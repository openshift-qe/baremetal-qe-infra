#!/bin/bash
set -euxo pipefail

PORT="$1"
[ -f "/var/.registry-$PORT" ] && {
  echo "The initialization script for registry-$PORT did already run. Exiting"
  exit 0
}
registry_password_file="/opt/registry-${PORT}/auth/htpasswd"
registry_certs_cert="/opt/registry-${PORT}/certs/domain.crt"
registry_certs_key="/opt/registry-${PORT}/certs/domain.key"
reg_cert_file="/opt/registry-common/domain.crt"
reg_key_file="/opt/registry-common/domain.key"
reg_passwd_file="/opt/registry-common/htpasswd"

mkdir -p "/opt/registry-${PORT}/"
# Ensure the file exists (it needs to be filled by ignition)
touch "/opt/registry-${PORT}/env"

## GENERATE REGISTRY CONFIGY.YAML FILE
cat > "/opt/registry-${PORT}/config.yaml" << EOF
version: 0.1
log:
  fields:
    service: registry
http:
  addr: :${PORT}
  headers:
    X-Content-Type-Options: [nosniff]
  tls:
    certificate: /certs/domain.crt
    key: /certs/domain.key
storage:
  delete:
    enabled: false
  cache:
    blobdescriptor: inmemory
  filesystem:
    rootdirectory: /var/lib/registry
  maintenance:
    readonly:
      enabled: false
auth:
  htpasswd:
    realm: Registry Realm
    path: /auth/htpasswd
health:
  storagedriver:
    enabled: true
    interval: 10s
    threshold: 3
EOF

## REGISTRY PASSWORD
if [ ! -f "${reg_passwd_file}" ]; then
  echo "The htpasswd file are not ready yet. Exiting"
  exit 1
fi
## CERTS FILES
if [ ! -f "${reg_cert_file}" ] || [ ! -f "${reg_key_file}" ]; then
  echo "Some certificate files are not ready yet. Exiting"
  exit 1
fi
mkdir -p "/opt/registry-${PORT}/"{data,auth,certs}
cat "${reg_passwd_file}"> "${registry_password_file}"
cat "${reg_cert_file}" > "${registry_certs_cert}"
cat "${reg_key_file}"> "${registry_certs_key}"
touch "/var/.registry-$PORT"
