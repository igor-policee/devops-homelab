output "vm_names" {
  description = "Names of the Kubernetes VM domains."
  value       = sort(keys(local.vm_inventory))
}

output "vm_mac_addresses" {
  description = "Fixed MAC addresses assigned to the Kubernetes VM NICs."
  value = {
    for name, vm in local.vm_inventory : name => vm.mac
  }
}

output "vm_reserved_ips" {
  description = "Reserved DHCP addresses for the Kubernetes VM NICs."
  value = {
    for name, vm in local.vm_inventory : name => vm.ip
  }
}

output "vm_connection_info" {
  description = "Per-node connection details for follow-up Ansible inventory work."
  value = {
    for name, vm in local.vm_inventory : name => {
      hostname = name
      ip       = vm.ip
      mac      = vm.mac
      ssh_user = var.vm_ssh_username
    }
  }
}
