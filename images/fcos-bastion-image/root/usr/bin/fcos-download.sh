#!/bin/bash

set -x

function fail() {
  echo "$1"
  exit 1
}

# download latest Fedora CoreOS
mkdir -p "${TFTP_DIR}"/fcos-{aarch64,x86_64}
curl -o /tmp/stable.json https://builds.coreos.fedoraproject.org/streams/stable.json
curl -o /tmp/fedora.gpg https://fedoraproject.org/fedora.gpg
fcos_release=$(jq -r .architectures.aarch64.artifacts.metal.release /tmp/stable.json)
echo "<4>~~ Fedora CoreOS Release ${fcos_release} ~~"

for arch in aarch64 x86_64; do
  pushd "${TFTP_DIR}"/fcos-"${arch}" || fail "pushd failed"
  files_num=$(find ./ -name "*${fcos_release}*" -type f | wc -l)
  if ((files_num < 9)); then
    urls=$(jq .architectures."${arch}".artifacts.metal.formats.pxe /tmp/stable.json)
    for pxeimg in kernel initramfs rootfs; do
      location=$(jq -r ."${pxeimg}".location <<< "${urls}")
      signature=$(jq -r ."${pxeimg}".signature <<< "${urls}")
      curl -# -O "${location}" || fail "${pxeimg} download failed"
      curl -# -O "${signature}" || fail "${pxeimg} download failed"
      pxeimg_l=$(jq -r ."${pxeimg}".location <<< "${urls}" | awk -F/ '{print $NF}')
      pxeimg_s=$(jq -r ."${pxeimg}".signature <<< "${urls}" | awk -F/ '{print $NF}')
      echo "$(jq -r ."${pxeimg}".sha256 <<< "${urls}") ${pxeimg_l}" > "${pxeimg_l}"-CHECKSUM
      gpgv --keyring /tmp/fedora.gpg "${pxeimg_s}" "${pxeimg_l}" || fail "${pxeimg_l} signature verification failed"
      sha256sum -c "${pxeimg_l}"-CHECKSUM || fail "${pxeimg_l} checksum does not match"
    done
  else
    echo "<4>~~ ${arch} ${fcos_release} image files are available ~~"
    ls -lh
  fi
  [[ "${PWD}" == "${TFTP_DIR}/fcos-${arch}" ]] && find ./ -type f -mtime +60 -exec rm {} \;
  popd || fail "popd failed"
done
