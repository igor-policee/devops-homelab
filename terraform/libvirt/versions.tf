terraform {
  required_version = ">= 1.5.0"

  required_providers {
    libvirt = {
      # This provider version matches the cloud-init workflow used by this stack.
      source  = "dmacvicar/libvirt"
      version = "= 0.8.1"
    }
  }
}
