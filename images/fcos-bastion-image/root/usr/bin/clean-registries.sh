#!/bin/sh
set -x

wait_for_container_running() {
  local container_name=$1
  echo "Waiting for container $container_name to become running..."
  for i in {1..60} MAX; do
    if [ "$i" == MAX ]; then
      return 1
    fi
    if [ "$(podman inspect -f '{{.State.Health.Status}}' "$container_name" 2>/dev/null)" == "healthy" ]; then
      echo "Container $container_name is now running and healthy"
      return 0
    fi
    sleep 1
  done
  echo "The container didn't get ready in time"
  return 1
}

mapfile -t ports < <(systemctl list-units 'registry@*' --no-pager --quiet | awk -F'[@.]' '{print $2}')
for port in "${ports[@]}"; do
  disk_use=$(df /opt/registry-"${port}" --output='pcent' | grep -o '[0-9]*')
  if [ "$disk_use" -gt 85 ]; then
    rm -rf /opt/registry-"${port}"/data/docker/registry/v2/repositories/*
    sed -i -e '/readonly/{n;s/enabled:.*/enabled: true/;}' /opt/registry-"${port}"/config.yaml
    systemctl restart registry@"${port}".service
    wait_for_container_running registry-"${port}"
    podman exec registry-"${port}" /bin/registry garbage-collect /etc/docker/registry/config.yml
    sed -i -e '/readonly/{n;s/enabled:.*/enabled: false/;}' /opt/registry-"${port}"/config.yaml
    systemctl restart registry@"${port}".service
  fi
done

exit 0
