#!/bin/bash
#
# create-lab-vms.sh
# Creates two VMs (FedoraLab1 and FedoraLab2) using a shared QCOW2 backing image
# Generates libvirt XML files that can be imported into KVM/Virt Manager
# Creates a dedicated virtual network with static IPs
# Uses virt-customize to pre-configure user and locale settings
#

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_IMAGE_SRC="${SCRIPT_DIR}/Fedora43Lab.qcow2"
LIBVIRT_IMAGES="/var/lib/libvirt/images"
BASE_IMAGE="${LIBVIRT_IMAGES}/Fedora43Lab.qcow2"
VM_DIR="${LIBVIRT_IMAGES}/fedora-lab"

# Network Configuration
NETWORK_NAME="labnet"
NETWORK_BRIDGE="virbr-lab"
NETWORK_SUBNET="192.168.100"
NETWORK_NETMASK="255.255.255.0"
NETWORK_GATEWAY="${NETWORK_SUBNET}.1"
DOMAIN_NAME="example.com"

# VM Definitions (name, IP suffix, MAC suffix)
declare -A VM_CONFIG
VM_CONFIG["FedoraLab1"]="10:aa"   # IP: .10, MAC ends with :aa
VM_CONFIG["FedoraLab2"]="11:bb"   # IP: .11, MAC ends with :bb
VM_NAMES=("FedoraLab1" "FedoraLab2")

# VM Resources
MEMORY_MB=1024
VCPUS=2

# User configuration
VM_USER="ansibleuser"
VM_PASSWORD="Automation!"
VM_LOCALE="en_US.UTF-8"
VM_TIMEZONE="America/New_York"

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

# Check for required tools
check_dependencies() {
    local missing=()
    
    if ! command -v qemu-img &> /dev/null; then
        missing+=("qemu-img")
    fi
    
    if ! command -v virt-customize &> /dev/null; then
        missing+=("libguestfs-tools")
    fi
    
    if ! command -v virsh &> /dev/null; then
        missing+=("libvirt-client")
    fi
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        error "Missing required tools: ${missing[*]}\nInstall with: sudo dnf install ${missing[*]}"
    fi
    
    info "All dependencies satisfied"
}

# Get VM IP address from config
get_vm_ip() {
    local vm_name="$1"
    local config="${VM_CONFIG[$vm_name]}"
    local ip_suffix="${config%%:*}"
    echo "${NETWORK_SUBNET}.${ip_suffix}"
}

# Get VM MAC address from config
get_vm_mac() {
    local vm_name="$1"
    local config="${VM_CONFIG[$vm_name]}"
    local mac_suffix="${config##*:}"
    echo "52:54:00:1a:b0:${mac_suffix}"
}

# Get VM FQDN
get_vm_fqdn() {
    local vm_name="$1"
    echo "${vm_name,,}.${DOMAIN_NAME}"
}

