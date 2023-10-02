#!/bin/bash

function prune_nodes() {

  if [ "$#" -ne 1 ]; then
      echo "<3>Usage: $0 <cluster-name>"
      return 1
  fi

  CLUSTER=${1}
  INTERNAL_NET="192.168.90.0/24"
  DOCKER_NET="172.17.0.0/16"
  reserved_hosts="/etc/hosts_pool_reserved"
  var_dir="/var/builds/${CLUSTER}"
  conf_files=(/opt/dhcpd/root/etc/dnsmasq.conf
              /opt/bind9_zones/zone
              /opt/bind9_zones/internal_zone.rev
              /opt/bind9_zones/external_zone.rev
              /etc/vips_reserved
              "${reserved_hosts}")

  readarray -t nodes < <(awk -F, -v cluster="${CLUSTER}" '$0 ~ cluster {print $12,$15,$16,$23}' "${reserved_hosts}")
  readarray -t node_ips < <(awk -F, -v cluster="${CLUSTER}" '$0 ~ cluster {print $2}' "${reserved_hosts}")
  readarray -t grub_macs < <(awk -F, -v cluster="${CLUSTER}" '$0 ~ cluster {print $1}' "${reserved_hosts}")

  # Destroy HAProxy network for $CLUSTER
  /usr/local/bin/ovs-docker del-port br-ext eth1 haproxy-"${CLUSTER}"
  /usr/local/bin/ovs-docker del-port br-int eth2 haproxy-"${CLUSTER}"
  /usr/local/bin/ovs-docker del-port br-int eth1 haproxy-"${CLUSTER}"

  # Delete haproxy container if it exists for the cluster
  if docker ps -a --format "{{.Names}}" | grep -q "${CLUSTER}"; then
    docker rm -f haproxy-"${CLUSTER}" && echo "<4>Deleted haproxy-${CLUSTER} container"
  fi

  # Remove firewall rules for bootstrap
  ## Remove port forwarding from bastion host to bootstrap host
  if [ "$(wc -l "${var_dir}"/boostrap.csv | awk '{print $1}')" -gt 1 ]; then
    bootstrap_host=$(awk -F, -v cluster="${CLUSTER}" '$0 ~ cluster {print $3}' "${var_dir}"/boostrap.csv)
    bootstrap_ip=$(awk -F, -v cluster="${CLUSTER}" '$0 ~ cluster {print $2}' "${var_dir}"/boostrap.csv)
    firewall-cmd --zone=external \
      --remove-forward-port=port=22"${bootstrap_host: -3}":proto=tcp:toport=22:toaddr="${bootstrap_ip}"
    firewall-cmd --zone=external \
      --remove-forward-port=port=22"${bootstrap_host: -3}":proto=tcp:toport=22:toaddr="${bootstrap_ip}" \
      --permanent

  ## Remove bootstrap host acess limit to internet if in disconnected network
    iptables -D FORWARD -s "${bootstrap_ip}" -p tcp --sport 22 -j ACCEPT
    iptables -D FORWARD -s "${bootstrap_ip}" ! -d "${INTERNAL_NET}" -j DROP
    iptables -D FORWARD -s "${bootstrap_ip}" -d "${DOCKER_NET}" -j ACCEPT
  fi

  # Remove cluster nodes acess limit to internet if in disconnected network
  if [ ${#node_ips[@]} -ge 1 ]; then
    for nodeip in "${node_ips[@]}"; do
      iptables -D FORWARD -s "${nodeip}" ! -d "${INTERNAL_NET}" -j DROP
      iptables -D FORWARD -s "${nodeip}" -d "${DOCKER_NET}" -j ACCEPT
    done
  fi

  # Delete provisioning network
  nmcli connection delete "${CLUSTER}"-provisioning-dev
  nmcli connection delete br-"${CLUSTER}"-provisioning

  # Delete VLAN on Juniper
  if [ -s "${var_dir}"/vips.yaml ] && [ -s "${var_dir}"/hosts.yaml ]; then
    ACTION=DELETE
    VLAN_NAME=${CLUSTER}
    VLAN_ID=$(grep "api_vip" "${var_dir}"/vips.yaml | awk -F. '{print $NF}')
    INTERFACES=$(grep 'switch_port:' "${var_dir}"/hosts.yaml | awk '{print $NF}' | tr '\n' ',' | sed 's/,$//')
    export ACTION VLAN_NAME VLAN_ID INTERFACES
    python3 /usr/local/bin/set_vlans.py
  fi

  # Cleanup dirs of CLUSTER
  for dir in /home/kni/cluster_configs /var/builds /opt/nfs /opt/html; do
    pushd "${dir}" || continue
    rm -fr "${CLUSTER}"
    popd || exit 1
  done

  # Delete cached openshift-images in /var/lib/libvirt/openshift-images/
  if [[ $(realpath /var/lib/libvirt/openshift-images/*"${CLUSTER}"*) =~ ^/var/lib/libvirt/openshift-images/.* ]]
  then
    rm -rf /var/lib/libvirt/openshift-images/*"${CLUSTER}"*
  fi

  pushd /opt/tftpboot || echo "<3>pushd to /opt/tftpboot failed"
  rm -fr "$CLUSTER"
  if [[ ${#grub_macs[@]} -gt 0 ]]; then
    for mac in "${grub_macs[@]}"; do
      grubcfg="grub.cfg-01-$(tr ':' '-' <<< "${mac}")"
      rm -f "${grubcfg}"
    done
  fi
  popd || exit 1

  # Wipe disks and power off nodes
  if [[ ${#nodes[@]} -gt 0 ]]; then
    printf "%s\n" "${nodes[@]}"

    while read -r nodeh nodeu nodep pdu_uri; do
      if [[ -n ${nodeh} && -n ${nodeu} && -n ${nodep} ]]; then
        if [[ -n ${pdu_uri} ]] && ! ipmitool -I lanplus -H "${nodeh}" -U "${nodeu}" -P "${nodep}" \
          power status | grep -Eq ' on| off'; then
          pdu_host=${pdu_uri%%/*}
          pdu_host=${pdu_host##*@}
          pdu_socket=${pdu_uri##*/}
          pdu_creds=${pdu_uri%%@*}
          pdu_user=${pdu_creds%%:*}
          pdu_pass=${pdu_creds##*:}
          echo "${pdu_pass}" > /tmp/ssh-pass
          timeout -s 9 10m sshpass -f /tmp/ssh-pass ssh "${pdu_user}@${pdu_host}" <<EOF
olReboot $pdu_socket
quit
EOF
          echo "<3>${nodeh} - pdu reboot"
	  pdu_reboot=true
	fi
      fi
    done <<< "$(printf "%s\n" "${nodes[@]}")"

    while read -r nodeh nodeu nodep pdu_uri; do
      if [[ -n ${nodeh} && -n ${nodeu} && -n ${nodep} ]]; then
        if [ "$pdu_reboot" = true ]; then
	  pdu_reboot=false
          echo "<4>Waiting for 2 min for pdu socket reboot before checking again.." && sleep 120
          retry_max=32
          while [ $retry_max -gt 0 ] && ! ipmitool -I lanplus -H "${nodeh}" -U "${nodeu}" -P "${nodep}" power status | \
            grep -Eq ' on| off'; do
            echo "<4>${nodeh} pdu socket is not up yet... waiting"
            sleep 15
            retry_max=$(( retry_max - 1 ))
          done
          [ $retry_max -le 0 ] && echo "<3>${nodeh} pdu socket needs investigation..."
        fi
        ipmitool -I lanplus -H "${nodeh}" -U "${nodeu}" -P "${nodep}" \
          chassis bootparam set bootflag force_pxe options=PEF,watchdog,reset,power
        ipmitool -I lanplus -H "${nodeh}" -U "${nodeu}" -P "${nodep}" power reset
      else
        echo "<3>Invalid line: check the node variables"
      fi
    done <<< "$(printf "%s\n" "${nodes[@]}")"

    echo -e "<4>Waiting for 10 mins for the nodes to wipe disks and power off..." && sleep 120
    while read -r nodeh nodeu nodep pdu_uri; do
      retry_max=32
      while [ $retry_max -gt 0 ] && ! ipmitool -I lanplus -H "${nodeh}" -U "${nodeu}" -P "${nodep}" power status | \
        grep -q "Power is off"; do
        echo "<4>${nodeh} is not powered off yet... waiting"
        sleep 15
        retry_max=$(( retry_max - 1 ))
      done
      [ $retry_max -le 0 ] && echo "<3>${nodeh} not powered off, needs investigation"
    done <<< "$(printf "%s\n" "${nodes[@]}")"
  fi

  # Clear cluster entries from the conf files
  sed -i "/${CLUSTER}/d" "${conf_files[@]}"

  # Restart dnsmasq container
  docker restart dhcpd

  # Reload and flush bind9 container
  docker exec bind9 rndc reload && \
    docker exec bind9 rndc flush
}

# Check if haproxy container is running for more than 3 days
for i in $(docker ps -a --format "{{.Names}}" | grep "haproxy-")
do
  creation_ts=$(docker inspect --format="{{.Created}}" "$i")
  create_ts=$(date -d "${creation_ts}" +%s)
  now_ts=$(date +%s)
  diff_in_ts=$((now_ts - create_ts))
  time_in_days=$((diff_in_ts / 86400))
  if [ "${time_in_days}" -ge 3 ]; then
    CLUSTER=${i#haproxy-}
    echo "<3>$CLUSTER is more than 3 days old, prunning started...."
    prune_nodes "$CLUSTER"
    echo "<4>$CLUSTER - Cleanu-up, wipe disks and deprovisioning completed successfully"
  fi
done
