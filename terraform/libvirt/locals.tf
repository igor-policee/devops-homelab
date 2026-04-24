locals {
  node_specs = {
    control-plane = {
      ip       = "192.168.122.10"
      mac      = "52:54:00:10:00:10"
      vcpu     = 2
      memory   = 4096
      disk_gib = 100
    }
    worker-1 = {
      ip       = "192.168.122.11"
      mac      = "52:54:00:10:00:11"
      vcpu     = 3
      memory   = 6144
      disk_gib = 100
    }
    worker-2 = {
      ip       = "192.168.122.12"
      mac      = "52:54:00:10:00:12"
      vcpu     = 3
      memory   = 6144
      disk_gib = 100
    }
  }

  vm_inventory = {
    for name, spec in local.node_specs : name => merge(spec, {
      disk_bytes = spec.disk_gib * 1024 * 1024 * 1024
    })
  }

  ubuntu_image_name = "ubuntu-base-${md5(var.ubuntu_image_source)}.qcow2"
}
