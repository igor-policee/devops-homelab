#!/usr/bin/env bash

set -euo pipefail

action="${1:?action is required}"
network_name="${2:?network_name is required}"
host_name="${3:?host_name is required}"
mac_address="${4:?mac_address is required}"
ip_address="${5:?ip_address is required}"

# Libvirt net-update wants the full host entry XML for both create and delete.
host_xml="<host mac='${mac_address}' name='${host_name}' ip='${ip_address}'/>"

if ! command -v virsh >/dev/null 2>&1; then
  echo "virsh is required to manage DHCP reservations for network ${network_name}" >&2
  exit 1
fi

existing_xml="$(virsh net-dumpxml "${network_name}")"

if [[ "${action}" == "apply" ]]; then
  # Keep the operation idempotent across repeated applies.
  if grep -Fq "${host_xml}" <<<"${existing_xml}"; then
    exit 0
  fi

  virsh net-update "${network_name}" add-last ip-dhcp-host "${host_xml}" --live --config
  exit 0
fi

if [[ "${action}" == "destroy" ]]; then
  # Destroy should also be idempotent so tofu destroy can be re-run safely.
  if ! grep -Fq "${host_xml}" <<<"${existing_xml}"; then
    exit 0
  fi

  virsh net-update "${network_name}" delete ip-dhcp-host "${host_xml}" --live --config
  exit 0
fi

echo "unsupported action: ${action}" >&2
exit 1
