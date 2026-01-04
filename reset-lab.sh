#!/bin/bash
#
# reset-lab.sh
# Resets the Fedora Lab environment by destroying and recreating VMs
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Configuration (must match create-lab-vms.sh)
LIBVIRT_IMAGES="/var/lib/libvirt/images"
VM_DIR="${LIBVIRT_IMAGES}/fedora-lab"
NETWORK_NAME="labnet"
VM_NAMES=("FedoraLab1" "FedoraLab2")

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

# Check if running as root
check_privileges() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run with sudo or as root"
    fi
}

# Stop all VMs
stop_vms() {
    info "Stopping VMs..."
    for vm_name in "${VM_NAMES[@]}"; do
        if virsh domstate "${vm_name}" 2>/dev/null | grep -q "running"; then
            info "  Stopping ${vm_name}..."
            virsh destroy "${vm_name}" 2>/dev/null || true
        fi
    done
}

# Undefine all VMs
undefine_vms() {
    info "Undefining VMs..."
    for vm_name in "${VM_NAMES[@]}"; do
        if virsh dominfo "${vm_name}" &>/dev/null; then
            info "  Undefining ${vm_name}..."
            virsh undefine "${vm_name}" --nvram 2>/dev/null || \
            virsh undefine "${vm_name}" 2>/dev/null || true
        fi
    done
}

# Remove network
remove_network() {
    info "Removing network..."
    if virsh net-info "${NETWORK_NAME}" &>/dev/null; then
        if virsh net-info "${NETWORK_NAME}" 2>/dev/null | grep -q "Active:.*yes"; then
            info "  Stopping ${NETWORK_NAME}..."
            virsh net-destroy "${NETWORK_NAME}" 2>/dev/null || true
        fi
        info "  Undefining ${NETWORK_NAME}..."
        virsh net-undefine "${NETWORK_NAME}" 2>/dev/null || true
    fi
}

# Remove VM files
remove_files() {
    info "Removing VM files..."
    if [[ -d "${VM_DIR}" ]]; then
        rm -rf "${VM_DIR}"
        info "  Removed: ${VM_DIR}"
    fi
}

# Show usage
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Reset the Fedora Lab environment by destroying and recreating VMs.

Options:
  --vms-only      Reset only the VMs, keep the network
  --full          Full reset including network (default)
  --destroy-only  Only destroy, don't recreate
  --keep-base     Keep the base image in libvirt storage
  -y, --yes       Skip confirmation prompt
  -h, --help      Show this help message

Examples:
  sudo $0              # Full reset with confirmation
  sudo $0 -y           # Full reset without confirmation
  sudo $0 --vms-only   # Reset VMs but keep network
  sudo $0 --destroy-only  # Just destroy, don't recreate

EOF
}

# Main
main() {
    local reset_network=true
    local recreate=true
    local skip_confirm=false
    local keep_base=false
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --vms-only)
                reset_network=false
                shift
                ;;
            --full)
                reset_network=true
                shift
                ;;
            --destroy-only)
                recreate=false
                shift
                ;;
            --keep-base)
                keep_base=true
                shift
                ;;
            -y|--yes)
                skip_confirm=true
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                error "Unknown option: $1\nRun '$0 --help' for usage."
                ;;
        esac
    done
    
    check_privileges
    
    echo ""
    echo -e "${BOLD}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}║              Fedora Lab Reset                             ║${NC}"
    echo -e "${BOLD}╚═══════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    # Show what will be done
    echo -e "${YELLOW}This will:${NC}"
    echo "  • Stop and undefine all lab VMs (FedoraLab1, FedoraLab2)"
    echo "  • Delete VM overlay disk images"
    if [[ "${reset_network}" == "true" ]]; then
        echo "  • Remove the lab network (${NETWORK_NAME})"
    fi
    if [[ "${recreate}" == "true" ]]; then
        echo "  • Recreate the entire lab environment"
    fi
    if [[ "${keep_base}" == "false" ]] && [[ "${reset_network}" == "true" ]]; then
        echo ""
        echo -e "  ${CYAN}Note: Base image at ${LIBVIRT_IMAGES}/Fedora43Lab.qcow2 will be preserved${NC}"
    fi
    echo ""
    
    # Confirmation
    if [[ "${skip_confirm}" != "true" ]]; then
        echo -e "${RED}WARNING: All VM data will be lost!${NC}"
        read -p "Are you sure you want to continue? (y/N): " response
        if [[ ! "${response}" =~ ^[Yy]$ ]]; then
            echo "Aborted."
            exit 0
        fi
        echo ""
    fi
    
    # Perform reset
    echo "────────────────────────────────────────────────────────────"
    echo "Destroying Lab Environment"
    echo "────────────────────────────────────────────────────────────"
    
    stop_vms
    undefine_vms
    
    if [[ "${reset_network}" == "true" ]]; then
        remove_network
    fi
    
    remove_files
    
    echo ""
    info "Lab environment destroyed successfully!"
    
    # Recreate if requested
    if [[ "${recreate}" == "true" ]]; then
        echo ""
        echo "────────────────────────────────────────────────────────────"
        echo "Recreating Lab Environment"
        echo "────────────────────────────────────────────────────────────"
        echo ""
        
        # Run create script
        "${SCRIPT_DIR}/create-lab-vms.sh"
        
        echo ""
        echo "────────────────────────────────────────────────────────────"
        echo "Starting VMs"
        echo "────────────────────────────────────────────────────────────"
        echo ""
        
        # Run start script
        "${SCRIPT_DIR}/start-lab-vms.sh"
        
        echo ""
        echo -e "${GREEN}${BOLD}Lab reset complete!${NC}"
        echo ""
        echo "VMs are ready. Connect with:"
        echo "  sudo virt-viewer FedoraLab1"
        echo "  ssh ansibleuser@fedoralab1.example.com"
    else
        echo ""
        echo "To recreate the lab, run:"
        echo "  sudo ./create-lab-vms.sh"
        echo "  sudo ./start-lab-vms.sh"
    fi
    echo ""
}

main "$@"


