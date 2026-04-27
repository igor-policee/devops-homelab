provider "libvirt" {
  uri = var.libvirt_uri
}

resource "libvirt_volume" "ubuntu_base" {
  name   = local.ubuntu_image_name
  pool   = var.storage_pool
  source = var.ubuntu_image_source
  format = "qcow2"
}

resource "libvirt_volume" "vm_disk" {
  for_each = local.vm_inventory

  name = "${each.key}.qcow2"
  pool = var.storage_pool
  # Use copy-on-write overlays so all nodes share the same downloaded base image.
  base_volume_id = libvirt_volume.ubuntu_base.id
  size           = each.value.disk_bytes
  format         = "qcow2"
}

resource "libvirt_cloudinit_disk" "seed" {
  for_each = local.vm_inventory

  name = "${each.key}-cloudinit.iso"
  pool = var.storage_pool

  user_data = templatefile("${path.module}/templates/user-data.tftpl", {
    hostname       = each.key
    ssh_username   = var.vm_ssh_username
    ssh_public_key = var.vm_ssh_public_key
  })

  meta_data = templatefile("${path.module}/templates/meta-data.tftpl", {
    hostname = each.key
  })
}

resource "terraform_data" "dhcp_reservation" {
  for_each = local.vm_inventory

  # Replace the reservation if any part of the identity tuple changes, because
  # libvirt tracks reservations by the full host XML entry.
  triggers_replace = [
    var.libvirt_uri,
    var.network_name,
    each.key,
    each.value.mac,
    each.value.ip,
  ]

  provisioner "local-exec" {
    command = "${path.module}/scripts/manage-dhcp-host.sh apply ${var.network_name} ${each.key} ${each.value.mac} ${each.value.ip}"

    environment = {
      VIRSH_DEFAULT_CONNECT_URI = var.libvirt_uri
    }
  }

  provisioner "local-exec" {
    when    = destroy
    command = "${path.module}/scripts/manage-dhcp-host.sh destroy ${self.triggers_replace[1]} ${self.triggers_replace[2]} ${self.triggers_replace[3]} ${self.triggers_replace[4]}"

    environment = {
      VIRSH_DEFAULT_CONNECT_URI = self.triggers_replace[0]
    }
  }
}

resource "libvirt_domain" "vm" {
  for_each = local.vm_inventory

  # Ensure reservations exist before the guests boot so wait_for_lease can
  # observe the expected static DHCP assignments.
  depends_on = [terraform_data.dhcp_reservation]

  name      = each.key
  memory    = each.value.memory
  vcpu      = each.value.vcpu
  autostart = true
  running   = true
  cloudinit = libvirt_cloudinit_disk.seed[each.key].id

  disk {
    volume_id = libvirt_volume.vm_disk[each.key].id
  }

  network_interface {
    network_name = var.network_name
    hostname     = each.key
    mac          = each.value.mac
    # Block apply until libvirt reports the guest lease; this gives a useful
    # readiness signal for later SSH and Ansible steps.
    wait_for_lease = true
  }

  console {
    type        = "pty"
    target_type = "serial"
    target_port = "0"
  }

  console {
    type        = "pty"
    target_type = "virtio"
    target_port = "1"
  }

  graphics {
    type        = "spice"
    listen_type = "address"
    autoport    = true
  }
}