# Create the lab network
create_network() {
    info "Checking lab network: ${NETWORK_NAME}..."
    
    # Check if network already exists
    if virsh net-info "${NETWORK_NAME}" &>/dev/null; then
        warn "Network ${NETWORK_NAME} already exists"
        read -p "Recreate network? This will destroy and recreate it (y/N): " response
        if [[ "${response}" =~ ^[Yy]$ ]]; then
            info "Removing existing network..."
            virsh net-destroy "${NETWORK_NAME}" 2>/dev/null || true
            virsh net-undefine "${NETWORK_NAME}" 2>/dev/null || true
        else
            info "Keeping existing network"
            return
        fi
    fi
    
    info "Creating lab network: ${NETWORK_NAME}..."
    
    # Build DHCP host entries for static IPs
    local dhcp_hosts=""
    for vm_name in "${VM_NAMES[@]}"; do
        local mac
        mac=$(get_vm_mac "${vm_name}")
        local ip
        ip=$(get_vm_ip "${vm_name}")
        local fqdn
        fqdn=$(get_vm_fqdn "${vm_name}")
        dhcp_hosts+="      <host mac='${mac}' name='${fqdn}' ip='${ip}'/>\n"
    done
    
    # Create network XML
    local network_xml="${VM_DIR}/${NETWORK_NAME}.xml"
    cat > "${network_xml}" << EOF
<network>
  <name>${NETWORK_NAME}</name>
  <forward mode='nat'>
    <nat>
      <port start='1024' end='65535'/>
    </nat>
  </forward>
  <bridge name='${NETWORK_BRIDGE}' stp='on' delay='0'/>
  <domain name='${DOMAIN_NAME}' localOnly='yes'/>
  <dns>
    <host ip='${NETWORK_SUBNET}.10'>
      <hostname>fedoralab1</hostname>
      <hostname>fedoralab1.${DOMAIN_NAME}</hostname>
    </host>
    <host ip='${NETWORK_SUBNET}.11'>
      <hostname>fedoralab2</hostname>
      <hostname>fedoralab2.${DOMAIN_NAME}</hostname>
    </host>
  </dns>
  <ip address='${NETWORK_GATEWAY}' netmask='${NETWORK_NETMASK}'>
    <dhcp>
      <range start='${NETWORK_SUBNET}.100' end='${NETWORK_SUBNET}.200'/>
$(echo -e "${dhcp_hosts}")
    </dhcp>
  </ip>
</network>
EOF

    # Define and start the network
    virsh net-define "${network_xml}"
    virsh net-start "${NETWORK_NAME}"
    virsh net-autostart "${NETWORK_NAME}"
    
    info "Network ${NETWORK_NAME} created and started"
    info "  Subnet: ${NETWORK_SUBNET}.0/24"
    info "  Gateway: ${NETWORK_GATEWAY}"
}

# Check if base image exists and copy to libvirt directory
check_base_image() {
    if [[ ! -f "${BASE_IMAGE_SRC}" ]]; then
        error "Source base image not found: ${BASE_IMAGE_SRC}"
    fi
    
    # Create libvirt images directory if needed
    mkdir -p "${LIBVIRT_IMAGES}"
    
    # Copy base image to libvirt directory if not already there
    if [[ ! -f "${BASE_IMAGE}" ]]; then
        info "Copying base image to libvirt images directory..."
        cp "${BASE_IMAGE_SRC}" "${BASE_IMAGE}"
        chown qemu:qemu "${BASE_IMAGE}"
        chmod 644 "${BASE_IMAGE}"
        info "Base image copied to: ${BASE_IMAGE}"
    else
        info "Base image already exists: ${BASE_IMAGE}"
    fi
}

# Create and customize overlay image for a VM
create_overlay_image() {
    local vm_name="$1"
    local overlay_path="${VM_DIR}/${vm_name}.qcow2"
    
    if [[ -f "${overlay_path}" ]]; then
        warn "Overlay image already exists: ${overlay_path}"
        read -p "Overwrite? (y/N): " response
        if [[ ! "${response}" =~ ^[Yy]$ ]]; then
            info "Skipping overlay creation for ${vm_name}"
            return
        fi
        rm -f "${overlay_path}"
    fi
    
    info "Creating overlay image for ${vm_name}..."
    qemu-img create -f qcow2 -b "${BASE_IMAGE}" -F qcow2 "${overlay_path}"
    info "Created: ${overlay_path}"
}

# Generate /etc/hosts content for VMs
generate_hosts_content() {
    local hosts_content="127.0.0.1   localhost localhost.localdomain\n"
    hosts_content+="::1         localhost localhost.localdomain\n\n"
    hosts_content+="# Lab VMs\n"
    
    for vm_name in "${VM_NAMES[@]}"; do
        local ip
        ip=$(get_vm_ip "${vm_name}")
        local fqdn
        fqdn=$(get_vm_fqdn "${vm_name}")
        local short_name="${vm_name,,}"
        hosts_content+="${ip}   ${fqdn} ${short_name}\n"
    done
    
    echo -e "${hosts_content}"
}

