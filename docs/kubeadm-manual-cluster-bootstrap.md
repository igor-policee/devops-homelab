# Kubernetes kubeadm manual cluster bootstrap

This runbook documents a manual Kubernetes installation on the libvirt guests before the same flow is automated with Ansible.

Goal:

- practice a clean `kubeadm` bootstrap by hand
- record the exact commands and checkpoints
- use the verified flow as the source for later Ansible roles and playbooks

Scope:

- Ubuntu 24.04 guest nodes created by the OpenTofu libvirt stack
- one control-plane node: `control-plane`
- two worker nodes: `worker-1`, `worker-2`
- container runtime: `containerd`
- CNI: Cilium

Expected guest IPs:

- `control-plane` -> `192.168.122.10`
- `worker-1` -> `192.168.122.11`
- `worker-2` -> `192.168.122.12`

## Before you begin

Assumptions:

- the host-side KVM/libvirt bootstrap is already complete
- the guests were created with the OpenTofu stack in `terraform/libvirt/`
- SSH access to all guests works with the `homelab` user
- commands below are run on the guest VMs unless stated otherwise

Recommended validation from the repository root:

```bash
cd ansible
ansible kubernetes -m ping
```

If this fails, fix guest access first. Do not continue with `kubeadm` until all three nodes are reachable.

## 1. Prepare all nodes

Run the following on `control-plane`, `worker-1`, and `worker-2`.

Update packages:

```bash
sudo apt-get update
sudo apt-get upgrade -y
```

Disable swap immediately:

```bash
sudo swapoff -a
```

Disable swap persistently by commenting swap entries in `/etc/fstab`:

```bash
sudo sed -i.bak '/\sswap\s/s/^/#/' /etc/fstab
```

Load the kernel modules required by Kubernetes networking:

```bash
cat <<'EOF' | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter
```

Configure sysctls required by Kubernetes and bridged traffic inspection:

```bash
cat <<'EOF' | sudo tee /etc/sysctl.d/99-kubernetes-cri.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sudo sysctl --system
```

Validation:

```bash
lsmod | grep -E 'overlay|br_netfilter'
sysctl net.ipv4.ip_forward
swapon --show
```

Expected result:

- both kernel modules are loaded
- `net.ipv4.ip_forward = 1`
- `swapon --show` returns no active swap devices

## 2. Install and configure containerd

Run on all nodes.

Install `containerd` from Ubuntu packages:

```bash
sudo apt-get install -y containerd
```

Generate a default config and switch the runtime to the `systemd` cgroup driver:

```bash
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml >/dev/null
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
```

Enable and restart the service:

```bash
sudo systemctl enable containerd
sudo systemctl restart containerd
```

Validation:

```bash
sudo systemctl status containerd --no-pager
grep -n 'SystemdCgroup = true' /etc/containerd/config.toml
```

## 3. Install kubeadm, kubelet, and kubectl

Run on all nodes.

At the time this runbook was written on April 29, 2026, the current Kubernetes installation page targets the `v1.35` package repository. If you intentionally want another supported minor version, replace `v1.35` below with that version everywhere before installing packages.

Install repository prerequisites:

```bash
sudo apt-get update
sudo apt-get install -y apt-transport-https ca-certificates curl gpg
sudo mkdir -p -m 755 /etc/apt/keyrings
```

Add the Kubernetes package signing key and repository:

```bash
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.35/deb/Release.key | \
  sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.35/deb/ /' | \
  sudo tee /etc/apt/sources.list.d/kubernetes.list
```

Install Kubernetes packages and pin them:

```bash
sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl
sudo systemctl enable --now kubelet
```

Validation:

```bash
kubeadm version
kubelet --version
kubectl version --client
```

Note:

- it is normal for `kubelet` to restart repeatedly before `kubeadm init` or `kubeadm join`

## 4. Initialize the control plane

Run only on `control-plane`.

Confirm the node IP that Kubernetes should advertise:

```bash
ip -4 addr show
ip route show
```

For this lab, the control-plane address should be `192.168.122.10`.

Initialize the cluster:

