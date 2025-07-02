#!/bin/bash
set -euo pipefail
PREPARED_USER_NAME="itsc"

echo "Provisioning the VM."
echo "This might take a while..."

# Wait for cloud-init to finish if systemd and its service is enabled.
if status=$(LANG=C systemctl is-system-running 2>/dev/null) || [ "${status}" != "offline" ] && systemctl is-enabled --quiet cloud-init.service 2>/dev/null
then
  cloud-init status --wait > /dev/null 2>&1 || true
else
  exit 1
fi

sudo passwd "${PREPARED_USER_NAME}"
