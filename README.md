# DevOps Homelab

A local DevOps lab built on a single physical host with remote access and a Kubernetes cluster.

## 🎯 Goal

Create a flexible, secure environment that is as close to production as possible for:

- working with Kubernetes (kubeadm)
- working with Docker / containerd
- configuring CI/CD
- experimenting with networking (Cilium, Gateway API)
- infrastructure as code (Ansible, OpenTofu)

---

## 🧱 Architecture

```
Client (any PC/laptop)
   ↓
Tailscale (VPN)
   ↓
Ubuntu Server 24.04 LTS (Host, WiFi)
   ↓
KVM / libvirt
   ↓
3 Virtual Machines
   ↓
Kubernetes (kubeadm cluster)
```

---

## 💻 Host (Physical Machine)

- CPU: Intel i7
- RAM: 32 GB
- GPU: RTX 3070 Ti
- OS: **Ubuntu Server 24.04 LTS**
- Network: WiFi 5 GHz (no Ethernet)

---

## 🌐 Network

- The host is connected to the internet via WiFi
- The host has a DHCP reservation on the router and currently uses the static LAN IP `192.168.1.100`
- Virtual machines use the **libvirt NAT network** (for example, `192.168.122.0/24`)
- Kubernetes virtual machines will use **DHCP reservations by MAC address inside the libvirt network** so each node keeps a stable IP
- Bridge networking is NOT used (due to WiFi limitations)

---

## 🔐 Access

Current bootstrap access:

- Local SSH access from the home LAN to `192.168.1.100` is configured
- The LAN IP is reserved on the router via DHCP reservation
- SSH access is hardened to key-only authentication

Target access model:

- Primary remote access from external networks will be added later with **Tailscale**
- No externally exposed ports
- A public IP is not used for incoming connections

---

## 🖥️ Virtual Machines

| Node            | CPU | RAM | Disk |
|-----------------|-----|-----|------|
| control-plane   | 2   | 4GB | 100GB |
| worker-1        | 3   | 6GB | 100GB |
| worker-2        | 3   | 6GB | 100GB |

Addressing model for the VM network:

- `libvirt` provides the NAT-backed subnet for the guests
- each VM gets a fixed MAC address
- IP addresses are assigned through DHCP reservation in `libvirt`, not by ad-hoc dynamic leases
- this keeps node IPs stable for Kubernetes while preserving simple VM networking

Planned VM IP assignments:

- `control-plane` → `192.168.122.10`
- `worker-1` → `192.168.122.11`
- `worker-2` → `192.168.122.12`

---

## ☸️ Kubernetes

- Planned cluster bootstrap tool: `kubeadm`
- Target Kubernetes minor version for the current project phase: `1.35`
- Container runtime: containerd
- CNI: Cilium
- kube-proxy: possibly disabled in favor of eBPF
- Manual bootstrap result for the current training pass:
  - `kubeadm init` and worker `kubeadm join` were validated successfully on Kubernetes `v1.35.4`
  - cluster administration from the host is performed on `homelab-ubuntu` with `kubectl`
  - the validated manual pod CIDR is `10.244.0.0/16`
  - the validated Cilium chart version is `1.19.3`
- Bootstrap packaging note:
  - direct access to `pkgs.k8s.io` may be unreliable from the project location
  - Kubernetes package delivery must not depend only on the upstream CDN
  - the project should support an alternate package source for manual bootstrap and Ansible automation
  - the selected fallback source is a dedicated GitLab project named `k8s-bootstrap-artifacts`
  - after installing Kubernetes packages from fallback artifacts, keep the bootstrap package set on `apt hold`
  - after installing from fallback artifacts, disable the upstream Kubernetes apt source on the nodes for this phase

---

## 🤖 Automation Stack

The project uses a minimal automation stack that covers the full path from the physical host to applications running inside Kubernetes.

