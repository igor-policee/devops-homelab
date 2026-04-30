# Project Decisions

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
