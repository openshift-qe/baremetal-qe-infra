#!/bin/bash

set -euxo pipefail

STORAGE_POOL_NAME="default"
STORAGE_FOLDER="/var/lib/libvirt/images"
STORAGE_CONF_TMP_FILE="/etc/libvirt/storage/storage.conf"

if ! virsh pool-info "${STORAGE_POOL_NAME}"; then
  cat > "${STORAGE_CONF_TMP_FILE}" <<EOF
<pool type='dir'>
  <name>${STORAGE_POOL_NAME}</name>
    <target>
      <path>${STORAGE_FOLDER}</path>
    </target>
</pool>
EOF
  virsh pool-define "${STORAGE_CONF_TMP_FILE}"
  rm -f "${STORAGE_CONF_TMP_FILE}"
fi

mkdir -p "${STORAGE_FOLDER}"
virsh pool-autostart "${STORAGE_POOL_NAME}"
virsh pool-info "${STORAGE_POOL_NAME}" | grep -iqE "State:[ ]+running" || virsh pool-start "${STORAGE_POOL_NAME}"
virsh net-autostart --network default --disable
