#!/bin/bash
# =============================================================================
# Arista cEOS VLAN Connectivity Test Script
# GitOps SDC/Kubenet Infrastructure
# =============================================================================

set -uo pipefail

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
    ["spine-1"]="172.20.20.11"
    ["leaf-1"]="172.20.20.21"
    ["leaf-2"]="172.20.20.22"
)

EXPECTED_VLANS=("10" "20" "30")
SSH_USER="admin"
SSH_PASS="admin"
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
        if timeout 5 sshpass -p "$SSH_PASS" ssh $SSH_OPTS "$SSH_USER@$ip" "show version | head -1" &>/dev/null; then
            log_pass "$switch ($ip) - SSH accessible"
        else
            log_fail "$switch ($ip) - SSH not accessible"
        fi
    done
}

test_vlans() {
    log_header "VLAN Configuration Test"

    for switch in "${!SWITCHES[@]}"; do
        local ip="${SWITCHES[$switch]}"
        log_info "Checking VLANs on $switch..."

        local vlan_output=$(ssh_cmd "$ip" "show vlan" 2>/dev/null)

        for vlan_id in "${EXPECTED_VLANS[@]}"; do
            if echo "$vlan_output" | grep -q "^${vlan_id} "; then
                local vlan_name=$(echo "$vlan_output" | grep "^${vlan_id} " | awk '{print $2}')
                log_pass "$switch: VLAN $vlan_id ($vlan_name) exists"
            else
                log_fail "$switch: VLAN $vlan_id NOT found"
            fi
        done
    done
}

test_interfaces() {
    log_header "Interface Status Test"

    for switch in "${!SWITCHES[@]}"; do
        local ip="${SWITCHES[$switch]}"
        log_info "Checking interfaces on $switch..."

        local status_output=$(ssh_cmd "$ip" "show interfaces status" 2>/dev/null)

        for iface in "Et1" "Et2"; do
            local line=$(echo "$status_output" | grep -E "^${iface}\s" | head -1)
            if [[ -n "$line" ]]; then
                local status=$(echo "$line" | awk '{print $2}')
                if [[ "$status" == "connected" ]]; then
                    log_pass "$switch: $iface is connected"
                else
                    log_fail "$switch: $iface is $status (expected: connected)"
                fi
            else
                log_skip "$switch: $iface not found"
            fi
        done
    done
}

test_trunk_ports() {
    log_header "Trunk Port Configuration Test"

    for switch in "${!SWITCHES[@]}"; do
        local ip="${SWITCHES[$switch]}"
        log_info "Checking trunk ports on $switch..."

        local trunk_output=$(ssh_cmd "$ip" "show interfaces trunk" 2>/dev/null)

        # Check if Et1 is a trunk with VLANs 10,20,30
        if echo "$trunk_output" | grep -qE "Et1.*trunk"; then
            local vlans_on_trunk=$(echo "$trunk_output" | grep -A5 "Et1" | grep -oE "[0-9,]+" | head -1)
            log_pass "$switch: Et1 is trunk with VLANs: $vlans_on_trunk"
        else
            # Check via show vlan for ports
            local vlan_ports=$(ssh_cmd "$ip" "show vlan" 2>/dev/null | grep -E "^10\s" | awk '{print $NF}')
            if echo "$vlan_ports" | grep -q "Et1"; then
                log_pass "$switch: Et1 has VLAN 10"
            else
                log_fail "$switch: Et1 trunk config issue"
            fi
        fi
    done
}

test_lldp_neighbors() {
    log_header "LLDP Neighbors Test"

    for switch in "${!SWITCHES[@]}"; do
        local ip="${SWITCHES[$switch]}"
        log_info "Checking LLDP neighbors on $switch..."

        local lldp_output=$(ssh_cmd "$ip" "show lldp neighbors" 2>/dev/null)
        local neighbor_count=$(echo "$lldp_output" | grep -cE "^Et[0-9]" || echo "0")

        if [[ "$neighbor_count" -gt 0 ]]; then
            log_pass "$switch: $neighbor_count LLDP neighbor(s) detected"
            echo "$lldp_output" | grep -E "^Et[0-9]" | while read line; do
                echo -e "       ${CYAN}$line${NC}"
            done
        else
            log_fail "$switch: No LLDP neighbors found"
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
Arista cEOS VLAN Connectivity Test Script

USAGE:
    $(basename "$0") [OPTIONS]

OPTIONS:
    -h, --help         Show this help message
    -s, --ssh          Test SSH connectivity only
    -v, --vlans        Test VLAN configuration only
    -i, --interfaces   Test interface status only
    -t, --trunk        Test trunk port configuration only
    -l, --lldp         Test LLDP neighbors only
    -a, --all          Run all tests (default)

ENVIRONMENT:
    Arista cEOS switches accessible via SSH
    Credentials: admin / admin

SWITCHES:
    spine-1: 172.20.20.11
    leaf-1:  172.20.20.21
    leaf-2:  172.20.20.22

VLANS:
    VLAN 10 (DATA):       192.168.10.0/24
    VLAN 20 (VOICE):      192.168.20.0/24
    VLAN 30 (MANAGEMENT): 192.168.30.0/24

EXAMPLES:
    # Run all tests
    $(basename "$0")

    # Test SSH only
    $(basename "$0") --ssh

    # Test VLANs only
    $(basename "$0") --vlans

EOF
}

# =============================================================================
# Main
# =============================================================================

main() {
    local run_all=true
    local run_ssh=false
    local run_vlans=false
    local run_interfaces=false
    local run_trunk=false
    local run_lldp=false

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
            -i|--interfaces)
                run_interfaces=true
                run_all=false
                shift
                ;;
            -t|--trunk)
                run_trunk=true
                run_all=false
                shift
                ;;
            -l|--lldp)
                run_lldp=true
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
    echo -e "${BOLD}${CYAN}║   Arista cEOS VLAN Connectivity Test - GitOps SDC Lab        ║${NC}"
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
        test_vlans
        test_interfaces
        test_trunk_ports
        test_lldp_neighbors
    else
        [[ "$run_ssh" == true ]] && test_ssh_connectivity
        [[ "$run_vlans" == true ]] && test_vlans
        [[ "$run_interfaces" == true ]] && test_interfaces
        [[ "$run_trunk" == true ]] && test_trunk_ports
        [[ "$run_lldp" == true ]] && test_lldp_neighbors
    fi

    print_summary

    if [[ $FAILED_TESTS -gt 0 ]]; then
        exit 1
    fi
    exit 0
}

main "$@"
