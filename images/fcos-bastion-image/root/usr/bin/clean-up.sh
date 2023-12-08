#!/bin/bash

# Check if any haproxy container is running for more than 3 days
for i in $(docker ps -a --format "{{.Names}}" | grep "haproxy-")
do
  creation_ts=$(docker inspect --format="{{.Created}}" "$i")
  create_ts=$(date -d "${creation_ts}" +%s)
  now_ts=$(date +%s)
  diff_in_ts=$((now_ts - create_ts))
  if [ "${diff_in_ts}" -ge 259200 ]; then
    CLUSTER=${i#haproxy-}
    echo "<3>$CLUSTER is more than 3 days old, starting the pruning...."
    prune_nodes "$CLUSTER"
  fi
done

# Clean up left over ports in the ovs switches that can span across multiple clusters
for port in $(ovs-vsctl show  | grep "No such device" | sed -e 's/^.*device //' -e 's/ (No such.*$//')
do
  bridge=$(ovs-vsctl port-to-br "$port")
  echo "Deleting orphan port $bridge/$port"
  ovs-vsctl del-port "$bridge" "$port"
done
