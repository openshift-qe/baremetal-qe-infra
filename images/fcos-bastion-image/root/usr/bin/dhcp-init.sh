#!/bin/bash

set -x

mkdir -p /var/opt/{ignitions,html}
cp ${LOCAL_PATH}/dhcp/ignitions/* /var/opt/ignitions/

ign=/var/opt/ignitions
mkdir -p ${PODMAN_DNSMASQ_BASEDIR}/{etc,tftpboot,misc}
#/usr/bin/chown -R 65534:65534 ${PODMAN_DNSMASQ_BASEDIR}/misc
cp ${LOCAL_PATH}/dhcp/bastion_dnsmasq.conf ${PODMAN_DNSMASQ_BASEDIR}/etc/
cp ${LOCAL_PATH}/dhcp/tftpboot/grub.cfg ${TFTP_DIR}
cp ${LOCAL_PATH}/ignitions/* ${ign}

# create ignition files
export password_hash=$(<"${ign}/password_hashes")

pdm_opts="--rm --interactive --security-opt label=disable -v ${ign}:/ign -v /var/opt/html:/output -w /ign"
butane_img="quay.io/coreos/butane:release"

podman run ${pdm_opts} ${butane_img} --pretty --strict --files-dir=./ wipe_disks.bu -o /output/wipe_disks.ign
podman run ${pdm_opts} ${butane_img} --pretty --strict --files-dir=./ -o /output/shell.ign  <<< $(envsubst < ${ign}/shell.bu)

# Extract grubaa64.efi and grubx64.efi from centso:stream9 RPMs
podman run -i --rm --privileged --name grubefi -v ${TFTP_DIR}:/tmp/output quay.io/centos/centos:stream9 /bin/bash <<EOF
dnf install -y cpio
cd /tmp
curl -L -O "\$(dnf repoquery --location grub2-efi-aa64 --forcearch aarch64 | tail -n 1)"
curl -L -O "\$(dnf repoquery --location grub2-efi-x64 --forcearch x86_64 | tail -n 1)"
mkdir -p {aarch64,x86_64,output}

cd /tmp/aarch64
rpm2cpio /tmp/grub2-efi-aa64* | cpio -idmv
mv boot/efi/EFI/centos/*.efi /tmp/output/

cd /tmp/x86_64
rpm2cpio /tmp/grub2-efi-x64* | cpio -idmv
mv boot/efi/EFI/centos/*.efi /tmp/output/
EOF
