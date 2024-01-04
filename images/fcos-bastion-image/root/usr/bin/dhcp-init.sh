#!/bin/bash

set -x

mkdir -p "${PODMAN_DNSMASQ_BASEDIR}"/{etc,tftpboot,misc,hosts/hostsdir,hosts/optsdir} \
 /var/opt/{ignitions,html}
ign=/var/opt/ignitions
cp "${LOCAL_PATH}"/dhcp/dnsmasq.conf "${PODMAN_DNSMASQ_BASEDIR}"/etc/
if [ -f "${PODMAN_DNSMASQ_BASEDIR}"/dnsmasq.hosts.conf ]; then
  cat "${PODMAN_DNSMASQ_BASEDIR}"/dnsmasq.hosts.conf >> "${PODMAN_DNSMASQ_BASEDIR}"/etc/dnsmasq.conf
fi

cp "${LOCAL_PATH}"/dhcp/tftpboot/grub.cfg "${TFTP_DIR}"
cp "${LOCAL_PATH}"/ignitions/* ${ign}

if [ ! -s "${ign}"/authorized_keys ] || [ ! -s "${ign}"/password_hashes ]; then
  echo "<3>Some files are not yet available, exiting prematurely from initializing dhcp services"
  exit 1
fi

# create ignition files
password_hash=$(<"${ign}/password_hashes")
export password_hash

pdm_opts=(--rm --interactive --security-opt "label=disable" -v "${ign}":/ign -v /var/opt/html:/output -w /ign)
butane_img="quay.io/coreos/butane:release"

podman run "${pdm_opts[@]}" ${butane_img} --pretty --strict --files-dir=./ wipe_disks.bu -o /output/wipe_disks.ign
podman run "${pdm_opts[@]}" ${butane_img} --pretty --strict --files-dir=./ -o /output/shell.ign  <<< "$(envsubst < ${ign}/shell.bu)"

# Extract grubaa64.efi and grubx64.efi from centso:stream9 RPMs
podman run -i --rm --privileged --name grubefi -v "${TFTP_DIR}":/tmp/output quay.io/centos/centos:stream9 /bin/bash <<'EOF'
dnf install -y cpio
cd /tmp
curl -L -O "$(dnf repoquery --location grub2-efi-aa64 --forcearch aarch64 | tail -n 1)"
curl -L -O "$(dnf repoquery --location grub2-efi-x64 --forcearch x86_64 | tail -n 1)"
mkdir -p {aarch64,x86_64,output}

cd /tmp/aarch64
rpm2cpio /tmp/grub2-efi-aa64* | cpio -idmv
mv boot/efi/EFI/centos/*.efi /tmp/output/
cd /tmp/x86_64
rpm2cpio /tmp/grub2-efi-x64* | cpio -idmv
mv boot/efi/EFI/centos/*.efi /tmp/output/

chmod 755 /tmp/output/*.efi
EOF
