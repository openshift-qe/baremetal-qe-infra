#!/bin/sh
set -x

mapfile -t ports < <(systemctl list-units 'registry@*' --no-pager --quiet | awk -F'[@.]' '{print $2}')
for port in "${ports[@]}"; do
  disk_use=$(df /opt/registry-"${port}" --output='pcent' | grep -o '[0-9]*')
  if [ "$disk_use" -gt 85 ]; then
    rm -rf /opt/registry-"${port}"/data/docker/registry/v2/repositories/*
    systemctl restart registry@"${port}".service
  fi
done

exit 0