# Customize the VM image with user and locale settings
customize_image() {
    local vm_name="$1"
    local overlay_path="${VM_DIR}/${vm_name}.qcow2"
    local vm_ip
    vm_ip=$(get_vm_ip "${vm_name}")
    local vm_fqdn
    vm_fqdn=$(get_vm_fqdn "${vm_name}")
    local vm_hostname="${vm_name,,}"
    
    info "Customizing ${vm_name} with virt-customize..."
    info "  - Creating user: ${VM_USER}"
    info "  - Setting locale: ${VM_LOCALE}"
    info "  - Setting timezone: ${VM_TIMEZONE}"
    info "  - Setting hostname: ${vm_fqdn}"
    info "  - Static IP: ${vm_ip}"
    
    # Generate hosts file content
    local hosts_content
    hosts_content=$(generate_hosts_content)
    
    # Create a temporary directory with hosts file
    local temp_dir
    temp_dir=$(mktemp -d)
    echo -e "${hosts_content}" > "${temp_dir}/hosts"
    
    # Use virt-customize to configure the image
    virt-customize -a "${overlay_path}" \
        --hostname "${vm_fqdn}" \
        --timezone "${VM_TIMEZONE}" \
        --write "/etc/locale.conf:LANG=${VM_LOCALE}" \
        --write "/etc/vconsole.conf:KEYMAP=us" \
        --run-command "useradd -m -G wheel -s /bin/bash ${VM_USER} 2>/dev/null || true" \
        --password "${VM_USER}:password:${VM_PASSWORD}" \
        --run-command "echo '${VM_USER} ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/${VM_USER}" \
        --run-command "chmod 440 /etc/sudoers.d/${VM_USER}" \
        --run-command "chown root:root /etc/sudoers.d/${VM_USER}" \
        --copy-in "${temp_dir}/hosts:/etc/" \
        --run-command "chmod 644 /etc/hosts" \
        --run-command "rm -f /etc/systemd/system/multi-user.target.wants/initial-setup.service" \
        --run-command "rm -f /etc/systemd/system/graphical.target.wants/initial-setup.service" \
        --run-command "rm -f /usr/lib/systemd/system/initial-setup.service" \
        --run-command "rm -f /usr/lib/systemd/system/initial-setup-text.service" \
        --run-command "mkdir -p /etc/sysconfig && touch /etc/sysconfig/initial-setup-reconfiguration-complete" \
        --run-command "mkdir -p /var/lib/initial-setup && touch /var/lib/initial-setup/state" \
        --selinux-relabel
    
    rm -rf "${temp_dir}"
    
    chown qemu:qemu "${overlay_path}"
    chmod 644 "${overlay_path}"
    
    info "Customization complete for ${vm_name}"
}

# Generate libvirt XML for a VM
generate_xml() {
    local vm_name="$1"
    local xml_path="${VM_DIR}/${vm_name}.xml"
    local disk_path="${VM_DIR}/${vm_name}.qcow2"
    local mac_address
    mac_address=$(get_vm_mac "${vm_name}")
    
    # Generate a unique UUID for each VM
    local uuid
    uuid=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || uuidgen 2>/dev/null || echo "$(date +%s)-${vm_name}" | md5sum | sed 's/^\(..\)\(..\)\(..\)\(..\)\(..\)\(..\)\(..\)\(..\)\(..\)\(..\)\(..\)\(..\)\(..\)\(..\)\(..\)\(..\).*/\1\2\3\4-\5\6-\7\8-\9\10-\11\12\13\14\15\16/')
    
    info "Generating XML for ${vm_name}..."
    info "  - MAC: ${mac_address}"
    info "  - Network: ${NETWORK_NAME}"
    
    cat > "${xml_path}" << EOF
