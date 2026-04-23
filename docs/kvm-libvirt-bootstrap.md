# KVM/libvirt bootstrap

This phase prepares the physical Ubuntu 24.04 host for VM-based Kubernetes nodes.

## What the playbook does

- installs KVM/libvirt packages
- enables and starts `libvirtd`
- adds the SSH user to the `libvirt` and `kvm` groups
- verifies CPU virtualization support with `kvm-ok`
- ensures the default libvirt NAT network exists and is active
- verifies that `virsh` works against `qemu:///system`

## Run

From the repository `ansible/` directory:

```bash
cd ansible
ansible-playbook -K playbooks/host-bootstrap.yml
```

If your local SSH config already contains the `homelab-ubuntu` host entry, the inventory can stay as-is.

## Manual verification after first run

If the playbook reports that `virsh` validation is deferred, reconnect your SSH session so the new group membership is applied, then check:

```bash
kvm-ok
virsh net-list --all
virsh pool-list --all
```

Expected checkpoints:

- `kvm-ok` reports that KVM acceleration can be used
- the `default` libvirt network exists, is active, and autostarts
- `virsh` works without needing root

Note:

- on the first run, adding the SSH user to `libvirt` and `kvm` may require a fresh login before non-root `virsh` access works
- rerunning the playbook after reconnecting should then pass the final validation step cleanly
