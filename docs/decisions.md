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

**Superseded by the 2026-06-05 decision below — the external gitlab.com source has been decommissioned.**

Decision (original):
- used the GitLab project `igor-policee/k8s-bootstrap-artifacts` on gitlab.com as the fallback source for Kubernetes bootstrap packages
- package name `kubernetes-debs`, package version `v1.35.4`
- installed `cri-tools`, `kubeadm`, `kubectl`, `kubelet`, and `kubernetes-cni` from downloaded `.deb` files
- put those packages on `apt hold` and disabled the upstream `kubernetes.list` source

## 2026-06-05 — Move Kubernetes bootstrap artifacts to local GitLab CE

Decision:
- the external gitlab.com source (`igor-policee/k8s-bootstrap-artifacts`) has been decommissioned
- Kubernetes bootstrap artifacts are now hosted in the local GitLab CE instance on `gitlab-vm` (`192.168.122.20`)
- package name `kubernetes-debs` and package version `v1.35.4` remain unchanged
- `kubernetes_gitlab_api` in `group_vars/all.yml` now points to `http://192.168.122.20/api/v4`
- `kubernetes_gitlab_project_id` must be set after `gitlab-bootstrap.yml` creates the project

Reason:
- eliminates the external dependency on gitlab.com for every cluster rebuild
- the local GitLab CE (Phase 5) is available on the same libvirt NAT network as all Kubernetes nodes
- download reliability and latency improve significantly for LAN-local artifact delivery

Consequences:
- `gitlab-bootstrap.yml` must run and the artifacts must be uploaded to local GitLab before `kubernetes-bootstrap.yml` can succeed
- the `GITLAB_TOKEN` env var now refers to a personal access token from the local GitLab instance

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

## 2026-06-05 — Use reverse SSH tunnel via VPS for remote access

Decision:
- homelab-ubuntu maintains a persistent outbound SSH tunnel to a VPS using `autossh` and a systemd service
- the user connects to `VPS:2222` which is relayed through the tunnel to `homelab:22`
- VPS acts as a stateless TCP relay; private keys never leave the client machine

Reason:
- the ISP blocks all incoming TCP connections at the network level (stateful firewall drops external SYN packets)
- direct port forwarding at the router is not viable regardless of router configuration
- reverse tunnel leverages the ISP's allowance of outbound connections; the established session carries bidirectional traffic without triggering the incoming block

Alternatives considered:
- call ISP to request open incoming ports (user declined)
- Cloudflare Tunnel or ngrok (adds external SaaS dependency)

Consequences:
- a VPS with a public IP is now a hard dependency for external access to the homelab
- Phase 13 is largely complete; remaining item is SSH port forwarding for cluster services
- the `autossh` systemd service must be added to Ansible host bootstrap to survive host rebuilds

## 2026-06-04 — Deploy GitLab CI on a dedicated VM outside the Kubernetes cluster

Decision:
- GitLab CI runs on a dedicated libvirt VM (`gitlab-vm`, `192.168.122.20`), not as a Kubernetes application
- GitLab Runner is deployed into the Kubernetes cluster as a Kubernetes executor and connects to the external GitLab instance
- `gitlab-vm` is provisioned by the same OpenTofu + libvirt stack as the Kubernetes nodes

Reason:
- CI/CD infrastructure must survive Kubernetes cluster failures; if the cluster is broken or being rebuilt, GitLab must remain available to run recovery pipelines
- eliminates the chicken-and-egg bootstrap problem: GitLab cannot deploy itself to a cluster that does not yet exist
- resource isolation: GitLab resource consumption does not compete with workload pods on worker nodes
- production pattern: in real environments, CI/CD servers are not deployed on the same cluster they manage

Alternatives considered:
- deploy GitLab via the official Helm chart into the Kubernetes cluster

Consequences:
- OpenTofu `locals.tf` adds a fourth node entry (`gitlab-vm`); worker nodes are sized at 8GB each instead of 12GB
- Phase 5 Ansible work targets the `gitlab-vm` host group for GitLab CE installation, and the Kubernetes cluster for Runner deployment
- the `gitlab-vm` operates on the same libvirt NAT network (`192.168.122.0/24`) and is reachable from all Kubernetes nodes

## 2026-06-04 — Replace kube-proxy with Cilium eBPF kube-proxy replacement mode

Decision:
- run Cilium in kube-proxy replacement mode using eBPF instead of the default kube-proxy setup
- Phase 4 Ansible and Helm work must configure Cilium with `kubeProxyReplacement: true` and
  kubeadm must skip the kube-proxy addon (`--skip-phases=addon/kube-proxy`)

Reason:
- eBPF-based networking is the modern approach aligned with a DevSecOps platform; it enables
  deeper network policy enforcement and reduces per-hop overhead compared to iptables
- this decision is made before Phase 4 to avoid reconfiguring the network stack after workloads
  are deployed on the cluster

