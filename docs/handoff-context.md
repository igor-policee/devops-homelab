# DevOps Homelab — Handoff Context

## Current Status

Project: single-host DevOps homelab on Ubuntu Server 24.04 LTS with WiFi uplink, KVM/libvirt, and a future kubeadm-based Kubernetes cluster.

Completed so far:
- Ubuntu Server 24.04 LTS installed on physical host
- Host connected to WiFi
- Static LAN IP reserved on router via DHCP reservation
- Current host IP: `192.168.1.100`
- SSH access configured
- SSH hardened to key-only authentication
- Initial Ansible scaffold for host bootstrap added to the repository
- KVM/libvirt installed and validated on the physical host

Current access model:
- Local SSH from home LAN works
- External remote access via Tailscale is intentionally postponed to the final stage

## SSH Details

Local SSH alias on workstation:
```sshconfig
Host homelab-ubuntu
    HostName 192.168.1.100
    User ipolishchuk
    IdentityFile ~/.ssh/id_ed25519_homelab-ubuntu
    IdentitiesOnly yes
```

Verified state:
- `ssh homelab-ubuntu` works
- password-based SSH login is disabled

## Architecture Decisions

- Host network uplink: WiFi only
- VM networking: `libvirt` NAT network
- No bridge networking because host uses WiFi
- No public ports exposed
- No port forwarding
- Tailscale will be configured only at the final remote-access phase

## Minimal Automation Stack

- Ansible: host bootstrap, VM configuration, kubeadm workflow
- Terraform + libvirt provider: VM provisioning
- Helm: Kubernetes package installation
- ArgoCD: GitOps
- SOPS + age: secrets in Git
- GitHub Actions: CI checks

## Roadmap Status

Phase 1 completed:
- Install Ubuntu Server 24.04 LTS
- Connect host to WiFi
- Reserve LAN IP `192.168.1.100` on the router
- Configure SSH access
- Harden SSH to key-based authentication only
- Install KVM / libvirt with Ansible
- Validate `kvm-ok`, `libvirtd`, the default NAT network, and non-root `virsh` access on the host

Phase 1 pending:
- Create VMs with Terraform + libvirt provider

Later phases remain unchanged:
- Kubernetes bootstrap with kubeadm
- Cilium
- GitOps
- Observability
- Final Tailscale setup for external access

## README Status

`README.md` reflects:
- current LAN IP
- SSH completed
- SSH key-only hardening completed
- KVM/libvirt host bootstrap completed
- Tailscale moved to the final phase

## Next Recommended Step

Prepare Terraform scaffolding for VM provisioning with the libvirt provider.

Immediate follow-up tasks:
1. Define the VM inventory for `control-plane`, `worker-1`, and `worker-2`
2. Assign fixed MAC addresses and DHCP reservations in the `libvirt` network
3. Prepare the Ubuntu cloud image, storage pool usage, and VM disk definitions
4. Scaffold Terraform files for `libvirt` domains, disks, and networking

## Notes For Next Chat

Goal for the next session:
- scaffold Terraform for VM creation on top of the verified KVM/libvirt host
- define MAC/IP assignments for the three Kubernetes nodes
- prepare the base image and storage approach for the VM disks

Important constraints:
- do not introduce Tailscale yet
- keep remote access limited to LAN SSH for now
