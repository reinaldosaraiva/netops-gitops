#!/bin/bash
# gNMI Subscribe for real-time logs and telemetry from network switches
# Requires: gnmic (https://gnmic.openconfig.net/)
#
# Usage:
#   ./gnmi-subscribe-logs.sh nokia-spine-1 system    # System events
#   ./gnmi-subscribe-logs.sh nokia-spine-1 interface # Interface counters
#   ./gnmi-subscribe-logs.sh arista-spine-1 system   # Arista system
#
# Install gnmic: bash -c "$(curl -sL https://get-gnmic.openconfig.net)"

set -e

# Switch definitions
declare -A NOKIA_SWITCHES=(
  ["nokia-spine-1"]="172.40.40.11:57401"
  ["nokia-spine-2"]="172.40.40.12:57401"
  ["nokia-leaf-1"]="172.40.40.21:57401"
  ["nokia-leaf-2"]="172.40.40.22:57401"
)

declare -A ARISTA_SWITCHES=(
  ["arista-spine-1"]="172.20.20.11:6030"
  ["arista-leaf-1"]="172.20.20.21:6030"
  ["arista-leaf-2"]="172.20.20.22:6030"
)

# Credentials
NOKIA_USER="admin"
NOKIA_PASS="admin123"
ARISTA_USER="admin"
ARISTA_PASS="admin"

# gNMI paths for different subscription types
declare -A NOKIA_PATHS=(
  ["system"]="/system/information"
  ["interface"]="/interface[name=*]/statistics"
  ["cpu"]="/platform/control[slot=*]/cpu[index=all]/total"
  ["memory"]="/platform/control[slot=*]/memory"
  ["network-instance"]="/network-instance[name=*]/protocols"
  ["bgp"]="/network-instance[name=default]/protocols/bgp"
  ["lldp"]="/system/lldp/interface[name=*]/neighbor"
)

declare -A ARISTA_PATHS=(
  ["system"]="/system/state"
  ["interface"]="/interfaces/interface[name=*]/state/counters"
  ["cpu"]="/components/component[name=*]/cpu/utilization"
  ["memory"]="/system/memory/state"
  ["bgp"]="/network-instances/network-instance[name=default]/protocols/protocol[identifier=BGP][name=BGP]/bgp"
  ["lldp"]="/lldp/interfaces/interface[name=*]/neighbors"
)

usage() {
  echo "Usage: $0 <switch-name> <subscription-type> [--sample-interval <seconds>]"
  echo ""
  echo "Switch names:"
  echo "  Nokia:  nokia-spine-1, nokia-spine-2, nokia-leaf-1, nokia-leaf-2"
  echo "  Arista: arista-spine-1, arista-leaf-1, arista-leaf-2"
  echo ""
  echo "Subscription types:"
  echo "  system     - System information and events"
  echo "  interface  - Interface statistics and counters"
  echo "  cpu        - CPU utilization"
  echo "  memory     - Memory usage"
  echo "  bgp        - BGP session state"
  echo "  lldp       - LLDP neighbor information"
  echo ""
  echo "Options:"
  echo "  --sample-interval <seconds>  Sampling interval (default: 10)"
  echo "  --once                       Get single sample instead of stream"
  echo ""
  echo "Examples:"
  echo "  $0 nokia-spine-1 interface"
  echo "  $0 arista-leaf-1 system --sample-interval 5"
  echo "  $0 nokia-spine-2 bgp --once"
  exit 1
}

# Check gnmic installation
check_gnmic() {
  if ! command -v gnmic &> /dev/null; then
    echo "ERROR: gnmic not found. Install with:"
    echo "  bash -c \"\$(curl -sL https://get-gnmic.openconfig.net)\""
    exit 1
  fi
}

# Parse arguments
SWITCH_NAME=""
SUB_TYPE=""
SAMPLE_INTERVAL=10
ONCE_MODE=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --sample-interval)
      SAMPLE_INTERVAL="$2"
      shift 2
      ;;
    --once)
      ONCE_MODE=true
      shift
      ;;
    --help|-h)
      usage
      ;;
    *)
      if [ -z "$SWITCH_NAME" ]; then
        SWITCH_NAME="$1"
      elif [ -z "$SUB_TYPE" ]; then
        SUB_TYPE="$1"
      fi
      shift
      ;;
  esac
done

if [ -z "$SWITCH_NAME" ] || [ -z "$SUB_TYPE" ]; then
  usage
fi

check_gnmic

# Determine switch type and get address
if [[ "$SWITCH_NAME" == nokia-* ]]; then
  ADDRESS="${NOKIA_SWITCHES[$SWITCH_NAME]}"
  USER="$NOKIA_USER"
  PASS="$NOKIA_PASS"
  PATH_VALUE="${NOKIA_PATHS[$SUB_TYPE]}"
  ENCODING="json_ietf"
elif [[ "$SWITCH_NAME" == arista-* ]]; then
  ADDRESS="${ARISTA_SWITCHES[$SWITCH_NAME]}"
  USER="$ARISTA_USER"
  PASS="$ARISTA_PASS"
  PATH_VALUE="${ARISTA_PATHS[$SUB_TYPE]}"
  ENCODING="json_ietf"
else
  echo "ERROR: Unknown switch: $SWITCH_NAME"
  usage
fi

if [ -z "$ADDRESS" ]; then
  echo "ERROR: Switch $SWITCH_NAME not found"
  usage
fi

if [ -z "$PATH_VALUE" ]; then
  echo "ERROR: Unknown subscription type: $SUB_TYPE"
  usage
fi

echo "============================================"
echo "gNMI Subscribe - $SWITCH_NAME"
echo "============================================"
echo "Target:   $ADDRESS"
echo "Path:     $PATH_VALUE"
echo "Interval: ${SAMPLE_INTERVAL}s"
echo "Mode:     $([ "$ONCE_MODE" = true ] && echo 'ONCE' || echo 'STREAM')"
echo "============================================"
echo ""

if [ "$ONCE_MODE" = true ]; then
  # Single GET request
  gnmic -a "$ADDRESS" \
    --insecure \
    -u "$USER" \
    -p "$PASS" \
    get \
    --path "$PATH_VALUE" \
    --encoding "$ENCODING" \
    --format flat
else
  # Stream subscription
  gnmic -a "$ADDRESS" \
    --insecure \
    -u "$USER" \
    -p "$PASS" \
    subscribe \
    --path "$PATH_VALUE" \
    --stream-mode sample \
    --sample-interval "${SAMPLE_INTERVAL}s" \
    --encoding "$ENCODING" \
    --format event
fi
