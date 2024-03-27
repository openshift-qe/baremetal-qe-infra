#!/bin/bash
set -x

iso_path="/home/kni/.cache/openshift-installer/image_cache/"

if [ -d "${iso_path}" ]; then
  echo "<3>${iso_path} exists, cleaning up 15 days old unused ISO"
  find "${iso_path}" -type "f,d" -atime +15 -delete
else
  echo "<2>${iso_path} directory does not exist"
fi