```bash
sudo kubeadm init \
  --apiserver-advertise-address=192.168.122.10 \
  --pod-network-cidr=10.244.0.0/16
```

Why `10.244.0.0/16`:

- it does not overlap with the documented libvirt NAT subnet `192.168.122.0/24`
- it keeps the pod network explicit in the notes instead of relying on defaults

After a successful init, configure `kubectl` for the `homelab` user:

```bash
mkdir -p "$HOME/.kube"
sudo cp -i /etc/kubernetes/admin.conf "$HOME/.kube/config"
sudo chown "$(id -u)":"$(id -g)" "$HOME/.kube/config"
```

Capture the worker join command printed by `kubeadm init`. If needed, you can regenerate it later with:

```bash
sudo kubeadm token create --print-join-command
```

Validation:

```bash
kubectl get nodes
kubectl get pods -A
```

Expected result before CNI:

- `control-plane` exists as a node
- CoreDNS is not fully running yet
- worker nodes are not joined yet

## 5. Join the worker nodes

Run the saved `kubeadm join ...` command on `worker-1` and `worker-2` with `sudo`.

Example shape:

```bash
sudo kubeadm join 192.168.122.10:6443 --token <token> \
  --discovery-token-ca-cert-hash sha256:<hash>
```

Validation on the control-plane node:

```bash
kubectl get nodes -o wide
```

Expected result before CNI:

- all three nodes appear in the cluster
- nodes may remain `NotReady` until the CNI is installed

## 6. Install Cilium

Run on `control-plane`.

This project uses Cilium as the Kubernetes CNI. For the manual training pass, install it with Helm so the steps stay visible and easy to map into later automation.

Install Helm if it is not already present:

```bash
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

Install Cilium from the OCI registry:

```bash
helm install cilium oci://quay.io/cilium/charts/cilium \
  --version 1.19.3 \
  --namespace kube-system
```

Validation:

```bash
kubectl get pods -n kube-system
kubectl get nodes
```

Expected result:

- Cilium pods start on all nodes
- CoreDNS becomes `Running`
- all nodes transition to `Ready`

## 7. Optional Cilium CLI validation

Run on `control-plane` if you want a stronger post-install check.

Install the CLI:

```bash
CILIUM_CLI_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/cilium-cli/main/stable.txt)
CLI_ARCH=amd64
if [ "$(uname -m)" = "aarch64" ]; then CLI_ARCH=arm64; fi
curl -L --fail --remote-name-all \
  https://github.com/cilium/cilium-cli/releases/download/${CILIUM_CLI_VERSION}/cilium-linux-${CLI_ARCH}.tar.gz{,.sha256sum}
sha256sum --check cilium-linux-${CLI_ARCH}.tar.gz.sha256sum
sudo tar xzvfC cilium-linux-${CLI_ARCH}.tar.gz /usr/local/bin
rm cilium-linux-${CLI_ARCH}.tar.gz{,.sha256sum}
```

Run the status check:

```bash
cilium status --wait
```

## 8. Record outputs for the Ansible phase

Capture these values from the manual bootstrap because the later Ansible work will need to reproduce them:

- package repository minor version used for Kubernetes
- the exact `kubeadm init` arguments
- the pod CIDR
- the validated Cilium chart version
- any extra fixes required on Ubuntu 24.04 guests

Minimal state snapshot:

```bash
kubectl get nodes -o wide
kubectl get pods -A
kubectl cluster-info
```

## 9. Reset before the automation pass

Once the manual training pass is complete and your notes are saved, destroy and recreate the VMs with OpenTofu instead of trying to partially clean the guests by hand.

From the host copy of the repository:

```bash
cd ~/devops-homelab/terraform/libvirt
TF_CLI_CONFIG_FILE=$HOME/.config/opentofu/offline.tfrc tofu destroy
TF_CLI_CONFIG_FILE=$HOME/.config/opentofu/offline.tfrc tofu apply
```

Then rerun the guest baseline validation:

```bash
cd ~/devops-homelab/ansible
ansible-playbook playbooks/guest-bootstrap.yml
```

After that, the next implementation target is Ansible automation for:

- common Kubernetes prerequisites
- control-plane initialization
- worker join workflow
- Cilium installation
