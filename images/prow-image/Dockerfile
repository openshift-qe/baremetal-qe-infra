# This Dockerfile builds the image used by baremetal qe installation tests
FROM quay.io/centos/centos:stream9
ENV HOME /output
RUN set -x; INSTALL_PKGS="bash bc bind-utils butane ca-certificates conntrack-tools coreos-installer diffutils \
        ethtool file findutils gawk git gzip hostname iperf3 ipmitool iproute iputils jq libvirt-client lsof make \
        mtr net-tools nmap-ncat nmstate openssh procps procps-ng python3 python3-pip rsync shadow-utils socat strace \
        tar tcpdump tree util-linux wget which zip" && \
  mkdir -p ${HOME} && \
  dnf install --setopt=install_weak_deps=False --nodocs -y $INSTALL_PKGS && \
  dnf clean all && \
  rm -rf /var/cache/yum/*

RUN set -x; \
    OC_TAR_URL="https://mirror.openshift.com/pub/openshift-v4/$(uname -m)/clients/ocp/latest/openshift-client-linux.tar.gz" && \
    curl -q -o /tmp/oc.tar.gz "$OC_TAR_URL" && \
    tar -C /usr/bin/ -xvf /tmp/oc.tar.gz oc && \
    rm -f /tmp/oc.tar.gz

RUN wget -O /usr/local/bin/yq \
  https://github.com/mikefarah/yq/releases/download/v4.30.4/yq_linux_$(uname -m \
    | sed 's/x86_64/amd64/;s/aarch64/arm64/') && \
  chmod +x /usr/local/bin/yq && \
  pip3 install setuptools-rust && \
  pip3 install --upgrade pip && \
  INSTALL_PYTHON3_PKGS="netaddr junos-eznc wheel redfish sushy-tools" && \
  pip3 install --ignore-installed $INSTALL_PYTHON3_PKGS
