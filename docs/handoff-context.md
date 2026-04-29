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
  - `vm_ssh_username = "homelab"`
  - a dedicated VM SSH public key, separate from the host SSH key
- `tofu init`, `tofu plan`, `tofu apply`, and `tofu destroy` were successfully verified on `homelab-ubuntu`
- SSH access to all 3 guests was verified with the dedicated VM key and the `homelab` user
- a baseline Ansible guest-validation playbook now exists at `ansible/playbooks/guest-bootstrap.yml`

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
  - a neutral shared account (`homelab`)
  - a dedicated VM SSH keypair
  - no reuse of the host SSH key
- Kubernetes version target for the current phase:
  - use Kubernetes minor version `1.35`
  - use the same minor version for both the manual training pass and the first Ansible automation pass
  - do not upgrade to `1.36` during this phase unless that upgrade is planned explicitly
- Kubernetes package delivery constraint for the current phase:
  - direct downloads from `pkgs.k8s.io` may time out from the project location
  - repository metadata can still be reachable even when large `.deb` downloads fail
  - the bootstrap workflow therefore needs an alternate package source outside the cluster itself
- Selected fallback source design:
  - use a dedicated GitLab project named `k8s-bootstrap-artifacts`
  - store Kubernetes Debian packages in the GitLab Generic Package Registry
  - use package name `kubernetes-debs`
  - use package version `v1.35.4` for the current Kubernetes package set

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
- Verify `tofu init`, `tofu plan`, `tofu apply`, and `tofu destroy`

Phase 1 pending:
- Move on to the manual Kubernetes training pass on the current guests

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

## Current Status Of Provisioning

The earlier guest-networking blocker is resolved.

Observed facts from the successful validation cycle:
- `tofu apply` creates all expected resources:
  - base volume
  - VM overlay disks
  - cloud-init ISOs
  - DHCP reservations
  - libvirt domains
- all 3 VM domains boot and stay in `running` state
- `virsh -c qemu:///system net-dhcp-leases default` shows the expected addresses:
  - `control-plane` → `192.168.122.10`
  - `worker-1` → `192.168.122.11`
  - `worker-2` → `192.168.122.12`
- `virsh -c qemu:///system domifaddr <vm>` returns the same guest addresses
- guest networking remains reproducible across a full `tofu destroy` and `tofu apply` cycle

Resolved SSH bootstrap issue:
- guest SSH login with `vm_ssh_username = "admin"` failed even though networking and `sshd` were up
- offline inspection of the guest disk and cloud-init logs showed that the user was not created
- root cause from `cloud-init`:
  - `useradd: group admin exists - if you want to add this user to that group, use -g.`
- switching the guest username to `homelab` avoided the Ubuntu group-name conflict

Interpretation:
- host-side libvirt networking is functioning correctly
- guest networking is functioning correctly
- guest SSH bootstrap is functioning correctly with the `homelab` user

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

## Diagnostic Findings From This Session

The final diagnosis was not a libvirt or DHCP issue.

Confirmed guest-side findings:
- `ens3` comes up successfully
- the guest receives the expected DHCP lease
- `sshd` listens on `tcp/22`
- `cloud-init` reaches `DataSourceNoCloud [seed=/dev/sr0]`
- `cloud-init` fails in `users_groups` for username `admin`
- `/home/admin` is absent in the guest filesystem because the user was never created

## Notes For Next Chat

The next chat should resume from the manual `kubeadm` training pass, not from networking or OpenTofu bootstrap.

What is already done:
- host bootstrap is done
- OpenTofu is installed on `homelab-ubuntu`
- the repo exists on `homelab-ubuntu`
- offline provider mirror is configured
- `terraform.tfvars` is prepared
- `tofu init`, `tofu plan`, `tofu apply`, and `tofu destroy` work
- guest DHCP and VM boot are confirmed working
- guest SSH access is confirmed working with the `homelab` user
- `homelab-ubuntu` is the correct execution point for reaching the libvirt guest network directly

What needs to happen next:
1. Perform one manual `kubeadm` installation pass on the current guests and record every step in the dedicated runbook
2. Publish the required Kubernetes `1.35.4` bootstrap packages to the GitLab fallback source
3. Record the `pkgs.k8s.io` download-timeout issue and the chosen fallback workflow in the runbook
4. Capture real outputs and any Ubuntu 24.04-specific fixes from that pass
5. Recreate the guests with OpenTofu after the manual pass
6. Convert the validated manual workflow into Ansible roles and playbooks
7. Keep the Ansible inventory aligned with the confirmed VM addresses for the automation phase

## Manual kubeadm training pass

The immediate project goal is to practice a full Kubernetes installation manually before automating it.

Why this step exists:
- it creates a precise source workflow for the later Ansible implementation
- it keeps Kubernetes troubleshooting separate from Ansible troubleshooting
- it produces a reusable notes document for future rebuilds

Repository note:
- the manual runbook for this phase lives at `docs/kubeadm-manual-cluster-bootstrap.md`
- the intended sequence is manual cluster build on the current guests, then `tofu destroy` and `tofu apply`, then Ansible automation on fresh guests
- the manual pass should be executed from `homelab-ubuntu`, because the workstation environment does not directly reach the libvirt guest subnet
- Kubernetes `1.35` is the pinned project minor version for both the manual and first automated cluster build
- the package-source fallback must exist outside Kubernetes, because it is needed before the cluster exists
- the selected fallback package source is the GitLab project `k8s-bootstrap-artifacts`

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
