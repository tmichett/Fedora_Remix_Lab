#!/bin/bash
#
# lab-status.sh
# Displays status of Fedora Lab VMs, network, and configuration
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Configuration (must match create-lab-vms.sh)
NETWORK_NAME="labnet"
NETWORK_SUBNET="192.168.100"
DOMAIN_NAME="example.com"

# VM Definitions
declare -A VM_CONFIG
VM_CONFIG["FedoraLab1"]="10"   # IP suffix
VM_CONFIG["FedoraLab2"]="11"
VM_NAMES=("FedoraLab1" "FedoraLab2")

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Status indicators
OK="${GREEN}●${NC}"
WARN="${YELLOW}●${NC}"
ERR="${RED}●${NC}"
OFF="${RED}○${NC}"

# Helper functions
get_vm_ip() {
    local vm_name="$1"
    echo "${NETWORK_SUBNET}.${VM_CONFIG[$vm_name]}"
}

get_vm_fqdn() {
    local vm_name="$1"
    echo "${vm_name,,}.${DOMAIN_NAME}"
}

# Check if virsh is available and we have access
check_virsh() {
    if ! command -v virsh &> /dev/null; then
        echo -e "${ERR} virsh command not found. Install libvirt-client."
        exit 1
    fi
    
    # Check if we can access libvirt (need root for system VMs)
    if ! virsh list &>/dev/null; then
        echo -e "${WARN} Cannot access libvirt. Running with sudo recommended."
        echo -e "    Run: ${CYAN}sudo $0${NC}"
        echo ""
    fi
}

# Get network status
get_network_status() {
    local status
    
    if ! virsh net-info "${NETWORK_NAME}" &>/dev/null; then
        echo "not_defined"
        return
    fi
    
    if virsh net-info "${NETWORK_NAME}" 2>/dev/null | grep -q "Active:.*yes"; then
        echo "active"
    else
        echo "inactive"
    fi
}

# Get VM definition status
get_vm_defined() {
    local vm_name="$1"
    if virsh dominfo "${vm_name}" &>/dev/null; then
        echo "yes"
    else
        echo "no"
    fi
}

# Get VM running status
get_vm_state() {
    local vm_name="$1"
    local state
    state=$(virsh domstate "${vm_name}" 2>/dev/null)
    echo "${state:-undefined}"
}

# Get VM's actual IP from DHCP leases
get_vm_actual_ip() {
    local vm_name="$1"
    local mac
    
    # Get MAC address from VM definition
    mac=$(virsh domiflist "${vm_name}" 2>/dev/null | grep -oE '([0-9a-f]{2}:){5}[0-9a-f]{2}' | head -1)
    
    if [[ -z "${mac}" ]]; then
        echo "-"
        return
    fi
    
    # Look up IP in network DHCP leases
    local ip
    ip=$(virsh net-dhcp-leases "${NETWORK_NAME}" 2>/dev/null | grep -i "${mac}" | awk '{print $5}' | cut -d'/' -f1)
    
    if [[ -n "${ip}" ]]; then
        echo "${ip}"
    else
        echo "-"
    fi
}

# Check if VM is reachable via ping
check_vm_ping() {
    local ip="$1"
    if [[ "${ip}" == "-" ]]; then
        echo "unknown"
        return
    fi
    
    if ping -c 1 -W 1 "${ip}" &>/dev/null; then
        echo "reachable"
    else
        echo "unreachable"
    fi
}

# Check SSH connectivity
check_vm_ssh() {
    local ip="$1"
    if [[ "${ip}" == "-" ]]; then
        echo "unknown"
        return
    fi
    
    if timeout 2 bash -c "echo >/dev/tcp/${ip}/22" 2>/dev/null; then
        echo "open"
    else
        echo "closed"
    fi
}

# Print section header
print_header() {
    echo ""
    echo -e "${BOLD}${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}${BLUE}  $1${NC}"
    echo -e "${BOLD}${BLUE}═══════════════════════════════════════════════════════════════${NC}"
}