| Area | Tool | Purpose |
|------|------|---------|
| Host bootstrap | Ansible | Install and configure SSH, Tailscale, KVM/libvirt, base packages |
| VM provisioning | OpenTofu + libvirt provider | Declaratively create the Kubernetes virtual machines |
| VM configuration | Ansible | Install containerd, kubeadm, and required system settings |
| Kubernetes bootstrap | Ansible + kubeadm | Initialize the control plane and join worker nodes |
| Kubernetes packages | Helm | Install and manage Cilium, ArgoCD, observability tools, and other charts |
| GitOps | ArgoCD | Continuously reconcile Kubernetes applications from Git |
| Secrets | SOPS + age | Store encrypted secrets safely in Git |
| CI checks | GitHub Actions | Validate OpenTofu, Ansible, YAML, and Helm changes before merge |

---

## 📁 Repository Structure

```text
devops-homelab/
├── README.md
├── ansible/
│   ├── inventory/
│   ├── playbooks/
│   └── roles/
├── terraform/
│   └── libvirt/
├── kubernetes/
│   ├── bootstrap/
│   ├── apps/
│   └── clusters/
├── scripts/
└── docs/
```

Important documents for the current phase:

- `docs/kvm-libvirt-bootstrap.md` - host-side KVM/libvirt bootstrap notes
- `docs/kubeadm-manual-cluster-bootstrap.md` - manual Kubernetes training runbook before Ansible automation

---

## ▶️ Command Order

Use the repository root as the working directory unless a step explicitly changes directories.

Prerequisites check:

```bash
ansible --version
tofu version
virsh --version
```

Run the physical host bootstrap:

```bash
cd ansible
ansible-playbook -K playbooks/host-bootstrap.yml
```

If the bootstrap adds the SSH user to the `libvirt` or `kvm` groups, reconnect your SSH session and verify the host state:

```bash
kvm-ok
virsh -c qemu:///system net-list --all
virsh -c qemu:///system pool-list --all
```

Bootstrap note:

- The `kvm_libvirt` role manages the host-wide libvirt daemon through `qemu:///system`. Use the same URI in manual verification commands, because plain `virsh` may resolve to `qemu:///session` for a regular user and show an empty libvirt state.
- On Ubuntu 24.04, repeated Ansible runs may still report `changed` for the `libvirtd` systemd unit even when it is already enabled and running. Treat that as a known idempotency quirk unless the task also returns an actual failure.

Plan and apply the VM provisioning stack:

```bash
cd ..
cd terraform/libvirt
cp terraform.tfvars.example terraform.tfvars
tofu init
tofu plan
tofu apply
```

Notes:

- The Ansible bootstrap command is expected to run from the repository `ansible/` directory so the repository-local `ansible.cfg` resolves `inventory/` and `roles/` correctly.
- OpenTofu must run on a machine where both `tofu` and `virsh` can reach the same libvirt daemon.
- The OpenTofu stack assumes the existing `default` libvirt network remains the source of truth for guest networking.
- The manual Kubernetes training pass should be performed from `homelab-ubuntu`, because that host can reach the `192.168.122.0/24` libvirt guest network directly.
- After `kubeadm init`, copy `/etc/kubernetes/admin.conf` from `control-plane` to `~/.kube/config` on `homelab-ubuntu` and use that host as the main `kubectl` execution point for the manual phase.

Run the first Ansible Kubernetes automation pass from `homelab-ubuntu` after a fresh `tofu apply`:

```bash
cd ~/devops-homelab/ansible
export GITLAB_TOKEN='YOUR_TOKEN_HERE'
ansible-playbook -K playbooks/kubernetes-bootstrap.yml
```

Automation notes:

- the Kubernetes automation playbook reproduces the validated manual flow in this order:
  - guest preparation
  - package bootstrap from GitLab-hosted `.deb` files
  - `kubeadm init`
  - worker join
  - Cilium install
- the first automation pass keeps Kubernetes pinned to `v1.35.4`, uses `10.244.0.0/16` as the pod CIDR, and installs Cilium `1.19.3`
- the playbook expects `GITLAB_TOKEN` on the Ansible control node and never stores the token in the repository
- `homelab-ubuntu` currently remains the intended execution point because it can reach the `192.168.122.0/24` guest network directly
- the final localhost automation play now installs operator tooling as needed:
  - `kubectl` from the validated GitLab fallback package source
  - `helm` from the official Helm binary release
