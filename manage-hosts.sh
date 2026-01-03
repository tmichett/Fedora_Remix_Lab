#!/bin/bash
#
# manage-hosts.sh
# Adds or removes Fedora Lab VM entries from /etc/hosts
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOSTS_FILE="/etc/hosts"
HOSTS_LOCAL="${SCRIPT_DIR}/hosts.local"

# Marker comments to identify managed section
MARKER_START="# BEGIN Fedora Lab VMs"
MARKER_END="# END Fedora Lab VMs"

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

# Check if running as root
check_privileges() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run with sudo or as root"
    fi
}

# Check if entries already exist
entries_exist() {
    grep -q "${MARKER_START}" "${HOSTS_FILE}" 2>/dev/null
}

# Add entries to /etc/hosts
add_entries() {
    if [[ ! -f "${HOSTS_LOCAL}" ]]; then
        error "hosts.local not found: ${HOSTS_LOCAL}\nRun create-lab-vms.sh first!"
    fi
    
    if entries_exist; then
        warn "Fedora Lab entries already exist in ${HOSTS_FILE}"
        echo "Use '$0 remove' to remove them first, or '$0 update' to update them."
        return 1
    fi
    
    info "Adding Fedora Lab entries to ${HOSTS_FILE}..."
    
    # Create backup
    cp "${HOSTS_FILE}" "${HOSTS_FILE}.bak.$(date +%Y%m%d%H%M%S)"
    info "Backup created: ${HOSTS_FILE}.bak.*"
    
    # Append entries with markers
    {
        echo ""
        echo "${MARKER_START}"
        # Extract just the IP entries (skip comments)
        grep -E "^[0-9]" "${HOSTS_LOCAL}"
        echo "${MARKER_END}"
    } >> "${HOSTS_FILE}"
    
    info "Entries added successfully!"
    echo ""
    echo "Added entries:"
    grep -E "^[0-9]" "${HOSTS_LOCAL}" | sed 's/^/  /'
}

# Remove entries from /etc/hosts
remove_entries() {
    if ! entries_exist; then
        warn "No Fedora Lab entries found in ${HOSTS_FILE}"
        return 0
    fi
    
    info "Removing Fedora Lab entries from ${HOSTS_FILE}..."
    
    # Create backup
    cp "${HOSTS_FILE}" "${HOSTS_FILE}.bak.$(date +%Y%m%d%H%M%S)"
    info "Backup created: ${HOSTS_FILE}.bak.*"
    
    # Remove the marked section (including blank line before marker)
    sed -i "/^${MARKER_START}$/,/^${MARKER_END}$/d" "${HOSTS_FILE}"
    
    # Clean up any trailing blank lines
    sed -i -e :a -e '/^\n*$/{$d;N;ba' -e '}' "${HOSTS_FILE}"
    
    info "Entries removed successfully!"
}

# Update entries (remove then add)
update_entries() {
    info "Updating Fedora Lab entries..."
    
    if entries_exist; then
        # Silently remove without extra messages
        cp "${HOSTS_FILE}" "${HOSTS_FILE}.bak.$(date +%Y%m%d%H%M%S)"
        sed -i "/^${MARKER_START}$/,/^${MARKER_END}$/d" "${HOSTS_FILE}"
    fi
    
    if [[ ! -f "${HOSTS_LOCAL}" ]]; then
        error "hosts.local not found: ${HOSTS_LOCAL}\nRun create-lab-vms.sh first!"
    fi
    
    # Append entries with markers
    {
        echo ""
        echo "${MARKER_START}"
        grep -E "^[0-9]" "${HOSTS_LOCAL}"
        echo "${MARKER_END}"
    } >> "${HOSTS_FILE}"
    
    info "Entries updated successfully!"
    echo ""
    echo "Current entries:"
    grep -E "^[0-9]" "${HOSTS_LOCAL}" | sed 's/^/  /'
}

# Show current status
show_status() {
    echo "Status of Fedora Lab entries in ${HOSTS_FILE}:"
    echo ""
    
    if entries_exist; then
        echo -e "${GREEN}[PRESENT]${NC} Entries are configured"
        echo ""
        echo "Current entries:"
        sed -n "/^${MARKER_START}$/,/^${MARKER_END}$/p" "${HOSTS_FILE}" | grep -E "^[0-9]" | sed 's/^/  /'
    else
        echo -e "${YELLOW}[MISSING]${NC} No entries found"
        if [[ -f "${HOSTS_LOCAL}" ]]; then
            echo ""
            echo "Available entries in hosts.local:"
            grep -E "^[0-9]" "${HOSTS_LOCAL}" | sed 's/^/  /'
            echo ""
            echo "Run '$0 add' to add them."
        fi
    fi
}

# Show usage
usage() {
    cat << EOF
Usage: $0 <command>

Commands:
  add      Add Fedora Lab entries to /etc/hosts (if not present)
  remove   Remove Fedora Lab entries from /etc/hosts
  update   Update entries (remove and re-add with latest from hosts.local)
  status   Show current status of entries

Examples:
  sudo $0 add      # Add entries
  sudo $0 remove   # Remove entries
  sudo $0 update   # Update entries
  $0 status        # Check status (no sudo needed)

EOF
}

# Main
main() {
    local command="${1:-}"
    
    case "${command}" in
        add)
            check_privileges
            add_entries
            ;;
        remove)
            check_privileges
            remove_entries
            ;;
        update)
            check_privileges
            update_entries
            ;;
        status)
            show_status
            ;;
        -h|--help|help)
            usage
            ;;
        "")
            usage
            exit 1
            ;;
        *)
            error "Unknown command: ${command}\nRun '$0 --help' for usage."
            ;;
    esac
}

main "$@"

