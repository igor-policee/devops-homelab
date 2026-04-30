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
- Kubernetes target minor version: `1.35`
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

Package delivery note:

- this environment may have unreliable access to `pkgs.k8s.io` for large package downloads
- repository metadata can still work while `.deb` payload downloads time out
- if package installation fails during the manual pass, record the failure and switch to an alternate package source outside the cluster
- the selected fallback source is the GitLab project `k8s-bootstrap-artifacts` using the GitLab Generic Package Registry

Recommended validation from the repository root:

```bash
ssh homelab-ubuntu 'for host in control-plane worker-1 worker-2; do ssh "$host" hostname; done'
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

Project decision for this phase:

- use Kubernetes minor version `1.35`
- keep the same minor version for the later Ansible automation pass so the manual notes and automation stay aligned
- the fallback package source design is:
  - GitLab project: `k8s-bootstrap-artifacts`
  - package name: `kubernetes-debs`
  - package version: `v1.35.4`
- after installing the package set from fallback artifacts, keep these packages on hold:
  - `kubeadm`
  - `kubelet`
  - `kubectl`
  - `cri-tools`
  - `kubernetes-cni`
- after the fallback installation, disable the upstream Kubernetes apt source on the node for this phase to avoid accidental dependency on `pkgs.k8s.io`

Validated installation approach for this environment:

```bash
mkdir -p ~/k8s-bootstrap/v1.35.4
cd ~/k8s-bootstrap/v1.35.4

export GITLAB_TOKEN='YOUR_TOKEN_HERE'
export GITLAB_PROJECT_ID='81772984'
export GITLAB_API='https://gitlab.com/api/v4'
export GITLAB_PACKAGE_NAME='kubernetes-debs'
export GITLAB_PACKAGE_VERSION='v1.35.4'

for file in \
  cri-tools_1.35.0-1.1_amd64.deb \
  kubeadm_1.35.4-1.1_amd64.deb \
  kubectl_1.35.4-1.1_amd64.deb \
  kubelet_1.35.4-1.1_amd64.deb \
  kubernetes-cni_1.8.0-1.1_amd64.deb \
  SHA256SUMS
do
  curl --fail --location \
    --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
    --output "$file" \
    "$GITLAB_API/projects/$GITLAB_PROJECT_ID/packages/generic/$GITLAB_PACKAGE_NAME/$GITLAB_PACKAGE_VERSION/$file"
done

sha256sum -c SHA256SUMS

sudo dpkg -i \
  cri-tools_1.35.0-1.1_amd64.deb \
  kubernetes-cni_1.8.0-1.1_amd64.deb \
  kubelet_1.35.4-1.1_amd64.deb \
  kubectl_1.35.4-1.1_amd64.deb \
  kubeadm_1.35.4-1.1_amd64.deb

sudo apt-mark hold kubelet kubeadm kubectl cri-tools kubernetes-cni

if [ -f /etc/apt/sources.list.d/kubernetes.list ]; then
  sudo mv /etc/apt/sources.list.d/kubernetes.list /etc/apt/sources.list.d/kubernetes.list.disabled
fi

sudo apt-get update
sudo systemctl enable --now kubelet
```

Validation:

```bash
kubeadm version
kubelet --version
kubectl version --client
apt-mark showhold | grep -E 'kubeadm|kubectl|kubelet|cri-tools|kubernetes-cni'
```

Note:

- it is normal for `kubelet` to restart repeatedly before `kubeadm init` or `kubeadm join`
- the GitLab-hosted package flow is the primary installation path for this project phase

Observed result from this session:

- direct large `.deb` downloads from `pkgs.k8s.io` timed out from the project location
- repository metadata remained reachable even while payload downloads failed
- the fallback GitLab package source worked correctly for downloading and validating the bootstrap package set
- the Kubernetes package set was installed from local `.deb` files on the nodes
- `kubelet` entered an auto-restart loop before `kubeadm init`, which is expected at this stage

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

After a successful init, configure `kubectl` on `homelab-ubuntu`, because the host is the main execution point for `kubectl` in this lab:

```bash
mkdir -p ~/.kube
ssh control-plane 'sudo cat /etc/kubernetes/admin.conf' > ~/.kube/config
chmod 600 ~/.kube/config
```

Capture the worker join command printed by `kubeadm init`. If needed, you can regenerate it later with:

```bash
sudo kubeadm token create --print-join-command
```

Validated observations from this session:

- `kubeadm init` reported that upstream already advertised `v1.36.0`, then correctly fell back to `stable-1.35`
- the actual initialized cluster version was `v1.35.4`
- `kubelet` became healthy after `kubeadm` wrote `/var/lib/kubelet/config.yaml` and kubeadm-managed flags
- before CNI installation, `kubectl get nodes -o wide` showed only `control-plane` and that node was `NotReady`
- before CNI installation, `kubectl get pods -A -o wide` showed `CoreDNS` as `Pending` and the control-plane static Pods as `Running`

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

Validated observations from this session:

- both `worker-1` and `worker-2` completed TLS bootstrap successfully
- both workers were able to read the `kubeadm-config` ConfigMap from `kube-system`
- after both joins, all three nodes appeared in `kubectl get nodes -o wide`
- before CNI installation, all nodes remained `NotReady`, which was expected

Validation on `homelab-ubuntu`:

```bash
kubectl get nodes -o wide
```

Expected result before CNI:

- all three nodes appear in the cluster
- nodes may remain `NotReady` until the CNI is installed

## 6. Install Cilium

Run on `homelab-ubuntu`.

This project uses Cilium as the Kubernetes CNI. For the manual training pass, install it with Helm so the steps stay visible and easy to map into later automation.

Install Helm if it is not already present:

```bash
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
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

