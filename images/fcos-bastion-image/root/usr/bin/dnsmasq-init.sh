#!/bin/bash

PODMAN_DNSMASQ_BASEDIR=/var/opt/dnsmasq
tftp_dir=${PODMAN_DNSMASQ_BASEDIR}/tftpboot
password_hash=$(<"/var/opt/ignitions/password_hashes")

# create ignition files
pdm_opts="--rm --interactive --security-opt label=disable -v /var/opt/ignitions:/ign_files -v /opt/html:/output -w /ign_files"
butane_img="quay.io/coreos/butane:release"

podman run ${pdm_opts} ${butane_img} --pretty --strict --files-dir=./ wipe_disk.bu -o /output/wipe_disks.ign
podman run ${pdm_opts} ${butane_img} --pretty --strict --files-dir=./ -o /output/shell.ign  <<< $(envsubst < shell.bu)

# Extract grubaa64.efi and grubx64.efi from centso:stream9 RPMs
mkdir -p ${PODMAN_DNSMASQ_BASEDIR}/tftpboot
podman run --rm -t --privileged --name grubefi -v ${tftp_dir}:/tmp/output quay.io/centos/centos:stream9 <<EOF
dnf install -y cpio
cd /tmp
curl -L -O $(dnf repoquery --location grub2-efi-aa64 --forcearch aarch64 | tail -n 1)
curl -L -O $(dnf repoquery --location grub2-efi-x64 --forcearch x86_64 | tail -n 1)
mkdir -p {aarch64,x86_64,output}

cd /tmp/aarch64
rpm2cpio /tmp/grub2-efi-aa64* | cpio -idmv
mv boot/efi/EFI/centos/*.efi /tmp/output/

cd /tmp/x86_64
rpm2cpio /tmp/grub2-efi-x64* | cpio -idmv
mv boot/efi/EFI/centos/*.efi /tmp/output/
EOF

# download latest Fedora CoreOS
mkdir -p ${tftp_dir}/fcos-{aarch64,x86_64}
curl -o /tmp/stable.json https://builds.coreos.fedoraproject.org/streams/stable.json
curl -o /tmp/fedora.gpg https://fedoraproject.org/fedora.gpg
echo -e "\n\e[31m~~ Fedora CoreOS Release $(jq .architectures.aarch64.artifacts.metal.release /tmp/stable.json) ~~\e[0m\n"

for arch in aarch64 x86_64; do
  pushd ${tftp_dir}/fcos-$arch
  urls=$(jq .architectures.$arch.artifacts.metal.formats.pxe /tmp/stable.json)
  for pxeimg in kernel initramfs rootfs; do
    curl -# -O $(jq -r .$pxeimg.location <<< $urls) || echo "$pxeimg download failed" || exit 1
    curl -# -O $(jq -r .$pxeimg.signature <<< $urls) || echo "$pxeimg download failed" || exit 1
    pxeimg_l=$(jq -r .$pxeimg.location <<< $urls | awk -F/ '{print $NF}')
    pxeimg_s=$(jq -r .$pxeimg.signature <<< $urls | awk -F/ '{print $NF}')
    echo "$(jq -r .$pxeimg.sha256 <<< $urls) $pxeimg_l" > ${pxeimg_l}-CHECKSUM
    gpgv --keyring /tmp/fedora.gpg ${pxeimg_s} ${pxeimg_l} || echo "${pxeimg_l} signature verification failed" || exit 1
    sha256sum -c ${pxeimg_l}-CHECKSUM || echo "${pxeimg_l} checksum does not match" || exit 1
  done
  popd
done
