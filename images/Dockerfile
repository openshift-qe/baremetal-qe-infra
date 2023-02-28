# This Dockerfile builds the image used by baremetal qe installation tests
FROM registry.ci.openshift.org/ocp/4.12:cli
ENV HOME /output
RUN set -x; INSTALL_PKGS="ansible openssh rsync wget bc file findutils git hostname lsof make \
      socat tar tree util-linux wget which zip curl gawk iputils jq iproute ca-certificates \
      nmap-ncat socat mtr bash net-tools bind-utils iperf3 tcpdump procps conntrack-tools \
      iputils ethtool strace ipmitool butane libvirt-client" && \
  mkdir -p ${HOME} && \
  yum install --setopt=install_weak_deps=False --nodocs -y $INSTALL_PKGS && \
  yum clean all && \
  rm -rf /var/cache/yum/*
RUN wget -O /usr/local/bin/yq \
  https://github.com/mikefarah/yq/releases/download/v4.30.4/yq_linux_$(uname -m \
    | sed 's/x86_64/amd64/;s/aarch64/arm64/') && \
  chmod +x /usr/local/bin/yq && \
  pip3 install setuptools-rust && \
  pip3 install --upgrade pip && \
  ansible-galaxy collection install -vvvv community.docker community.general dellemc.openmanage && \
  chmod -R g=u "${HOME}/.ansible/" && \
  INSTALL_PYTHON3_PKGS="netaddr junos-eznc wheel" && \
  pip3 install --ignore-installed $INSTALL_PYTHON3_PKGS && \
  git clone https://github.com/dell/omsdk.git /tmp/omsdk && \
  cd /tmp/omsdk && \
  pip3 install -r requirements-python3x.txt && \
  sh build.sh 1.2 503 && \
  cd dist && \
  pip3 install omsdk-1.2.503-py2.py3-none-any.whl

