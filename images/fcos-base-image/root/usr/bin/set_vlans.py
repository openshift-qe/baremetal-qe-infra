#!/bin/python3
import os
import sys
from jnpr.junos import Device
from jnpr.junos.utils.config import Config

try:
    vlan_name = os.environ["VLAN_NAME"]
    interfaces = os.environ["INTERFACES"].split(",")
    switch_host = os.environ.get("SWITCH_HOST", "")
    switch_user = os.environ.get("SWITCH_USER", "")
    switch_pass = os.environ.get("SWITCH_PASS", "")
    switch_port = os.environ.get("SWITCH_PORT", 22)
    action = os.environ.get("ACTION", "CREATE")
    if action == "CREATE":
        vlan_id = os.environ["VLAN_ID"]
except KeyError as key:
    print(f"Environment {key} is not set")
    sys.exit(1)


def up():
    cu.load(f'set vlans {vlan_name} vlan-id {vlan_id}')
    cu.load(f'set interfaces ge-0/0/0 unit 0 family ethernet-switching vlan members {vlan_name}', format='set')
    for interface in interfaces:
        cu.load(f'delete interfaces {interface} unit 0 family ethernet-switching vlan members', format='set', ignore_warning=True)
        cu.load(f'set interfaces {interface} unit 0 family ethernet-switching vlan members {vlan_name}', format='set')

def down():
    cu.load(f'delete interfaces ge-0/0/0 unit 0 family ethernet-switching vlan members {vlan_name}', format='set', ignore_warning=True)
    for interface in interfaces:
        cu.load(f'delete interfaces {interface} unit 0 family ethernet-switching vlan members', format='set', ignore_warning=True)
        cu.load(f'set interfaces {interface} unit 0 family ethernet-switching vlan members vlan8', format='set')
    cu.load(f'delete vlans {vlan_name}', ignore_warning=True)


with Device(host=switch_host, user=switch_user, password=switch_pass, port=switch_port) as dev:
    with Config(dev, mode='private') as cu:
        up() if action == "CREATE" else down()
        cu.pdiff()
        cu.commit(force_sync=True,sync=True,timeout=300,detail=True)