Alternatives considered:
- keep kube-proxy and add Cilium eBPF features later as an optional upgrade

Consequences:
- the current running cluster still uses kube-proxy; applying this change requires either a
  documented in-place migration or a cluster rebuild at the start of Phase 4
- Phase 4 Ansible playbooks and Cilium Helm values must be updated accordingly

## 2026-06-04 — Expand DevSecOps platform toolset to cover the full security lifecycle

Decision:
- extend the planned toolset to cover all major DevSecOps practice areas: container security (Harbor), identity and access management (Keycloak + LDAP), application security testing (SonarQube, OWASP ZAP), supply chain security (Cosign, Syft), policy enforcement (Kyverno), vulnerability management (DefectDojo), and security monitoring (SIEM, MITRE ATT&CK)
- split the single "DevSecOps Tooling" phase into four focused phases: container and Kubernetes security, secure CI/CD pipeline, security testing and monitoring
- rename Phase 7 from "Secrets with Vault" to "Secrets and Identity" to include Keycloak and LDAP alongside Vault

Reason:
- the project vision is a modern DevSecOps platform covering the full SDLC security lifecycle, not just a CI/CD platform with basic scanning
- the full toolset provides a complete training environment aligned with industry DevSecOps practices
- grouping tools by security domain (identity, container security, pipeline security, threat analysis) makes each phase independently learnable and deployable

Alternatives considered:
- keep a single broad DevSecOps tooling phase with all tools listed together
- implement only the tools directly required by the CI/CD pipeline

Consequences:
- the roadmap now spans 13 phases (1–3 completed, 4–13 pending)
- each DevSecOps phase maps to a distinct security domain, making progress measurable
- Keycloak must be deployed alongside Vault in Phase 7, increasing Phase 7 complexity
- Harbor becomes a dependency for Phase 8 and Phase 9 (supply chain and image signing)

## 2026-06-04 — Redirect project to a DevSecOps CI/CD platform

Decision:
- reposition the project from a general DevOps/Kubernetes homelab to a platform for deploying and operating a CI/CD stack (GitLab CI, ArgoCD, Vault) and for DevSecOps training and solution development
- DevSecOps skill-building becomes the primary goal; the public GitHub showcase remains but is secondary

Reason:
- the user wants to expand their DevOps profile to DevSecOps
- the homelab provides a safe, reproducible environment to practice real security tooling without enterprise risk
- the existing Kubernetes automation baseline (Phases 1–3) is a solid foundation for deploying CI/CD and security tooling on top

Alternatives considered:
- continue as a general-purpose DevOps homelab and add security tooling incrementally without a declared focus
- pursue a cloud-based DevSecOps lab instead of a self-hosted one

Consequences:
- roadmap phases are restructured to target GitLab CI, ArgoCD, Vault, and DevSecOps tooling in explicit phases
- GitHub Actions and SOPS+age are removed from the planned stack
- new phases cover SAST, image scanning, policy enforcement, supply chain security, and DAST

## 2026-06-04 — Replace GitHub Actions with GitLab CI

Decision:
- GitLab CI is the primary CI/CD platform for this project; GitHub Actions is removed from the planned stack
- GitLab CI deployment model is TBD: self-hosted GitLab instance on the cluster or SaaS GitLab.com with a cluster-side runner

Reason:
- GitLab provides integrated CI/CD with native security scanning hooks, runner flexibility, and a self-hosted option that fits the homelab model
- GitLab CI is directly relevant to DevSecOps environments; its native SAST, DAST, container scanning, and dependency scanning integrations align with the new project goal

Alternatives considered:
- keep GitHub Actions as a secondary lint/check layer for the GitHub repository while GitLab CI handles the full pipeline
- use Jenkins instead of GitLab CI

Consequences:
- Phase 5 of the roadmap must decide and document the GitLab CI deployment model before pipeline work begins
- the GitHub repository remains the source of truth for IaC, but CI/CD pipelines run in GitLab
- no GitHub Actions workflows will be added to the repository

## 2026-06-04 — Replace SOPS+age with Vault

Decision:
- HashiCorp Vault self-hosted on the cluster is the secrets backend; SOPS+age is removed from the planned stack
- Vault will use the Kubernetes auth backend and support dynamic secrets and policy-as-code

Reason:
- Vault is a core DevSecOps skill; its Kubernetes auth backend, dynamic secrets, and policy engine are not achievable with SOPS+age
- integrating Vault with both ArgoCD and GitLab CI is a realistic pattern used in production DevSecOps environments and directly supports the training goal

Alternatives considered:
- keep SOPS+age alongside Vault for Git-encrypted secrets at rest
- use HCP Vault (managed) instead of self-hosted

Consequences:
- Vault must be bootstrapped before application secrets can be defined (Phase 7)
- ArgoCD and GitLab CI must be integrated with Vault for secret injection in later phases
- the bootstrap complexity is higher than SOPS+age but justified by the DevSecOps focus

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
