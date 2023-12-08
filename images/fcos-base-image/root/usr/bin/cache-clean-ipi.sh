#!/bin/bash
set -x

NOW=$(date +'%s')

for f in /home/kni/.cache/openshift-installer/image_cache/*; do
  ACCESS=$(stat --format=%X "$f")
  DELTA=$((NOW - ACCESS))
  # 15 days
  if [ $DELTA -gt 1296000 ]; then
    rm -f "$f"
  fi
done
