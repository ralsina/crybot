#!/usr/bin/env bash
set -euo pipefail

# Crybot Installer Script
# Downloads and installs Crybot for the current system

# Configuration
REPO="ralsina/crybot"
BINARY_NAME="crybot"
INSTALL_DIR="${HOME}/.local/bin"
CONFIG_DIR="${HOME}/.crybot"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper functions
info() { echo -e "${BLUE}ℹ${NC} $*"; }
success() { echo -e "${GREEN}✓${NC} $*"; }
warn() { echo -e "${YELLOW}⚠${NC} $*"; }
error() { echo -e "${RED}✗${NC} $*"; }

# Detect system architecture
detect_arch() {
    local arch=$(uname -m)
    case $arch in
        x86_64|amd64)
            echo "amd64"
            ;;
        aarch64|arm64)
            echo "arm64"
            ;;
        armv7l|armhf)
            echo "armv7"
            ;;
        *)
            error "Unsupported architecture: $arch"
            exit 1
            ;;
    esac
}

# Detect OS
detect_os() {
    case "$(uname -s)" in
        Linux*)
            echo "linux"
            ;;
        Darwin*)
            echo "darwin"
            ;;
        *)
            error "Unsupported OS: $(uname -s)"
            exit 1
            ;;
    esac
}

# Get latest release version from GitHub
get_latest_version() {
    info "Fetching latest release version..."
    if command -v curl &> /dev/null; then
        curl -s "https://api.github.com/repos/${REPO}/releases/latest" | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/'
    elif command -v wget &> /dev/null; then
        wget -qO- "https://api.github.com/repos/${REPO}/releases/latest" | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/'
    else
        error "Neither curl nor wget found. Please install one of them."
        exit 1
    fi
}

# Download binary from GitHub release
download_binary() {
    local version="$1"
    local os="$2"
    local arch="$3"
    local download_url="https://github.com/${REPO}/releases/latest/download/${BINARY_NAME}-${os}-${arch}"

    info "Downloading Crybot ${version} for ${os}-${arch}..."
    info "From: ${download_url}"

    local temp_file=$(mktemp)

    if command -v curl &> /dev/null; then
        if ! curl -L -o "${temp_file}" "${download_url}"; then
            error "Failed to download binary"
            rm -f "${temp_file}"
            exit 1
        fi
    elif command -v wget &> /dev/null; then
        if ! wget -O "${temp_file}" "${download_url}"; then
            error "Failed to download binary"
            rm -f "${temp_file}"
            exit 1
        fi
    else
        error "Neither curl nor wget found. Please install one of them."
        exit 1
    fi

    # Make executable
    chmod +x "${temp_file}"
    mv "${temp_file}" "${INSTALL_DIR}/${BINARY_NAME}"
    success "Binary installed to ${INSTALL_DIR}/${BINARY_NAME}"
}

# Check if install directory exists, create if not
ensure_install_dir() {
    if [[ ! -d "${INSTALL_DIR}" ]]; then
        info "Creating install directory: ${INSTALL_DIR}"
        mkdir -p "${INSTALL_DIR}"
    fi

    # Add to PATH if not already there
    if [[ ":$PATH:" != *":${INSTALL_DIR}:"* ]]; then
        warn "${INSTALL_DIR} is not in your PATH"
        info "Add this to your ~/.bashrc or ~/.zshrc:"
        echo "  export PATH=\"${INSTALL_DIR}:\$PATH\""
    fi
}





# Main installation flow
main() {
    echo -e "${BLUE}"
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║           Crybot Installation Script                     ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo -e "${NC}"

    # Parse arguments
    local VERSION=""

    while [[ $# -gt 0 ]]; do
        case $1 in
            --version)
                VERSION="$2"
                shift 2
                ;;
            --help|-h)
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  --version VERSION    Install specific version (default: latest)"
                echo "  --help, -h           Show this help message"
                echo ""
                echo "This script downloads and installs the Crybot binary."
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                echo "Run '$0 --help' for usage information"
                exit 1
                ;;
        esac
    done

    # Detect system
    local OS=$(detect_os)
    local ARCH=$(detect_arch)
    info "Detected system: ${OS}-${ARCH}"

    # Get version if not specified
    if [[ -z "${VERSION}" ]]; then
        VERSION=$(get_latest_version)
        if [[ -z "${VERSION}" ]]; then
            error "Failed to fetch latest version"
            exit 1
        fi
    fi

    success "Installing Crybot ${VERSION}"

    # Ensure install directory exists
    ensure_install_dir

    # Download binary
    download_binary "${VERSION}" "${OS}" "${ARCH}"

    # Success message
    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════╗"
    echo "║              Installation Complete! ✓                        ║"
    echo "╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""
    success "Crybot has been installed to: ${INSTALL_DIR}/${BINARY_NAME}"
    echo ""
    info "Next steps:"
    echo "  1. Make sure ${INSTALL_DIR} is in your PATH"
    echo "  2. Run onboarding to configure: ${BINARY_NAME} onboard"
    echo ""
    info "For more information, see: https://github.com/${REPO}"
    echo ""
}

# Run main function
main "$@"
