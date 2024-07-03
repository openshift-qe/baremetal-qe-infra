#!/bin/bash

BUILD_USER=${BUILD_USER:-jenkins}
[ -z "$BUILD_ID" ] && echo "No build ID provided" && exit 1
[ -z "$BUILD_USER" ] && echo "No build user provided" && exit 1

# The defaults are due to historical reasons, but they can be overridden by the caller
REQUEST_BOOTSTRAP_HOST=${REQUEST_BOOTSTRAP_HOST:-true}
REQUEST_VIPS=${REQUEST_VIPS:-false}
APPEND=${APPEND:-false}
ARCH=${ARCH:-aarch64}
N_MASTERS=${N_MASTERS:-3}
N_WORKERS=${N_WORKERS:-3}
MAX_WAIT_MINS=${MAX_WAIT_MINS:-30}
RESERVED_FILE=${RESERVED_FILE:-/etc/hosts_pool_reserved}
INVENTORY_FILE=${INVENTORY_FILE:-/etc/hosts_pool_inventory}
VENDOR_REGEX=""

if [ -n "$VENDOR" ]; then
  VENDOR_REGEX=",${VENDOR},"
fi

if [ -s /etc/hosts_pool_lock ]; then
    echo "The infra reservation is stopped:"
    cat /etc/hosts_pool_lock
    exit 1
fi

BUILD_DIR="/var/builds/$BUILD_ID"
mkdir -p "${BUILD_DIR}"

APPEND=${APPEND,,}
REQUEST_BOOTSTRAP_HOST=${REQUEST_BOOTSTRAP_HOST,,}

CSV_COLUMNS=$(head -n 1 "$INVENTORY_FILE" | sed 's/#//'),build_id,build_user,name
NUM_HOSTS=$(( N_MASTERS + N_WORKERS ))

if [ -f "${BUILD_DIR}/hosts.yaml" ] && [ "$APPEND" != "true" ]; then
    echo "A reservation for the build id ${BUILD_ID} already exists. Failing."
    exit 1
fi

if [ "$REQUEST_BOOTSTRAP_HOST" == "true" ]; then
    NUM_HOSTS=$(( NUM_HOSTS + 1 ))
fi

if [ "$APPEND" == "true" ]; then
    POSTFIX="${POSTFIX:--a}"
fi

echo "Waiting up to $MAX_WAIT_MINS minutes for host reservation"
echo "Require $N_MASTERS masters and $N_WORKERS workers $([ "$REQUEST_BOOTSTRAP_HOST" == "true" ] && echo -n '(+ 1 bootstrap node)') = $NUM_HOSTS hosts"
echo "Build ID $BUILD_ID from user $BUILD_USER"

LOCK="/tmp/reserved_file.lock"
LOCK_FD=200
touch "$LOCK"
exec 200>"$LOCK"
set -e
trap catch_exit ERR INT

function catch_exit {
  echo "Releasing lock $LOCK_FD ($LOCK)"
  flock -u "$LOCK_FD"
  exit 1
}

function check_available_hosts() {
  echo "Acquiring lock $LOCK_FD ($LOCK) (waiting up to 10 minutes)"
  flock -w 600 "$LOCK_FD"
  echo "Lock acquired $LOCK_FD ($LOCK)"
  mapfile -t CANDIDATES_HOSTS < <(grep -v -f <(cut -f1,2,3 -d, "$RESERVED_FILE") <(sed -e '/^#/d' -e '/^mac.*$/d' "$INVENTORY_FILE") | grep -E ",${ARCH},.*$VENDOR_REGEX")
  COUNT=${#CANDIDATES_HOSTS[@]}
  if [ "$COUNT" -lt "$NUM_HOSTS" ]; then
    echo "Unable to reserve the required amount of hosts witch ARCH: $ARCH and Vendor: ${VENDOR:-Any} (retry n. $retry_count), releasing lock..."
    flock -u "$LOCK_FD"
    return 1
  fi
  return 0
}

function reserve_hosts() {
  local ROLE=$1
  local COUNT=$2
  if [ "$APPEND" != "true" ]; then
    echo "$CSV_COLUMNS" > "${BUILD_DIR}/${ROLE}.csv"
  fi
  for ((i=0; i<COUNT; i++)); do
    OUTPUT[j]="${CANDIDATES_HOSTS[j]},$BUILD_ID,$BUILD_USER,${ROLE}${POSTFIX}-$(printf "%02d" "$i")"
    echo "${OUTPUT[j]}" >> "${BUILD_DIR}/${ROLE}.csv"
    echo "${OUTPUT[j]}" >> "${BUILD_DIR}/hosts.csv"
    j=$(( j + 1 ))
  done
}

retry_count=0
while ! check_available_hosts; do
  sleep 60s
  retry_count=$(( retry_count + 1 ))
  if [ "$retry_count" -gt "$MAX_WAIT_MINS" ]; then
    echo "Timeout while waiting for available hosts"
    exit 1
  fi
done

OUTPUT=()
j=0
if [ "$APPEND" != "true" ]; then
    echo "$CSV_COLUMNS" > "${BUILD_DIR}/hosts.csv"
fi
reserve_hosts "master" "$N_MASTERS"
reserve_hosts "worker" "$N_WORKERS"
[ "$REQUEST_BOOTSTRAP_HOST" == "true" ] && reserve_hosts "bootstrap" 1
printf '%s\n' "${OUTPUT[@]}" >> "$RESERVED_FILE"

if [ "$REQUEST_VIPS" == "true" ]; then
    FIRST_HOST_ID=$(echo "${CANDIDATES_HOSTS[0]}" | cut -f3 -d,)
    FIRST_HOST_ID_HEX=$(printf '%03x' "$FIRST_HOST_ID")
    
    INGRESS_VIP="${INGRESS_VIPS_SUBNET_PREFIX:-192.168.82.}${FIRST_HOST_ID}"
    API_VIP="${API_VIPS_SUBNET_PREFIX:-192.168.81.}${FIRST_HOST_ID}"
    INGRESS_VIP_V6="${IPV6_INGRESS_VIPS_SUBNET_PREFIX:-fd99:2222:3456::2:}${FIRST_HOST_ID_HEX}"
    API_VIP_V6="${IPV6_API_VIPS_SUBNET_PREFIX:-fd99:2222:3456::1:}${FIRST_HOST_ID_HEX}"
    
    # Create a single JSON object
    echo "{
  \"ingress_vip\": \"$INGRESS_VIP\",
  \"api_vip\": \"$API_VIP\",
  \"ingress_vip_v6\": \"$INGRESS_VIP_V6\",
  \"api_vip_v6\": \"$API_VIP_V6\"
}" > "${BUILD_DIR}/vips.json"
fi


echo "Releasing lock $LOCK_FD ($LOCK)"
flock -u "$LOCK_FD"

yq -p csv -o yaml "${BUILD_DIR}/hosts.csv" > "${BUILD_DIR}/hosts.yaml"
yq -p csv -o yaml "${BUILD_DIR}/worker.csv" > "${BUILD_DIR}/worker.yaml"
yq -p csv -o yaml "${BUILD_DIR}/master.csv" > "${BUILD_DIR}/master.yaml"
touch "${BUILD_DIR}/vips.yaml"
if [ "$REQUEST_VIPS" == "true" ]; then
  yq -p json -o yaml "${BUILD_DIR}/vips.json" > "${BUILD_DIR}/vips.yaml"
fi

yq < "${BUILD_DIR}/hosts.yaml"