Validated observations from this session:

- Helm was available on `homelab-ubuntu` as `v3.20.2`
- `helm install cilium ... --version 1.19.3 --namespace kube-system` completed successfully
- `cilium`, `cilium-envoy`, and `cilium-operator` Pods reached `Running`
- `kubectl get nodes -o wide` showed `control-plane`, `worker-1`, and `worker-2` as `Ready`
- `CoreDNS` transitioned from `Pending` before CNI to `Running` after the Cilium install

## 7. Optional Cilium CLI validation

Run on `homelab-ubuntu` if you want a stronger post-install check.

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

- the exact `kubeadm init` arguments
- the pod CIDR
- the validated Cilium chart version
- any extra fixes required on Ubuntu 24.04 guests
- the chosen fallback package-delivery method if the upstream Kubernetes CDN is unreliable

Validated values from this session:

- `kubeadm init` arguments:
  - `--apiserver-advertise-address=192.168.122.10`
  - `--pod-network-cidr=10.244.0.0/16`
- Kubernetes version: `v1.35.4`
- validated Cilium chart version: `1.19.3`
- operational `kubectl` execution point: `homelab-ubuntu`
- pre-init `kubelet` restart loop cause:
  - `/var/lib/kubelet/config.yaml` did not exist yet
- post-CNI cluster state:
  - all three nodes `Ready`
  - `CoreDNS` `Running`

## Fallback package source layout

The selected GitLab fallback source for the current package set:

- project: `k8s-bootstrap-artifacts`
- package name: `kubernetes-debs`
- package version: `v1.35.4`

Expected files:

- `cri-tools_1.35.0-1.1_amd64.deb`
- `kubeadm_1.35.4-1.1_amd64.deb`
- `kubectl_1.35.4-1.1_amd64.deb`
- `kubelet_1.35.4-1.1_amd64.deb`
- `kubernetes-cni_1.8.0-1.1_amd64.deb`

Recommended supporting files:

- `SHA256SUMS`
- a short manifest file that records the package set used for the manual and first automated bootstrap

## Post-install package pinning

After installing Kubernetes packages from the GitLab fallback source on a node:

```bash
sudo apt-mark hold kubelet kubeadm kubectl cri-tools kubernetes-cni
sudo mv /etc/apt/sources.list.d/kubernetes.list /etc/apt/sources.list.d/kubernetes.list.disabled
sudo apt-get update
```

Why this step exists:

- it prevents routine `apt upgrade` runs from drifting the tested bootstrap package set
- it removes the unstable direct dependency on `pkgs.k8s.io` during this project phase
- it keeps the manual flow aligned with the intended first Ansible implementation

## Validation loop for all nodes

Use this check from `homelab-ubuntu` after the package installation step:

```bash
for host in control-plane worker-1 worker-2; do
  ssh "$host" '
    echo "==== $(hostname) ===="
    kubeadm version
    kubelet --version
    kubectl version --client
    apt-mark showhold | grep -E "kubeadm|kubectl|kubelet|cri-tools|kubernetes-cni"
    systemctl is-enabled kubelet
    systemctl is-active kubelet
  '
done
```

Expected result at this stage:

- all package version commands succeed
- all five bootstrap packages appear in the hold list
- `kubelet` is `enabled`
- `kubelet` may show `activating` or restart repeatedly before `kubeadm init` and `kubeadm join`

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
