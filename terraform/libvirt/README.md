# OpenTofu libvirt scaffold

This stack provisions the three Kubernetes VMs on the existing `default` libvirt NAT network.

It creates:

- one reusable Ubuntu cloud image volume
- one qcow2 overlay disk per VM
- one cloud-init seed ISO per VM
- one libvirt domain per VM
- one DHCP reservation per VM through `virsh net-update`

## Inputs

Required values:

- `ubuntu_image_source`
- `vm_ssh_username`
- `vm_ssh_public_key`

Defaults:

- `libvirt_uri = "qemu:///system"`
- `network_name = "default"`
- `storage_pool = "default"`

## Usage

```bash
cd terraform/libvirt
cp terraform.tfvars.example terraform.tfvars
tofu init
tofu plan
tofu apply
```

## Notes

- This stack assumes the `default` libvirt network already exists and remains the network of record.
- DHCP reservations are managed through `virsh`, so `tofu apply` must run on a machine that has `virsh` access to the same libvirt daemon as OpenTofu.
- The stack pins `dmacvicar/libvirt` to `0.8.1` because that provider generation still matches the legacy `cloudinit` and domain workflow used here.