<domain type='kvm'>
  <name>${vm_name}</name>
  <uuid>${uuid}</uuid>
  <metadata>
    <libosinfo:libosinfo xmlns:libosinfo="http://libosinfo.org/xmlns/libvirt/domain/1.0">
      <libosinfo:os id="http://fedoraproject.org/fedora/43"/>
    </libosinfo:libosinfo>
  </metadata>
  <memory unit='MiB'>${MEMORY_MB}</memory>
  <currentMemory unit='MiB'>${MEMORY_MB}</currentMemory>
  <vcpu placement='static'>${VCPUS}</vcpu>
  <os firmware='efi'>
    <type arch='x86_64' machine='q35'>hvm</type>
    <boot dev='hd'/>
  </os>
  <features>
    <acpi/>
    <apic/>
    <vmport state='off'/>
  </features>
  <cpu mode='host-passthrough' check='none' migratable='on'/>
  <clock offset='utc'>
    <timer name='rtc' tickpolicy='catchup'/>
    <timer name='pit' tickpolicy='delay'/>
    <timer name='hpet' present='no'/>
  </clock>
  <on_poweroff>destroy</on_poweroff>
  <on_reboot>restart</on_reboot>
  <on_crash>destroy</on_crash>
  <pm>
    <suspend-to-mem enabled='no'/>
    <suspend-to-disk enabled='no'/>
  </pm>
  <devices>
    <emulator>/usr/bin/qemu-system-x86_64</emulator>
    <disk type='file' device='disk'>
      <driver name='qemu' type='qcow2' discard='unmap'/>
      <source file='${disk_path}'/>
      <target dev='vda' bus='virtio'/>
      <address type='pci' domain='0x0000' bus='0x04' slot='0x00' function='0x0'/>
    </disk>
    <controller type='usb' index='0' model='qemu-xhci' ports='15'>
      <address type='pci' domain='0x0000' bus='0x02' slot='0x00' function='0x0'/>
    </controller>
    <controller type='pci' index='0' model='pcie-root'/>
    <controller type='pci' index='1' model='pcie-root-port'>
      <model name='pcie-root-port'/>
      <target chassis='1' port='0x10'/>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x02' function='0x0' multifunction='on'/>
    </controller>
    <controller type='pci' index='2' model='pcie-root-port'>
      <model name='pcie-root-port'/>
      <target chassis='2' port='0x11'/>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x02' function='0x1'/>
    </controller>
    <controller type='pci' index='3' model='pcie-root-port'>
      <model name='pcie-root-port'/>
      <target chassis='3' port='0x12'/>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x02' function='0x2'/>
    </controller>
    <controller type='pci' index='4' model='pcie-root-port'>
      <model name='pcie-root-port'/>
      <target chassis='4' port='0x13'/>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x02' function='0x3'/>
    </controller>
    <controller type='pci' index='5' model='pcie-root-port'>
      <model name='pcie-root-port'/>
      <target chassis='5' port='0x14'/>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x02' function='0x4'/>
    </controller>
    <controller type='pci' index='6' model='pcie-root-port'>
      <model name='pcie-root-port'/>
      <target chassis='6' port='0x15'/>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x02' function='0x5'/>
    </controller>
    <controller type='sata' index='0'>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x1f' function='0x2'/>
    </controller>
    <controller type='virtio-serial' index='0'>
      <address type='pci' domain='0x0000' bus='0x03' slot='0x00' function='0x0'/>
    </controller>
    <interface type='network'>
      <mac address='${mac_address}'/>
      <source network='${NETWORK_NAME}'/>
      <model type='virtio'/>
      <address type='pci' domain='0x0000' bus='0x01' slot='0x00' function='0x0'/>
    </interface>
    <serial type='pty'>
      <target type='isa-serial' port='0'>
        <model name='isa-serial'/>
      </target>
    </serial>
    <console type='pty'>
      <target type='serial' port='0'/>
    </console>
    <channel type='unix'>
      <target type='virtio' name='org.qemu.guest_agent.0'/>
      <address type='virtio-serial' controller='0' bus='0' port='1'/>
    </channel>
    <channel type='spicevmc'>
      <target type='virtio' name='com.redhat.spice.0'/>
      <address type='virtio-serial' controller='0' bus='0' port='2'/>
    </channel>
    <input type='tablet' bus='usb'>
      <address type='usb' bus='0' port='1'/>
    </input>
    <input type='mouse' bus='ps2'/>
    <input type='keyboard' bus='ps2'/>
    <tpm model='tpm-crb'>
      <backend type='emulator' version='2.0'/>
    </tpm>
    <graphics type='spice' autoport='yes'>
      <listen type='address'/>
      <image compression='auto_glz'/>
      <gl enable='no'/>
    </graphics>
    <sound model='ich9'>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x1b' function='0x0'/>
    </sound>
    <audio id='1' type='spice'/>
    <video>
      <model type='qxl' ram='65536' vram='65536' vgamem='16384' heads='1' primary='yes'/>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x01' function='0x0'/>
    </video>
    <redirdev bus='usb' type='spicevmc'>
      <address type='usb' bus='0' port='2'/>
    </redirdev>
    <redirdev bus='usb' type='spicevmc'>
      <address type='usb' bus='0' port='3'/>
    </redirdev>
    <watchdog model='itco' action='reset'/>
    <memballoon model='virtio'>
      <address type='pci' domain='0x0000' bus='0x05' slot='0x00' function='0x0'/>
    </memballoon>
    <rng model='virtio'>
      <backend model='random'>/dev/urandom</backend>
      <address type='pci' domain='0x0000' bus='0x06' slot='0x00' function='0x0'/>
    </rng>
  </devices>
