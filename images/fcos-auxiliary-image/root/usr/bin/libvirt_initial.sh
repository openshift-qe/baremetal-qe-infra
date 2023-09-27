#!/bin/bash

# Check the 'default' pool existing, define the pool if it doesn't exist
default_image_pool=$(virsh pool-list --all | grep default)

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
default_image_pool_start=$(virsh pool-list | grep default)

if [[ -z ${default_image_pool_start} ]]; then
    virsh pool-start default
fi
# Auto-start the default pool
virsh pool-autostart default
