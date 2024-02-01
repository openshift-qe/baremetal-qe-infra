#!/bin/sh
set -x

mapfile -t services < <(systemctl list-units --type service | grep -i "registry@" | awk '{print $1}' | awk -F'[@.]' '{print $2}')
for port in "${services[@]}"; do
  disk_use=$(df /opt/registry-"${port}" --output='pcent' | grep -o '[0-9]*')
  if [ "$disk_use" -gt 85 ]; then
    rm -rf /opt/registry-"${port}"/data/docker/registry/v2/repositories/*
    systemctl restart registry@"${port}".service
  fi
done

exit 0

