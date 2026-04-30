# Project Decisions

## 2026-04-30 — Position the project as a reproducible homelab, not a platform-first build

Decision:
- define the project as a reproducible Kubernetes homelab for hands-on practice, safe pre-production experimentation, and public demonstration of engineering quality
- prioritize engineering depth, reproducibility, and documentation quality over adding many tools quickly
- treat the current repository as a strong homelab baseline first, and only evolve it toward a platform as additional service-delivery and day-2 layers are added

Reason:
- the project needs to satisfy three real user goals at the same time:
  - learn and practice on real infrastructure
  - test ideas safely before proposing or applying them in an enterprise environment
  - show employers a serious, end-to-end engineering project on GitHub
- a platform label would currently overstate the scope, while a homelab baseline with strong automation and documentation already delivers practical value

Alternatives considered:
- position the project immediately as a full platform build
- treat the repository only as a personal learning sandbox without stronger engineering standards

Consequences:
- the next phases should focus on meaningful platform-like capabilities such as networking, GitOps, secrets, observability, and operational runbooks
- the project should avoid adding tools only for visual completeness or trend value
- documentation and operational clarity remain first-class deliverables, not secondary polish
## 2026-04-30 — Keep Kubernetes `1.35` for manual and first automated bootstrap

Decision:
- pin the current project phase to Kubernetes minor version `1.35`
- use package version `v1.35.4` for the validated manual bootstrap

Reason:
- the manual training pass and the first Ansible automation pass need to stay aligned
- `kubeadm init` confirmed that upstream already advertises `v1.36.0`, so an explicit pin avoids accidental drift during automation work

Alternatives considered:
- move immediately to Kubernetes `1.36`

Consequences:
- the automation phase should keep `1.35` until an explicit upgrade step is planned and documented
- validation and troubleshooting notes from the manual run remain directly reusable for Ansible

## 2026-04-30 — Use GitLab Generic Package Registry as the bootstrap package source

Decision:
- use the GitLab project `igor-policee/k8s-bootstrap-artifacts` as the fallback source for Kubernetes bootstrap packages
- keep package name `kubernetes-debs` and package version `v1.35.4`
- install `cri-tools`, `kubeadm`, `kubectl`, `kubelet`, and `kubernetes-cni` from the downloaded `.deb` files
- put those packages on `apt hold` and disable the upstream `kubernetes.list` source during this phase

Reason:
- large `.deb` downloads from `pkgs.k8s.io` are unreliable from the project location even when repository metadata remains reachable
- the bootstrap workflow needs a source that can be reused for both the manual and automated phases

Alternatives considered:
- depend only on direct `pkgs.k8s.io` downloads during bootstrap

Consequences:
- the first Ansible implementation must reproduce the same package-source, hold, and repo-disable behavior
- the project should avoid assuming stable access to the upstream Kubernetes CDN during bootstrap

## 2026-04-30 — Manage the manual cluster from `homelab-ubuntu`

Decision:
- use `homelab-ubuntu` as the main execution point for `kubectl`, Helm, and cluster validation during the manual phase
- copy `/etc/kubernetes/admin.conf` from `control-plane` to `~/.kube/config` on `homelab-ubuntu`

Reason:
- `homelab-ubuntu` can reach the `192.168.122.0/24` libvirt guest network directly
- keeping manual cluster administration on the host matches the OpenTofu execution model and reduces repeated SSH hops into the control-plane VM

Alternatives considered:
- manage the cluster interactively from the `control-plane` VM

Consequences:
- automation and runbooks should assume host-side control of `kubectl` during this phase
- the `control-plane` VM remains the source of `admin.conf`, but not the main operator shell

## 2026-04-30 — Run operator-side Kubernetes tooling locally on `homelab-ubuntu`

Decision:
- keep `homelab-ubuntu` as the operator shell for Ansible localhost tasks during the automation phase
- run the final Cilium installation play with `connection: local` instead of SSHing back into `homelab-ubuntu`
- install `kubectl` locally on `homelab-ubuntu` from the validated GitLab fallback package source
- install Helm locally on `homelab-ubuntu` from the official Helm binary release when it is missing or outside the validated version

Reason:
- the host can already reach the `192.168.122.0/24` libvirt guest network directly
- the localhost Ansible play should not depend on SSH host-key state for `homelab-ubuntu`
- the automation phase should prepare its own operator tooling instead of assuming `kubectl` and Helm are already present

Alternatives considered:
- keep the Cilium play on the `hypervisors` group and rely on SSH back into `homelab-ubuntu`
- require manual installation of `kubectl` and Helm outside the playbook

Consequences:
- localhost-scoped automation variables must be available outside the `kubernetes` host group
- the automation phase now owns operator-tool preparation as part of the documented bootstrap workflow
- the project keeps Kubernetes node bootstrap packages on the GitLab fallback source, while Helm remains sourced from the official upstream binary release

## 2026-04-30 — Keep `kubelet` stopped until `kubeadm` owns first bootstrap

Decision:
- install and enable `kubelet` during package bootstrap, but keep it stopped on fresh nodes
- stop `kubelet` explicitly before `kubeadm init` and `kubeadm join` when the node is not yet initialized
- after a successful `kubeadm init` or `kubeadm join`, explicitly return `kubelet` to `started`
- use `kubeadm reset -f` only for actual partial control-plane state, identified by kubeadm-managed files rather than a busy `10250` port alone

Reason:
- on a fresh node, a prematurely started `kubelet` can already occupy port `10250` before `kubeadm init`
- the first clean `kubelet` start should be coordinated by `kubeadm`, not by the package-install phase
- the first automation run showed that relying on implicit kubelet recovery after bootstrap was too weak and could leave all nodes `NotReady`
- treating any busy `10250` socket as partial kubeadm state was too broad for first-run automation

Alternatives considered:
- start `kubelet` immediately after package installation and ignore `Port-10250` preflight failures
- keep manual recovery outside the playbook after failed `kubeadm init`

Consequences:
- the first automation pass should no longer fail preflight on fresh nodes because `kubelet` started too early
- the bootstrap workflow must verify that `kubelet` is running again before relying on node readiness or CNI installation
- control-plane recovery remains automated for interrupted `kubeadm init` attempts that leave kubeadm-managed files behind
- bootstrap troubleshooting should distinguish between fresh-node sequencing issues and true partial kubeadm state
