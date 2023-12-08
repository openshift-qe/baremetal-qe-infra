#!/bin/bash

set -euxo pipefail

STORAGE_POOL_NAME="default"
STORAGE_FOLDER="/var/lib/libvirt/images"

if ! virsh pool-info "${STORAGE_POOL_NAME}"; then
  virsh pool-define /dev/stdin <<EOF
<pool type='dir'>
  <name>${STORAGE_POOL_NAME}</name>
    <target>
      <path>${STORAGE_FOLDER}</path>
    </target>
</pool>
EOF
fi

mkdir -p "${STORAGE_FOLDER}"
virsh pool-autostart "${STORAGE_POOL_NAME}"
virsh pool-info "${STORAGE_POOL_NAME}" | grep -iqE "State:[ ]+running" || virsh pool-start "${STORAGE_POOL_NAME}"
