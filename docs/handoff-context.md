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
- Ansible host bootstrap now manages the libvirt `default` network and `default` storage pool
- The `kvm_libvirt` role now pins all `virsh` calls to `qemu:///system`
- OpenTofu is installed on `homelab-ubuntu`
- The repository working tree was copied to `homelab-ubuntu` at `~/devops-homelab`
- OpenTofu provider access works on the host through an offline mirror configuration
- `terraform/libvirt/terraform.tfvars` now exists locally with:
  - `ubuntu_image_source` set to the Ubuntu Noble cloud image URL
  - `vm_ssh_username = "admin"`
  - a dedicated VM SSH public key, separate from the host SSH key
- `tofu init` and `tofu plan` were successfully verified on `homelab-ubuntu`

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
- `virsh -c qemu:///system net-info default` shows the `default` network as active and persistent
- `virsh -c qemu:///system pool-info default` shows the `default` storage pool as running and persistent

## Architecture Decisions

- Host network uplink: WiFi only
- VM networking: `libvirt` NAT network
- No bridge networking because host uses WiFi
- No public ports exposed
- No port forwarding
- Tailscale will be configured only at the final remote-access phase
- VM disks were increased from `40 GiB` to `100 GiB`
- VM SSH access should use:
  - a neutral shared admin account (`admin`)
  - a dedicated VM SSH keypair
  - no reuse of the host SSH key

## Minimal Automation Stack

- Ansible: host bootstrap, VM configuration, kubeadm workflow
- OpenTofu + libvirt provider: VM provisioning
- Helm: Kubernetes package installation
- ArgoCD: GitOps
- SOPS + age: secrets in Git
- GitHub Actions: CI checks

## OpenTofu Execution Model

OpenTofu now runs on `homelab-ubuntu`, not on the workstation.

Important host-side details:
- the repo copy used for execution is `~/devops-homelab`
- `tofu` uses `qemu:///system`
- provider installation from `registry.opentofu.org` is blocked from the host, so an offline provider mirror is used instead
- the mirror config file on the host is:
  - `~/.config/opentofu/offline.tfrc`
- commands on the host should therefore be run like:

```bash
TF_CLI_CONFIG_FILE=$HOME/.config/opentofu/offline.tfrc tofu init -input=false -no-color
TF_CLI_CONFIG_FILE=$HOME/.config/opentofu/offline.tfrc tofu plan -input=false -no-color
TF_CLI_CONFIG_FILE=$HOME/.config/opentofu/offline.tfrc tofu apply
```

## Roadmap Status

Phase 1 completed:
- Install Ubuntu Server 24.04 LTS
- Connect host to WiFi
- Reserve LAN IP `192.168.1.100` on the router
- Configure SSH access
- Harden SSH to key-based authentication only
- Install KVM / libvirt with Ansible
- Validate `kvm-ok`, `libvirtd`, the default NAT network, the default storage pool, and non-root `virsh -c qemu:///system` access on the host
- Install OpenTofu on `homelab-ubuntu`
- Prepare `terraform.tfvars`
- Verify `tofu init` and `tofu plan`

Phase 1 pending:
- Successfully complete `tofu apply`
- Boot all 3 VMs with working guest networking and DHCP leases

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
- manual verification commands must use `virsh -c qemu:///system`
- known quirk: repeated Ansible runs may still report `changed` for `libvirtd` even when it is already enabled and running
- Tailscale moved to the final phase
- VM disk sizes are now documented as `100GB`

## Current Blocker

The main blocker is no longer `tofu`, provider installation, or libvirt permissions. The current blocker is guest networking inside the VM after boot.

Observed facts:
- `tofu init` succeeds via the offline provider mirror
- `tofu plan` succeeds
- `tofu apply` creates:
  - base volume
  - VM overlay disks
  - cloud-init ISOs
  - DHCP reservations
  - libvirt domains
- VM domains start and reach the guest OS boot process
- the guest serial console on `control-plane` showed repeated waiting on:
  - `systemd-networkd-wait-online.service`
