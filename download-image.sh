#!/bin/bash
#
# download-image.sh
# Downloads the Fedora43Lab.qcow2 base image from Google Drive if not present
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE_NAME="Fedora43Lab.qcow2"
IMAGE_PATH="${SCRIPT_DIR}/${IMAGE_NAME}"

# Google Drive file ID extracted from the share link
# https://drive.google.com/file/d/1aMNna4AhHaRvQoEEK5XL8rGINnSEgTIN/view?usp=drive_link
GDRIVE_FILE_ID="1aMNna4AhHaRvQoEEK5XL8rGINnSEgTIN"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
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

# Check if gdown is installed, install if needed
check_gdown() {
    if ! command -v gdown &> /dev/null; then
        warn "gdown is not installed. Installing..."
        if command -v pip3 &> /dev/null; then
            pip3 install --user gdown
            # Add to PATH if needed
            export PATH="$HOME/.local/bin:$PATH"
        elif command -v pip &> /dev/null; then
            pip install --user gdown
            export PATH="$HOME/.local/bin:$PATH"
        else
            error "pip is not installed. Install Python pip first:\n  sudo dnf install python3-pip"
        fi
        
        # Verify installation
        if ! command -v gdown &> /dev/null; then
            error "Failed to install gdown. Try manually:\n  pip3 install gdown"
        fi
        info "gdown installed successfully"
    fi
}

# Download using gdown (handles Google Drive large file confirmations)
download_with_gdown() {
    info "Downloading ${IMAGE_NAME} from Google Drive..."
    info "File ID: ${GDRIVE_FILE_ID}"
    echo ""
    
    cd "${SCRIPT_DIR}"
    gdown "${GDRIVE_FILE_ID}" -O "${IMAGE_NAME}"
    
    if [[ -f "${IMAGE_PATH}" ]]; then
        local size
        size=$(du -h "${IMAGE_PATH}" | cut -f1)
        info "Download complete: ${IMAGE_PATH} (${size})"
    else
        error "Download failed. File not found."
    fi
}

# Alternative download using curl (may not work for large files)
download_with_curl() {
    info "Attempting download with curl..."
    warn "Note: Large files may require confirmation. Consider installing gdown."
    
    local confirm_url="https://drive.google.com/uc?export=download&id=${GDRIVE_FILE_ID}"
    
    cd "${SCRIPT_DIR}"
    
    # First attempt - may get confirmation page for large files
    curl -L -o "${IMAGE_NAME}" \
        "https://drive.google.com/uc?export=download&confirm=yes&id=${GDRIVE_FILE_ID}"
    
    if [[ -f "${IMAGE_PATH}" ]]; then
        local size
        size=$(du -h "${IMAGE_PATH}" | cut -f1)
        # Check if we got the actual file or just an HTML page
        if file "${IMAGE_PATH}" | grep -q "QEMU QCOW"; then
            info "Download complete: ${IMAGE_PATH} (${size})"
        else
            rm -f "${IMAGE_PATH}"
            error "Downloaded file is not a valid QCOW2 image.\nPlease install gdown: pip3 install gdown"
        fi
    else
        error "Download failed."
    fi
}

# Main
main() {
    echo ""
    echo "════════════════════════════════════════════════════════════"
    echo "  Fedora Lab Image Downloader"
    echo "════════════════════════════════════════════════════════════"
    echo ""
    
    # Check if image already exists
    if [[ -f "${IMAGE_PATH}" ]]; then
        local size
        size=$(du -h "${IMAGE_PATH}" | cut -f1)
        info "${IMAGE_NAME} already exists (${size})"
        echo ""
        echo "Location: ${IMAGE_PATH}"
        echo ""
        
        read -p "Re-download the image? (y/N): " response
        if [[ ! "${response}" =~ ^[Yy]$ ]]; then
            info "Keeping existing image."
            exit 0
        fi
        rm -f "${IMAGE_PATH}"
    fi
    
    # Download the image
    info "Image not found. Downloading..."
    echo ""
    echo "Source: Google Drive"
    echo "File:   ${IMAGE_NAME}"
    echo ""
    
    # Prefer gdown for reliable large file downloads
    if command -v gdown &> /dev/null; then
        download_with_gdown
    else
        echo -e "${YELLOW}gdown not found.${NC}"
        echo ""
        echo "Options:"
        echo "  1) Install gdown (recommended for large files)"
        echo "  2) Try curl (may fail for large files)"
        echo "  3) Cancel"
        echo ""
        read -p "Choose [1/2/3]: " choice
        
        case "${choice}" in
            1)
                check_gdown
                download_with_gdown
                ;;
            2)
                download_with_curl
                ;;
            *)
                echo "Cancelled."
                exit 0
                ;;
        esac
    fi
    
    echo ""
    echo "════════════════════════════════════════════════════════════"
    echo "  Download Complete!"
    echo "════════════════════════════════════════════════════════════"
    echo ""
    echo "You can now create the lab environment:"
    echo "  sudo ./create-lab-vms.sh"
    echo ""
}

main "$@"

