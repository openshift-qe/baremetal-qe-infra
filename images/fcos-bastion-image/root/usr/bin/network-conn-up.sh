#!/bin/bash
set -x

nmcli connection up ovs2brBR
nmcli connection show --active | grep -q 'ovs2brBR'
if [ $? -eq 0 ]; then
    echo "Connection established successfully."
    exit 0
else
    echo "Failed to establish connection."
    exit 1
fi
