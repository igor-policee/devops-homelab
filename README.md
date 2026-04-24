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
| control-plane   | 2   | 4GB | 40GB |
| worker-1        | 3   | 6GB | 40GB |
| worker-2        | 3   | 6GB | 40GB |

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

- Installed with `kubeadm`
- Container runtime: containerd
- CNI: Cilium
- kube-proxy: possibly disabled in favor of eBPF

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

---

## 🚀 Implementation Order

1. Finish physical host bootstrap: KVM/libvirt and base packages.
2. Provision the virtual machines with OpenTofu and the libvirt provider.
3. Prepare the virtual machines with Ansible for Kubernetes usage.
4. Bootstrap the Kubernetes cluster with kubeadm through Ansible.
5. Install Cilium with Helm.
6. Install ArgoCD and move Kubernetes applications to GitOps.
7. Add observability with Prometheus, Grafana, and Loki.
8. Add Tailscale for remote access from external networks.

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
- [ ] Create VMs with OpenTofu + libvirt provider

### Phase 2 — Kubernetes
- [ ] Install containerd and kubeadm with Ansible
- [ ] Bring up the control plane with kubeadm
- [ ] Add worker nodes
- [ ] Install CNI (Cilium) with Helm

### Phase 3 — Networking
- [ ] Configure Cilium Gateway API
- [ ] Ingress routing
- [ ] Service exposure (NodePort / internal)

### Phase 4 — DevOps Tools
- [ ] Helm
- [ ] GitOps with ArgoCD
- [ ] Secrets management with SOPS + age
- [ ] CI/CD with GitHub Actions

### Phase 5 — Observability
- [ ] Prometheus
- [ ] Grafana
- [ ] Loki

### Phase 6 — Remote Access
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