- the final Cilium play now runs with `connection: local` on the Ansible control node instead of SSHing back into `homelab-ubuntu`
- after recreating guests with `tofu destroy` and `tofu apply`, refresh or accept the new SSH host keys before the first Ansible run
- the package bootstrap role keeps `kubelet` enabled but stopped on fresh nodes so `kubeadm init` and `kubeadm join` own the first clean `kubelet` start
- after `kubeadm init` and `kubeadm join`, the automation must explicitly return `kubelet` to `started` so node readiness and CNI pods can progress
- if a previous `kubeadm init` attempt left partial control-plane state behind, the automation now runs `kubeadm reset -f` automatically before retrying `kubeadm init` while `/etc/kubernetes/admin.conf` is still absent

---

## 🌍 External Access

At the current stage:

- ❌ No public services
- ❌ No port forwarding
- ❌ No open ports

Access to services:
- through the local network during bootstrap
- through NodePort / kubectl port-forward
- through Tailscale after the final remote-access phase

---

## 🧪 Roadmap

### Phase 1 — Base Infrastructure
- [x] Install Ubuntu Server 24.04 LTS
- [x] Connect the host to WiFi
- [x] Reserve LAN IP `192.168.1.100` on the router
- [x] Configure SSH access
- [x] Harden SSH to key-based authentication only
- [x] Install KVM / libvirt with Ansible
- [x] Create VMs with OpenTofu + libvirt provider

### Phase 2 — Manual Kubernetes Training
- [x] Use Kubernetes `1.35` for the manual training cluster
- [x] Record the `pkgs.k8s.io` connectivity limitation and the fallback package-delivery workflow
- [x] Publish the required Kubernetes `1.35.4` `.deb` artifacts to the GitLab fallback source
- [x] Validate node-local installation of Kubernetes bootstrap packages from the GitLab fallback source
- [x] Perform a manual `kubeadm` bootstrap and record the runbook
- [x] Validate worker joins and Cilium `1.19.3` until all nodes become `Ready`
- [x] Rebuild the guests with OpenTofu after the manual training pass

### Phase 3 — Kubernetes Automation
- [ ] Keep Kubernetes `1.35` in the Ansible automation until an explicit upgrade step is planned
- [ ] Support an alternate Kubernetes package source in Ansible instead of depending only on `pkgs.k8s.io`
- [ ] Download Kubernetes bootstrap packages from the GitLab fallback source in Ansible
- [ ] Install containerd and kubeadm with Ansible
- [ ] Bring up the control plane with kubeadm through Ansible
- [ ] Add worker nodes through Ansible
- [ ] Install CNI (Cilium) with Helm

### Phase 4 — Networking
- [ ] Configure Cilium Gateway API
- [ ] Ingress routing
- [ ] Service exposure (NodePort / internal)

### Phase 5 — DevOps Tools
- [ ] Helm
- [ ] GitOps with ArgoCD
- [ ] Secrets management with SOPS + age
- [ ] CI/CD with GitHub Actions

### Phase 6 — Observability
- [ ] Prometheus
- [ ] Grafana
- [ ] Loki

### Phase 7 — Remote Access
- [ ] Configure Tailscale for access from external networks

---

## 🧭 Deferred Tools

The following tools are intentionally not part of the initial stack:

- Packer: useful later for custom VM images, but not required at the start
- Vault: too heavy for this single-host homelab; SOPS + age is simpler
- Rancher: adds an extra management layer that is not needed yet
- Pulumi: valid alternative, but OpenTofu is more direct for libvirt VM provisioning
- Jenkins: GitHub Actions is simpler for lightweight repository checks

---

## ⚠️ Limitations

- WiFi instead of Ethernet → possible latency
- Single physical host → no real HA
- NAT network → no direct L2 interaction

---

## 🔒 Security

- No externally open ports
- No port forwarding
- Initial access is limited to the home LAN over SSH key authentication
- Target remote access is through VPN (Tailscale)
- Secrets are stored encrypted with SOPS + age
