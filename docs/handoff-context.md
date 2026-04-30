# DevOps Homelab — Handoff Context

## Current Status

Project: single-host DevOps homelab on Ubuntu Server 24.04 LTS with WiFi uplink, KVM/libvirt, and a kubeadm-based Kubernetes cluster that has now been validated manually before Ansible automation.

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
- a full manual Kubernetes bootstrap was completed successfully on the current guests
- after the manual training pass, the guests were destroyed and recreated successfully with a fresh `tofu apply`
- the recreated guests were revalidated over SSH at the expected addresses:
  - `control-plane` -> `192.168.122.10`
  - `worker-1` -> `192.168.122.11`
  - `worker-2` -> `192.168.122.12`
- the repository now contains a first Ansible automation scaffold for the Kubernetes phase:
  - `ansible/playbooks/kubernetes-bootstrap.yml`
  - `ansible/roles/kubernetes_guest_prep`
  - `ansible/roles/kubernetes_packages`
  - `ansible/roles/kubeadm_control_plane`
  - `ansible/roles/kubeadm_worker_join`
  - `ansible/roles/cilium_install`
- `kubeadm init` was validated on `control-plane` with:
  - `--apiserver-advertise-address=192.168.122.10`
  - `--pod-network-cidr=10.244.0.0/16`
- `kubeadm join` was validated on both worker nodes
- the cluster reached `Ready` on all nodes after installing Cilium `1.19.3`
- `kubectl` administration for the manual phase now runs from `homelab-ubuntu` using a local copy of `admin.conf`

Current access model:
- Local SSH from home LAN works
- External remote access via Tailscale is intentionally postponed to the final stage
- Recreated guests required SSH host-key refresh on `homelab-ubuntu` before new sessions could be established

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
  - after local installation from fallback artifacts, keep `kubeadm`, `kubelet`, `kubectl`, `cri-tools`, and `kubernetes-cni` on hold
  - disable `/etc/apt/sources.list.d/kubernetes.list` on the nodes after the fallback installation for this phase
- Manual cluster administration decision:
  - use `homelab-ubuntu` as the main `kubectl` and Helm execution point
  - keep the control-plane VM as the source of `/etc/kubernetes/admin.conf`
- Manual bootstrap validation result:
  - `kubeadm init` on Kubernetes `v1.35.4` completed successfully even though upstream already advertised `v1.36.0`
  - the observed pre-CNI state was `NotReady` nodes with `CoreDNS` pending
  - the observed post-Cilium state was all nodes `Ready` with `CoreDNS` running

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

Current automation-execution caveats on `homelab-ubuntu`:
- `~/devops-homelab` is an operational copy, not a Git checkout
- `ansible` is not currently installed there yet
- `sudo` on `homelab-ubuntu` still requires a password, so future host-side playbook runs should expect `ansible-playbook -K`

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

Provisioning state:
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

## Notes For Next Chat

The next chat should resume from the Ansible automation phase, not from manual `kubeadm` bootstrap or OpenTofu provisioning.

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
- the GitLab fallback source for Kubernetes bootstrap artifacts is created:
  - project: `igor-policee/k8s-bootstrap-artifacts`
  - project id: `81772984`
  - package name: `kubernetes-debs`
  - package version: `v1.35.4`
- the Kubernetes `1.35.4` bootstrap package set was uploaded to the GitLab Generic Package Registry
- the package set was validated through GitLab download URLs and checksum verification
- the bootstrap package set was installed on the current nodes from GitLab-hosted `.deb` files instead of direct `pkgs.k8s.io` payload downloads
- the nodes were configured to keep `kubeadm`, `kubelet`, `kubectl`, `cri-tools`, and `kubernetes-cni` on hold
- the upstream Kubernetes apt source was disabled on the nodes for this phase after the fallback installation
- `kubelet` restart loops before `kubeadm init` / `kubeadm join` were observed and confirmed to be expected while `/var/lib/kubelet/config.yaml` was still absent
- `kubeadm init` succeeded with:
  - Kubernetes version `v1.35.4`
  - advertise address `192.168.122.10`
  - pod CIDR `10.244.0.0/16`
- the worker join flow succeeded on `worker-1` and `worker-2`
- `kubectl get nodes -o wide` reached:
  - `control-plane` -> `Ready`
  - `worker-1` -> `Ready`
  - `worker-2` -> `Ready`
- Cilium `1.19.3` was installed successfully through Helm from `homelab-ubuntu`
- `CoreDNS` transitioned from `Pending` before CNI to `Running` after Cilium was installed
- after the manual pass, `tofu destroy` and a fresh `tofu apply` were completed successfully
- `virsh -c qemu:///system list --all`, `net-dhcp-leases default`, and `domifaddr` re-confirmed the recreated guests at `.10`, `.11`, and `.12`
- SSH access to the recreated guests was revalidated from `homelab-ubuntu`
- `cloud-init status --wait` completed successfully on all recreated guests
- the first Ansible automation scaffold for the Kubernetes phase was added locally and passed `ansible-playbook --syntax-check`
- the updated `ansible/` tree, `README.md`, and `docs/handoff-context.md` were synced to the operational copy at `~/devops-homelab`
- the control-plane automation now auto-recovers from partial failed `kubeadm init` attempts by running `kubeadm reset -f` before retrying `kubeadm init` while `admin.conf` is still absent

What needs to happen next:
1. Install Ansible on `homelab-ubuntu` so the new automation playbook can run from the documented execution point
2. Run `ansible/playbooks/kubernetes-bootstrap.yml` with `GITLAB_TOKEN` exported and `-K` enabled
3. Validate the automated cluster bootstrap end-to-end with:
   - `kubectl get nodes -o wide`
   - `kubectl get pods -A`
   - `helm list -n kube-system`
   - confirm that control-plane recovery is clean if a previous failed `kubeadm init` left `kubelet` listening on `:10250`
4. Reproduce the validated control-plane arguments in automation:
   - `--apiserver-advertise-address=192.168.122.10`
   - `--pod-network-cidr=10.244.0.0/16`
5. Reproduce the validated Cilium installation in automation with chart version `1.19.3`
6. Decide whether `kube-proxy` should remain enabled or later be replaced by a Cilium eBPF mode in a separate change

## Repository State

Recent relevant commits:
- `88b2532` — `docs: record manual package bootstrap progress`
- `169505b` — `docs: define gitlab fallback package source`
- `eae1d37` — `docs: pin kubernetes to 1.35`
- `5e2548b` — `docs: define manual kubeadm training phase`
- `eab3f9c` — `docs: mark vm provisioning complete`

Important older infrastructure commits:
- `632226c` — `terraform: add libvirt vm provisioning stack`
- `3724e30` — `terraform: increase vm disk sizes to 100gb`
- `c353220` — `chore: replace terraform references with opentofu`
- `fff267b` — `ansible: manage default libvirt storage pool`
- `f83ee9e` — `ansible: pin libvirt role to system URI`

Current local worktree notes:
- `ansible/inventory/hosts.yml` also has a local modification and should be reviewed separately before any commit
- `kubeadm-join-token` is an untracked local artifact from the manual pass and should not be committed
- the host copy at `~/devops-homelab` should still be treated as the operational copy for current OpenTofu and VM-side bootstrap work
- the local inventory change now includes the Kubernetes guest group plus the dedicated VM SSH key path
- the newly added automation files are now present in the host-side operational copy because they were synced manually
