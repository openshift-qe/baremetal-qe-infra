#!/bin/bash
set -x

nmcli connection up ovs2brBR
conn_status=$(nmcli connection show --active | grep -q 'ovs2brBR' && echo "active" || echo "inactive")
if [ "$conn_status" = "active" ]; then
    echo "Connection established successfully."
    exit 0
else
    echo "Failed to establish connection."
    exit 1
fi
