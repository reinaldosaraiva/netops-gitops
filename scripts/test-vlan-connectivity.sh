#!/bin/bash
# =============================================================================
# Nokia SR Linux VLAN Connectivity Test Script
# GitOps SDC/Kubenet Infrastructure
# =============================================================================

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# Configuration
declare -A SWITCHES=(
    ["spine-1"]="172.40.40.11"
    ["spine-2"]="172.40.40.12"
    ["leaf-1"]="172.40.40.21"
    ["leaf-2"]="172.40.40.22"
)

declare -A VLAN_GATEWAYS=(
    ["vlan10"]="192.168.10.1"
    ["vlan20"]="192.168.20.1"
    ["vlan30"]="192.168.30.1"
)

SSH_USER="admin"
SSH_PASS="admin123"
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -o LogLevel=ERROR"

# Counters
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# =============================================================================
# Helper Functions
# =============================================================================

log_header() {
    echo ""
    echo -e "${BOLD}${CYAN}════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}${CYAN}  $1${NC}"
    echo -e "${BOLD}${CYAN}════════════════════════════════════════════════════════════${NC}"
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_pass() {
    echo -e "${GREEN}[PASS]${NC} $1"
    ((PASSED_TESTS++))
    ((TOTAL_TESTS++))
}

log_fail() {
    echo -e "${RED}[FAIL]${NC} $1"
    ((FAILED_TESTS++))
    ((TOTAL_TESTS++))
}

log_skip() {
    echo -e "${YELLOW}[SKIP]${NC} $1"
}

ssh_cmd() {
    local host=$1
    local cmd=$2
    sshpass -p "$SSH_PASS" ssh $SSH_OPTS "$SSH_USER@$host" "$cmd" 2>/dev/null
}

# =============================================================================
# Test Functions
# =============================================================================

test_ssh_connectivity() {
    log_header "SSH Connectivity Test"

    for switch in "${!SWITCHES[@]}"; do
        local ip="${SWITCHES[$switch]}"
        if timeout 5 sshpass -p "$SSH_PASS" ssh $SSH_OPTS "$SSH_USER@$ip" "echo ok" &>/dev/null; then
            log_pass "$switch ($ip) - SSH accessible"
        else
            log_fail "$switch ($ip) - SSH not accessible"
        fi
    done
}

test_network_instances() {
    log_header "Network Instances (VLANs) Test"

    local switch="spine-1"
    local ip="${SWITCHES[$switch]}"

    log_info "Checking network-instances on $switch..."

    local instances=$(ssh_cmd "$ip" "info from state network-instance name" 2>/dev/null | grep -E "^\s+name:" | awk '{print $2}')

    for vlan in "vlan10" "vlan20" "vlan30"; do
        if echo "$instances" | grep -q "$vlan"; then
            log_pass "Network-instance $vlan exists on $switch"
        else
            log_fail "Network-instance $vlan NOT found on $switch"
        fi
    done
}

test_irb_interfaces() {
    log_header "IRB Interface Test"

    local switch="spine-1"
    local ip="${SWITCHES[$switch]}"

    log_info "Checking IRB subinterfaces on $switch..."

    for vlan_id in 10 20 30; do
        local result=$(ssh_cmd "$ip" "info from state interface irb0 subinterface $vlan_id oper-state" 2>/dev/null | grep "oper-state" | awk '{print $2}')

        if [[ "$result" == "up" ]]; then
            log_pass "irb0.$vlan_id is UP"
        elif [[ -z "$result" ]]; then
            log_fail "irb0.$vlan_id not found"
        else
            log_fail "irb0.$vlan_id is $result (expected: up)"
        fi
    done
}

test_irb_ip_addresses() {
    log_header "IRB IP Address Test"

    local switch="spine-1"
    local ip="${SWITCHES[$switch]}"

    log_info "Checking IRB IP addresses on $switch..."

    declare -A expected_ips=(
        ["10"]="192.168.10.1/24"
        ["20"]="192.168.20.1/24"
        ["30"]="192.168.30.1/24"
    )

    for vlan_id in 10 20 30; do
        local expected="${expected_ips[$vlan_id]}"
        local result=$(ssh_cmd "$ip" "info from state interface irb0 subinterface $vlan_id ipv4 address" 2>/dev/null | grep "ip-prefix" | awk '{print $2}')

        if [[ "$result" == "$expected" ]]; then
            log_pass "irb0.$vlan_id has correct IP: $result"
        elif [[ -z "$result" ]]; then
            log_fail "irb0.$vlan_id has no IP configured"
        else
            log_fail "irb0.$vlan_id has wrong IP: $result (expected: $expected)"
        fi
    done
}

test_inter_vlan_routing() {
    log_header "Inter-VLAN Routing Test"

    local switch="spine-1"
    local ip="${SWITCHES[$switch]}"

    log_info "Testing routing between VLANs from $switch..."

    # From spine-1, ping all VLAN gateways
    for vlan in "${!VLAN_GATEWAYS[@]}"; do
        local gw_ip="${VLAN_GATEWAYS[$vlan]}"

        # Use network-instance default for inter-VLAN routing test
        local result=$(ssh_cmd "$ip" "ping $gw_ip network-instance default count 2 timeout 2" 2>/dev/null | grep -c "bytes from" || echo "0")

        if [[ "$result" -ge 1 ]]; then
            log_pass "$vlan gateway $gw_ip reachable from $switch"
        else
            log_fail "$vlan gateway $gw_ip NOT reachable from $switch"
        fi
    done
}

test_mac_vrf_interfaces() {
    log_header "MAC-VRF Interface Membership Test"

    local switch="spine-1"
    local ip="${SWITCHES[$switch]}"

    log_info "Checking MAC-VRF interface bindings on $switch..."

    for vlan_id in 10 20 30; do
        local interfaces=$(ssh_cmd "$ip" "info from state network-instance vlan$vlan_id interface" 2>/dev/null | grep "name:" | awk '{print $2}' | tr '\n' ' ')

        if [[ -n "$interfaces" ]]; then
            log_pass "vlan$vlan_id has interfaces: $interfaces"
        else
            log_fail "vlan$vlan_id has no interfaces bound"
        fi
    done
}

test_bgp_sessions() {
    log_header "BGP Session Test"

    for switch in "spine-1" "leaf-1"; do
        local ip="${SWITCHES[$switch]}"

        log_info "Checking BGP neighbors on $switch..."

        local established=$(ssh_cmd "$ip" "info from state network-instance default protocols bgp neighbor * session-state" 2>/dev/null | grep -c "established" || echo "0")

        if [[ "$established" -ge 1 ]]; then
            log_pass "$switch has $established BGP session(s) established"
        else
            log_fail "$switch has no established BGP sessions"
        fi
    done
}

print_summary() {
    log_header "Test Summary"

    echo ""
    echo -e "  ${BOLD}Total Tests:${NC}  $TOTAL_TESTS"
    echo -e "  ${GREEN}Passed:${NC}       $PASSED_TESTS"
    echo -e "  ${RED}Failed:${NC}       $FAILED_TESTS"
    echo ""

    local pass_rate=0
    if [[ $TOTAL_TESTS -gt 0 ]]; then
        pass_rate=$((PASSED_TESTS * 100 / TOTAL_TESTS))
    fi

    if [[ $pass_rate -ge 90 ]]; then
        echo -e "  ${GREEN}${BOLD}Pass Rate: ${pass_rate}% - EXCELLENT${NC}"
    elif [[ $pass_rate -ge 70 ]]; then
        echo -e "  ${YELLOW}${BOLD}Pass Rate: ${pass_rate}% - ACCEPTABLE${NC}"
    else
        echo -e "  ${RED}${BOLD}Pass Rate: ${pass_rate}% - NEEDS ATTENTION${NC}"
    fi

    echo ""
    echo -e "  ${CYAN}Timestamp: $(date '+%Y-%m-%d %H:%M:%S')${NC}"
    echo ""
}

show_help() {
    cat << EOF
Nokia SR Linux VLAN Connectivity Test Script

USAGE:
    $(basename "$0") [OPTIONS]

OPTIONS:
    -h, --help       Show this help message
    -s, --ssh        Test SSH connectivity only
    -v, --vlans      Test VLAN/network-instance only
    -i, --irb        Test IRB interfaces only
    -r, --routing    Test inter-VLAN routing only
    -b, --bgp        Test BGP sessions only
    -a, --all        Run all tests (default)

ENVIRONMENT:
    Nokia SR Linux switches accessible via SSH
    Credentials: admin / admin123

SWITCHES:
    spine-1: 172.40.40.11
    spine-2: 172.40.40.12
    leaf-1:  172.40.40.21
    leaf-2:  172.40.40.22

VLANS:
    VLAN 10 (Data):       192.168.10.0/24  Gateway: 192.168.10.1
    VLAN 20 (Voice):      192.168.20.0/24  Gateway: 192.168.20.1
    VLAN 30 (Management): 192.168.30.0/24  Gateway: 192.168.30.1

EXAMPLES:
    # Run all tests
    $(basename "$0")

    # Test SSH only
    $(basename "$0") --ssh

    # Test routing only
    $(basename "$0") --routing

EOF
}

# =============================================================================
# Main
# =============================================================================

main() {
    local run_all=true
    local run_ssh=false
    local run_vlans=false
    local run_irb=false
    local run_routing=false
    local run_bgp=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                show_help
                exit 0
                ;;
            -s|--ssh)
                run_ssh=true
                run_all=false
                shift
                ;;
            -v|--vlans)
                run_vlans=true
                run_all=false
                shift
                ;;
            -i|--irb)
                run_irb=true
                run_all=false
                shift
                ;;
            -r|--routing)
                run_routing=true
                run_all=false
                shift
                ;;
            -b|--bgp)
                run_bgp=true
                run_all=false
                shift
                ;;
            -a|--all)
                run_all=true
                shift
                ;;
            *)
                echo "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done

    echo ""
    echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${CYAN}║   Nokia SR Linux VLAN Connectivity Test - GitOps SDC Lab    ║${NC}"
    echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${BLUE}Started: $(date '+%Y-%m-%d %H:%M:%S')${NC}"

    # Check for sshpass
    if ! command -v sshpass &>/dev/null; then
        echo -e "${RED}ERROR: sshpass is required but not installed${NC}"
        echo "Install with: brew install hudochenkov/sshpass/sshpass (macOS)"
        echo "           or: apt install sshpass (Linux)"
        exit 1
    fi

    if [[ "$run_all" == true ]]; then
        test_ssh_connectivity
        test_network_instances
        test_irb_interfaces
        test_irb_ip_addresses
        test_mac_vrf_interfaces
        test_inter_vlan_routing
        test_bgp_sessions
    else
        [[ "$run_ssh" == true ]] && test_ssh_connectivity
        [[ "$run_vlans" == true ]] && test_network_instances
        [[ "$run_irb" == true ]] && { test_irb_interfaces; test_irb_ip_addresses; }
        [[ "$run_routing" == true ]] && test_inter_vlan_routing
        [[ "$run_bgp" == true ]] && test_bgp_sessions
    fi

    print_summary

    if [[ $FAILED_TESTS -gt 0 ]]; then
        exit 1
    fi
    exit 0
}

main "$@"
