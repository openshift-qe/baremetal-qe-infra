#!/bin/bash

set -x

# download latest Fedora CoreOS
mkdir -p ${TFTP_DIR}/fcos-{aarch64,x86_64}
curl -o /tmp/stable.json https://builds.coreos.fedoraproject.org/streams/stable.json
curl -o /tmp/fedora.gpg https://fedoraproject.org/fedora.gpg
fcos_release=$(jq -r .architectures.aarch64.artifacts.metal.release /tmp/stable.json)
echo -e "\n\e[31m~~ Fedora CoreOS Release ${fcos_release} ~~\e[0m\n"

for arch in aarch64 x86_64; do
  echo -e "\n----- $(date +"%Y-%m-%d %H:%M:%S") -----\n"
  pushd ${TFTP_DIR}/fcos-${arch}
  files_num=$(find ./ -name "*${fcos_release}*" -type f | wc -l)
  if ((files_num < 9)); then
    urls=$(jq .architectures.${arch}.artifacts.metal.formats.pxe /tmp/stable.json)
    for pxeimg in kernel initramfs rootfs; do
      curl -# -O $(jq -r .${pxeimg}.location <<< ${urls}) || echo "${pxeimg} download failed" || exit 1
      curl -# -O $(jq -r .${pxeimg}.signature <<< ${urls}) || echo "${pxeimg} download failed" || exit 1
      pxeimg_l=$(jq -r .${pxeimg}.location <<< ${urls} | awk -F/ '{print $NF}')
      pxeimg_s=$(jq -r .${pxeimg}.signature <<< ${urls} | awk -F/ '{print $NF}')
      echo "$(jq -r .${pxeimg}.sha256 <<< $urls) ${pxeimg_l}" > ${pxeimg_l}-CHECKSUM
      gpgv --keyring /tmp/fedora.gpg ${pxeimg_s} ${pxeimg_l} || echo "${pxeimg_l} signature verification failed" || exit 1
      sha256sum -c ${pxeimg_l}-CHECKSUM || echo "${pxeimg_l} checksum does not match" || exit 1
    done
  else
    echo -e "\n\e[34m${arch} ${fcos_release} image files available\e[0m\n$(ls -lh)\n"
  fi
  [[ "${PWD}" -eq "${TFTP_DIR}/fcos-${arch}" ]] && find ./ -type f -mtime +60 -exec rm {} \;
  popd
done