- no VM obtains a DHCP lease
- `virsh -c qemu:///system net-dhcp-leases default` remains empty
- `virsh -c qemu:///system domifaddr <vm>` returns no addresses
- `virsh -c qemu:///system net-dumpxml default` does show the expected DHCP reservations
- `dnsmasq` host entries exist in `/var/lib/libvirt/dnsmasq/default.hostsfile`

Interpretation:
- host-side libvirt networking appears correct
- the issue is likely inside the guest networking/bootstrap path, not in the host `libvirt` network definition

## Security / AppArmor Findings

During this session there was an earlier libvirt/QEMU failure:
- `Could not open '/var/lib/libvirt/images/ubuntu-base-....qcow2': Permission denied`

Findings from that investigation:
- plain file permissions did not cleanly explain the failure
- AppArmor profiles existed in `/etc/apparmor.d/libvirt`
- the generated profiles did not contain the backing image path
- `security_driver = "none"` was used as a pragmatic way to get past the backing-image access issue during diagnosis

Practical takeaway:
- if QEMU backing-file permission errors reappear later, re-check the current `libvirt` security driver and AppArmor interaction first

## Diagnostic File Changes Made During This Session

There are local, uncommitted diagnostic changes in the Terraform/libvirt stack intended to isolate the guest networking problem.

Current local diagnostics include:
- [terraform/libvirt/main.tf](/home/ipolishchuk/repo/devops-homelab/terraform/libvirt/main.tf:22)
  - `network_config` was temporarily removed from `libvirt_cloudinit_disk`
- [terraform/libvirt/templates/network-config.tftpl](/home/ipolishchuk/repo/devops-homelab/terraform/libvirt/templates/network-config.tftpl:1)
  - `set-name: ens3` was removed earlier during diagnosis
- [terraform/libvirt/templates/user-data.tftpl](/home/ipolishchuk/repo/devops-homelab/terraform/libvirt/templates/user-data.tftpl:1)
  - temporary `runcmd` diagnostics were added to print network and cloud-init state into the guest serial console

These changes were made for debugging and may or may not be retained in the final solution.

## Notes For Next Chat

The next chat should resume from the current guest-networking blocker, not from OpenTofu bootstrap.

What is already done:
- host bootstrap is done
- OpenTofu is installed on `homelab-ubuntu`
- the repo exists on `homelab-ubuntu`
- offline provider mirror is configured
- `terraform.tfvars` is prepared
- `tofu init` and `tofu plan` work
- `tofu apply` reaches VM boot

What needs to happen next:
1. Continue guest-networking diagnosis from the current serial-console evidence
2. Determine why the guest stalls on `systemd-networkd-wait-online.service`
3. Decide whether the final fix should be:
   - a corrected cloud-init `network_config`
   - no explicit `network_config` at all
   - an adjusted guest network renderer / netplan behavior
4. Once a VM gets a DHCP lease successfully, re-run `tofu apply`
5. After guest networking works, move on to Ansible for VM configuration

Suggested immediate diagnostic direction:
- continue inspecting guest-side networking behavior rather than changing host-side libvirt networking again
- focus on:
  - guest serial console output
  - cloud-init-generated network files
  - netplan / systemd-networkd state inside the guest

## Repository State

Relevant commit from this session:
- `3724e30` — `terraform: increase vm disk sizes to 100gb`

Relevant older commits:
- `c353220` — `chore: replace terraform references with opentofu`
- `fff267b` — `ansible: manage default libvirt storage pool`
- `f83ee9e` — `ansible: pin libvirt role to system URI`
- `93b3931` — `ansible: use systemd module for libvirt service`
- `107de85` — `docs: clarify libvirt system URI checks`

Current local worktree notes:
- `docs/handoff-context.md` is intentionally updated to capture the current debugging state
- multiple `terraform/libvirt/*` files are still untracked or locally modified in the workstation repo
- the host copy at `~/devops-homelab` should be treated as the operational copy for current OpenTofu work
