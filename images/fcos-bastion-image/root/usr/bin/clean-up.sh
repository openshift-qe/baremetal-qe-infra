#!/bin/bash

echo "<3>Starting the clean up process"
echo "<2>Checking if any /var/builds/* folder container is older than 3 days and prune the related clusters"
# Check if any /var/builds/* folder container is older than 3 days
while IFS= read -r -d '' cluster_folder
do
  echo "<3>Deleting $cluster_folder"
  cluster=$(basename "$cluster_folder")
  if [ -f "$cluster_folder/preserve" ]; then
    echo "<3>$cluster is marked to ignore the automatic pruning, skipping..."
    continue
  fi
  echo "<3>$cluster is more than 3 days old, starting the pruning...."
  prune_nodes "$cluster"
done < <(find /var/builds/ -maxdepth 1 -type d -mtime +2 -print0)

# Clean up left over ports in the ovs switches that can span across multiple clusters
for port in $(ovs-vsctl show  | grep "No such device" | sed -e 's/^.*device //' -e 's/ (No such.*$//')
do
  bridge=$(ovs-vsctl port-to-br "$port")
  echo "<3>Deleting orphan port $bridge/$port"
  ovs-vsctl del-port "$bridge" "$port"
done