</domain>
EOF

    info "Created: ${xml_path}"
}

# Generate hosts file for the host machine
generate_host_hosts_file() {
    local hosts_file="${SCRIPT_DIR}/hosts.local"
    
    info "Generating hosts file for host machine: ${hosts_file}"
    
    cat > "${hosts_file}" << EOF
# Fedora Lab VMs - Add these entries to /etc/hosts on the host machine
# Generated by create-lab-vms.sh on $(date)
#
# To add to your system:
#   sudo cat ${hosts_file} >> /etc/hosts
# Or manually add the following lines:

EOF

    for vm_name in "${VM_NAMES[@]}"; do
        local ip
        ip=$(get_vm_ip "${vm_name}")
        local fqdn
        fqdn=$(get_vm_fqdn "${vm_name}")
        local short_name="${vm_name,,}"
        echo "${ip}   ${fqdn} ${short_name}" >> "${hosts_file}"
    done
    
    info "Created: ${hosts_file}"
}

# Main execution
main() {
    echo "========================================"
    echo "  Fedora Lab VM Creator"
    echo "========================================"
    echo ""
    
    check_privileges
    check_dependencies
    check_base_image
    
    # Create VM directory if it doesn't exist
    mkdir -p "${VM_DIR}"
    info "VM directory: ${VM_DIR}"
    echo ""
    
    # Create the lab network
    echo "----------------------------------------"
    echo "Setting up Lab Network"
    echo "----------------------------------------"
    create_network
    echo ""
    
    # Create overlay images and XML files for each VM
    for vm_name in "${VM_NAMES[@]}"; do
        echo "----------------------------------------"
        echo "Setting up: ${vm_name}"
        echo "----------------------------------------"
        create_overlay_image "${vm_name}"
        customize_image "${vm_name}"
        generate_xml "${vm_name}"
        echo ""
    done
    
    # Generate hosts file for host machine
    echo "----------------------------------------"
    echo "Generating Host Files"
    echo "----------------------------------------"
    generate_host_hosts_file
    echo ""
    
    echo "========================================"
    echo "  Setup Complete!"
    echo "========================================"
    echo ""
    echo "Network: ${NETWORK_NAME}"
    echo "  Subnet: ${NETWORK_SUBNET}.0/24"
    echo "  Gateway: ${NETWORK_GATEWAY}"
    echo ""
    echo "VM Configuration:"
    echo "  - User: ${VM_USER}"
    echo "  - Password: ${VM_PASSWORD}"
    echo "  - Sudo: passwordless"
    echo ""
    echo "VM IP Addresses:"
    for vm_name in "${VM_NAMES[@]}"; do
        local ip
        ip=$(get_vm_ip "${vm_name}")
        local fqdn
        fqdn=$(get_vm_fqdn "${vm_name}")
        echo "  ${vm_name}: ${ip} (${fqdn})"
    done
    echo ""
    echo "To add hosts to your local /etc/hosts, run:"
    echo "  sudo bash -c 'cat ${SCRIPT_DIR}/hosts.local >> /etc/hosts'"
    echo ""
    echo "To start the VMs, run:"
    echo "  sudo ${SCRIPT_DIR}/start-lab-vms.sh"
    echo ""
}

main "$@"
