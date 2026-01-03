#!/bin/bash
#
# start-lab-vms.sh
# Registers and starts the FedoraLab VMs in libvirt/KVM
#

set -e

# Configuration
LIBVIRT_IMAGES="/var/lib/libvirt/images"
VM_DIR="${LIBVIRT_IMAGES}/fedora-lab"
VM_NAMES=("FedoraLab1" "FedoraLab2")

# Network Configuration
NETWORK_NAME="labnet"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

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

# Check if running as root or with sudo
check_privileges() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run with sudo or as root"
    fi
}

# Check if libvirt is running
check_libvirt() {
    if ! systemctl is-active --quiet libvirtd; then
        warn "libvirtd is not running. Attempting to start..."
        systemctl start libvirtd
        if ! systemctl is-active --quiet libvirtd; then
            error "Failed to start libvirtd"
        fi
    fi
    info "libvirtd is running"
}

# Check if lab network is active
check_network() {
    if ! virsh net-info "${NETWORK_NAME}" &>/dev/null; then
        error "Lab network '${NETWORK_NAME}' not found. Run create-lab-vms.sh first!"
    fi
    
    if ! virsh net-info "${NETWORK_NAME}" 2>/dev/null | grep -q "Active:.*yes"; then
        info "Starting ${NETWORK_NAME} network..."
        virsh net-start "${NETWORK_NAME}" 2>/dev/null || true
    fi
    info "Lab network '${NETWORK_NAME}' is available"
}

# Register a VM if not already defined
register_vm() {
    local vm_name="$1"
    local xml_path="${VM_DIR}/${vm_name}.xml"
    
    if [[ ! -f "${xml_path}" ]]; then
        error "XML file not found: ${xml_path}\nRun create-lab-vms.sh first!"
    fi
    
    # Check if VM is already defined
    if virsh dominfo "${vm_name}" &>/dev/null; then
        info "${vm_name} is already registered"
    else
        info "Registering ${vm_name}..."
        virsh define "${xml_path}"
        info "${vm_name} registered successfully"
    fi
}

# Start a VM if not already running
start_vm() {
    local vm_name="$1"
    
    # Check current state
    local state
    state=$(virsh domstate "${vm_name}" 2>/dev/null || echo "undefined")
    
    case "${state}" in
        "running")
            info "${vm_name} is already running"
            ;;
        "paused")
            info "Resuming ${vm_name}..."
            virsh resume "${vm_name}"
            info "${vm_name} resumed"
            ;;
        "shut off"|"undefined")
            info "Starting ${vm_name}..."
            virsh start "${vm_name}"
            info "${vm_name} started"
            ;;
        *)
            warn "${vm_name} is in state: ${state}"
            ;;
    esac
}

# Show VM status
show_status() {
    echo ""
    echo "========================================"
    echo "  VM Status"
    echo "========================================"
    for vm_name in "${VM_NAMES[@]}"; do
        local state
        state=$(virsh domstate "${vm_name}" 2>/dev/null || echo "not defined")
        echo "  ${vm_name}: ${state}"
    done
    echo "========================================"
}

# Main execution
main() {
    echo "========================================"
    echo "  Fedora Lab VM Starter"
    echo "========================================"
    echo ""
    
    check_privileges
    check_libvirt
    check_network
    echo ""
    
    # Register and start each VM
    for vm_name in "${VM_NAMES[@]}"; do
        echo "----------------------------------------"
        echo "Processing: ${vm_name}"
        echo "----------------------------------------"
        register_vm "${vm_name}"
        start_vm "${vm_name}"
        echo ""
    done
    
    show_status
    echo ""
    echo "To connect to a VM, use:"
    echo "  virt-viewer FedoraLab1"
    echo "  virt-viewer FedoraLab2"
    echo ""
    echo "Or open Virt Manager to access the VMs."
    echo ""
}

main "$@"

