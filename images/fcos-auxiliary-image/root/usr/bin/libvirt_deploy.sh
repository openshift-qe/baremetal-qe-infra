#!/bin/bash

libvirt=`yum list installed | grep libvirt`

# 'dnf -y install bridge-utils libvirt virt-install qemu-kvm" if libvirtd is not installed
if [[ -z ${libvirt} ]]; then
    dnf -y install bridge-utils libvirt virt-install qemu-kvm
else
# Start libvirtd if it is inactive
    is_active=`systemctl is-active libvirtd`
    if [ "$status" = "inactive" ]; then
        systemctl start libvirtd
    fi
# Enable libvirtd if it is disabled
    is_enabled=`systemctl is-enabled libvirtd`
    if [ "$status" = "disabled" ]; then
        systemctl enable libvirtd
    fi
fi
# Check the 'default' pool existing, define the pool if it doesn't exist
default_image_pool=`virsh pool-list --all | grep default`

if [[ -z ${default_image_pool} ]]; then
    cat > "/etc/libvirt/storage/default.xml" << EOF
    <pool type='dir'>
      <name>default</name>
        <target>
          <path>/var/lib/libvirt/images</path>
        </target>
    </pool>
EOF
    if [ ! -d "/var/lib/libvirt/images" ]; then
        mkdir -p /var/lib/libvirt/images
    fi
    virsh pool-define default.xml
fi
# Check the 'default' pool started, start the pool if it is inactive
default_image_pool_start=`virsh pool-list | grep default`

echo ${default_image_pool_start}

if [[ -z ${default_image_pool_start} ]]; then
    virsh pool-start default
fi
# Auto-start the default pool
virsh pool-autostart default
