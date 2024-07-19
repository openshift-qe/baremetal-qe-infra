#!/bin/bash
# shellcheck disable=SC2034
set -aeuo pipefail

## This script supports the manual deprovisioning of a baremetal cluster.
## It is meant to be run like this:
## podman run -it -v "/root/.ssh/id_rsa:/var/builds/$1/ssh-key:z" -v /var/builds:/var/builds:Z --rm \
##   registry.ci.openshift.org/ci/baremetal-qe-base:latest /usr/bin/deprovision.sh "$1"

if [ -z "${AUX_HOST:-}" ]; then
  echo "AUX_HOST environment variable is not set, exiting..."
  exit 1
fi

echo "Setting up environment..."
NAMESPACE="$1"
CLUSTER_PROFILE_DIR="/var/builds/$1"
SHARED_DIR="/var/builds/$1"
ARTIFACT_DIR="/var/builds/$1"
SELF_MANAGED_NETWORK="true"
DISCONNECTED="true"
PROVISIONING_NET_DEV="prov" # Remove this variable after https://github.com/openshift/release/pull/46960 is merged
# End (exported) environment variables setup
set +a

echo "${NAMESPACE}" > "${SHARED_DIR}/cluster_name"
touch "${SHARED_DIR}/"{CLUSTER_INSTALL_START_TIME,provisioning_network}

echo "Updating the openshift/release repository code..."

REPO_DIR="/tmp/openshift-release"
mkdir -p "${REPO_DIR}"
pushd "${REPO_DIR}" || exit 1
[ -d .git ] || git init -q
git remote | grep -q origin || git remote add origin https://github.com/openshift/release.git
git config core.sparseCheckout true
echo "ci-operator/step-registry/baremetal/lab/post" > .git/info/sparse-checkout
echo "ci-operator/step-registry/baremetal/lab/ipi" >> .git/info/sparse-checkout
git fetch --depth 1 origin master
git reset --hard origin/master
pushd ci-operator/step-registry/baremetal/lab/post || exit 1

echo "Running the post-installation steps..."
set +e
set -x
bash ./dhcp-pxe-conf/baremetal-lab-post-dhcp-pxe-conf-commands.sh
for architecture in aarch64 amd64; do
  export architecture="${architecture}"
  [ -f "${CLUSTER_PROFILE_DIR}/provisioning-host-ssh-port-${architecture}" ] && \
  bash ../ipi/deprovision/baremetal-lab-ipi-deprovision-commands.sh
done
bash ./wipe/baremetal-lab-post-wipe-commands.sh
bash ./dns/baremetal-lab-post-dns-commands.sh
bash ./firewall/baremetal-lab-post-firewall-commands.sh
bash ./load-balancer/baremetal-lab-post-load-balancer-commands.sh
for architecture in aarch64 amd64; do
  export architecture="${architecture}"
  [ -f "${CLUSTER_PROFILE_DIR}/provisioning-host-ssh-port-${architecture}" ] && \
  bash ./provisioning-network/baremetal-lab-post-provisioning-network-commands.sh
done
bash ./release-nodes/baremetal-lab-post-release-nodes-commands.sh
exit 0