# Print sub-header
print_subheader() {
    echo ""
    echo -e "${CYAN}─── $1 ───${NC}"
}

# Main status display
show_status() {
    echo -e "${BOLD}"
    echo "  ╔═══════════════════════════════════════════════════════════╗"
    echo "  ║           Fedora Lab Environment Status                   ║"
    echo "  ╚═══════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    
    # ─────────────────────────────────────────────────────────────────
    # Network Status
    # ─────────────────────────────────────────────────────────────────
    print_header "Virtual Network"
    
    local net_status
    net_status=$(get_network_status)
    
    echo ""
    printf "  %-20s : %s\n" "Network Name" "${NETWORK_NAME}"
    printf "  %-20s : %s\n" "Subnet" "${NETWORK_SUBNET}.0/24"
    printf "  %-20s : %s\n" "Gateway" "${NETWORK_SUBNET}.1"
    printf "  %-20s : %s\n" "Domain" "${DOMAIN_NAME}"
    echo ""
    
    case "${net_status}" in
        active)
            echo -e "  Status: ${OK} ${GREEN}Active${NC}"
            ;;
        inactive)
            echo -e "  Status: ${WARN} ${YELLOW}Defined but not running${NC}"
            echo -e "         Run: ${CYAN}sudo virsh net-start ${NETWORK_NAME}${NC}"
            ;;
        not_defined)
            echo -e "  Status: ${ERR} ${RED}Not defined${NC}"
            echo -e "         Run: ${CYAN}sudo ./create-lab-vms.sh${NC}"
            ;;
    esac
    
    # Show DHCP leases if network is active
    if [[ "${net_status}" == "active" ]]; then
        print_subheader "DHCP Leases"
        local leases
        leases=$(virsh net-dhcp-leases "${NETWORK_NAME}" 2>/dev/null | tail -n +3)
        if [[ -n "${leases}" ]]; then
            echo "${leases}" | while read -r line; do
                echo "  ${line}"
            done
        else
            echo "  No active DHCP leases"
        fi
    fi
    
    # ─────────────────────────────────────────────────────────────────
    # VM Status
    # ─────────────────────────────────────────────────────────────────
    print_header "Virtual Machines"
    
    # Table header
    echo ""
    printf "  ${BOLD}%-15s %-12s %-18s %-28s${NC}\n" "VM Name" "State" "IP Address" "Hostname"
    printf "  %-15s %-12s %-18s %-28s\n" "───────────────" "────────────" "──────────────────" "────────────────────────────"
    
    for vm_name in "${VM_NAMES[@]}"; do
        local defined
        defined=$(get_vm_defined "${vm_name}")
        
        local state="-"
        local actual_ip="-"
        local expected_ip
        expected_ip=$(get_vm_ip "${vm_name}")
        local fqdn
        fqdn=$(get_vm_fqdn "${vm_name}")
        
        if [[ "${defined}" == "yes" ]]; then
            state=$(get_vm_state "${vm_name}")
            if [[ "${state}" == "running" ]]; then
                actual_ip=$(get_vm_actual_ip "${vm_name}")
                if [[ "${actual_ip}" == "-" ]]; then
                    actual_ip="${expected_ip} (expected)"
                fi
            fi
        else
            state="not defined"
        fi
        
        # Color the state
        local state_display
        case "${state}" in
            running)
                state_display="${OK} ${GREEN}running${NC}"
                ;;
            "shut off")
                state_display="${OFF} ${RED}shut off${NC}"
                ;;
            paused)
                state_display="${WARN} ${YELLOW}paused${NC}"
                ;;
            "not defined")
                state_display="${ERR} ${RED}not defined${NC}"
                ;;
            *)
                state_display="${WARN} ${YELLOW}${state}${NC}"
                ;;
        esac
        
        printf "  %-15s %-25b %-18s %-28s\n" "${vm_name}" "${state_display}" "${actual_ip}" "${fqdn}"
    done
    
    # ─────────────────────────────────────────────────────────────────
    # Connectivity Check (only if VMs are running)
    # ─────────────────────────────────────────────────────────────────
    local any_running=false
    for vm_name in "${VM_NAMES[@]}"; do
        if [[ "$(get_vm_state "${vm_name}")" == "running" ]]; then
            any_running=true
            break
        fi
    done
    
    if [[ "${any_running}" == "true" ]]; then
        print_header "Connectivity"
        
        echo ""
        printf "  ${BOLD}%-15s %-18s %-12s %-12s${NC}\n" "VM Name" "IP Address" "Ping" "SSH (22)"
        printf "  %-15s %-18s %-12s %-12s\n" "───────────────" "──────────────────" "────────────" "────────────"
        
        for vm_name in "${VM_NAMES[@]}"; do
            local state
            state=$(get_vm_state "${vm_name}")
            
            if [[ "${state}" == "running" ]]; then
                local ip
                ip=$(get_vm_ip "${vm_name}")
                
                local ping_status
                ping_status=$(check_vm_ping "${ip}")
                
                local ssh_status
                ssh_status=$(check_vm_ssh "${ip}")
                
                # Format ping status
                local ping_display
                case "${ping_status}" in
                    reachable)
                        ping_display="${OK} ${GREEN}OK${NC}"
                        ;;
                    unreachable)
                        ping_display="${ERR} ${RED}FAIL${NC}"
                        ;;
                    *)
                        ping_display="${WARN} ${YELLOW}?${NC}"
                        ;;
                esac
                
                # Format SSH status
                local ssh_display
                case "${ssh_status}" in
                    open)
                        ssh_display="${OK} ${GREEN}Open${NC}"
                        ;;
                    closed)
                        ssh_display="${ERR} ${RED}Closed${NC}"
                        ;;
                    *)
                        ssh_display="${WARN} ${YELLOW}?${NC}"
                        ;;
                esac
                
                printf "  %-15s %-18s %-20b %-20b\n" "${vm_name}" "${ip}" "${ping_display}" "${ssh_display}"
            fi
        done
    fi
    
    # ─────────────────────────────────────────────────────────────────
    # Host Configuration
    # ─────────────────────────────────────────────────────────────────
    print_header "Host Configuration"
    
    echo ""
    
    # Check /etc/hosts
    if grep -q "# BEGIN Fedora Lab VMs" /etc/hosts 2>/dev/null; then
        echo -e "  /etc/hosts entries:  ${OK} ${GREEN}Configured${NC}"
    else
        echo -e "  /etc/hosts entries:  ${WARN} ${YELLOW}Not configured${NC}"
        echo -e "                       Run: ${CYAN}sudo ./manage-hosts.sh add${NC}"
    fi
    
    # Check hosts.local file
    if [[ -f "${SCRIPT_DIR}/hosts.local" ]]; then
        echo -e "  hosts.local file:    ${OK} ${GREEN}Present${NC}"
    else
        echo -e "  hosts.local file:    ${ERR} ${RED}Missing${NC}"
    fi
    
    # ─────────────────────────────────────────────────────────────────
    # Quick Commands
    # ─────────────────────────────────────────────────────────────────
    print_header "Quick Commands"
    
    echo ""
    echo "  Start all VMs:        sudo ./start-lab-vms.sh"
    echo "  Stop all VMs:         sudo virsh shutdown FedoraLab1 && sudo virsh shutdown FedoraLab2"
    echo "  Connect to VM:        sudo virt-viewer FedoraLab1"
    echo "  SSH to VM:            ssh ansibleuser@fedoralab1.example.com"
    echo "  Reset Lab:            sudo ./reset-lab.sh"
    echo "  Lab Status:           sudo ./lab-status.sh"
    echo ""
}

# Main
main() {
    check_virsh
    show_status
}

main "$@"

