#!/bin/bash

echo "<3>Starting the clean up process"
echo "<2>Checking if any /var/builds/* folder container is older than 3 days and prune the related clusters"
# Check if any /var/builds/* folder container is older than 3 days
while IFS= read -r -d '' cluster_folder
do
  echo "<3>Deleting $cluster_folder"
  cluster=$(basename "$cluster_folder")

  # To preserve a cluster, create an empty file named 'preserve'
  # To preserve a cluster with an expiry date, add the date in ISO 8601 (YYYY-MM-DD) and in UTC formate in preserve file
  # eg. To preserve cluster for a week
  # date --utc -I -d "1 week" > /var/builds/<cluster_name>/preserve
  # Or with exact time
  # date --utc -Iseconds -d "1 week 5:45 pm" > /var/builds/<cluster_name>/preserve
  if [ -e "$cluster_folder/preserve" ] && [ ! -s "$cluster_folder/preserve" ]; then
    echo "<3>$cluster is marked to ignore the automatic pruning forever, skipping..."
    continue
  elif [ -s "$cluster_folder/preserve" ]; then
    echo "<3>$cluster is marked to ignore the automatic pruning, checking the expiry date..."
    nowdate=$(date +%s)
    chkdate=$(date --utc -d "$(<"${cluster_folder}"/preserve)" -Iseconds 2>&1)
    chkstatus=$?
    if [ "${chkstatus}" -ne 0 ]; then
      echo "<2>$cluster preserve time is not in ISO 8601 format, preparing to prune..."
      enddate="${nowdate}"
    else
      enddate=$(date -d "${chkdate}" +%s)
    fi
    [ "${enddate}" -gt "${nowdate}" ] && \
    echo "<3>$cluster to continue being preserved, skipping..." && continue
    [ "${enddate}" -le "${nowdate}" ] && \
    echo "<3>$cluster no longer to be preserved"
  fi
  echo "<3>$cluster is more than 3 days old and not preserved, starting the pruning...."
  prune_nodes "$cluster"
done < <(find /var/builds/ -maxdepth 1 -type d -mmin 1440+ -print0)

# Clean up left over ports in the ovs switches that can span across multiple clusters
for port in $(ovs-vsctl show  | grep "No such device" | sed -e 's/^.*device //' -e 's/ (No such.*$//')
do
  bridge=$(ovs-vsctl port-to-br "$port")
  echo "<3>Deleting orphan port $bridge/$port"
  ovs-vsctl del-port "$bridge" "$port"
done
