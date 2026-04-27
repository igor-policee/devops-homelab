variable "libvirt_uri" {
  description = "Libvirt connection URI for the hypervisor."
  type        = string
  default     = "qemu:///system"
}

variable "network_name" {
  description = "Existing libvirt network that backs the Kubernetes VMs."
  type        = string
  default     = "default"
}

variable "storage_pool" {
  description = "Libvirt storage pool used for the base image, cloud-init seed ISOs, and VM disks."
  type        = string
  default     = "default"
}

variable "ubuntu_image_source" {
  description = "Ubuntu cloud image URL or absolute local file path."
  type        = string
}

variable "vm_ssh_username" {
  description = "Guest username that cloud-init will create and seed with the provided SSH key."
  type        = string
}

variable "vm_ssh_public_key" {
  description = "SSH public key injected into every guest through cloud-init."
  type        = string
  sensitive   = true
}
