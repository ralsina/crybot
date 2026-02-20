#!/usr/bin/env bash
set -euo pipefail

# Crybot Update Script
# Updates Crybot to the latest version

# Configuration
REPO="ralsina/crybot"
BINARY_NAME="crybot"
INSTALL_DIR="${HOME}/.local/bin"
CONFIG_DIR="${HOME}/.crybot"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info() { echo -e "${BLUE}ℹ${NC} $*"; }
success() { echo -e "${GREEN}✓${NC} $*"; }
warn() { echo -e "${YELLOW}⚠${NC} $*"; }
error() { echo -e "${RED}✗${NC} $*"; }

# Detect system architecture
detect_arch() {
    local arch=$(uname -m)
    case $arch in
        x86_64|amd64) echo "amd64" ;;
        aarch64|arm64) echo "arm64" ;;
        armv7l|armhf) echo "armv7" ;;
        *)
            error "Unsupported architecture: $arch"
            exit 1
            ;;
    esac
}

# Detect OS
detect_os() {
    case "$(uname -s)" in
        Linux*) echo "linux" ;;
        Darwin*) echo "darwin" ;;
        *)
            error "Unsupported OS: $(uname -s)"
            exit 1
            ;;
    esac
}

# Get latest release version
get_latest_version() {
    info "Checking for updates..."
    if command -v curl &> /dev/null; then
        curl -s "https://api.github.com/repos/${REPO}/releases/latest" | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/'
    elif command -v wget &> /dev/null; then
        wget -qO- "https://api.github.com/repos/${REPO}/releases/latest" | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/'
    else
        error "Neither curl nor wget found"
        exit 1
    fi
}

# Get current version
get_current_version() {
    if [[ -f "${INSTALL_DIR}/${BINARY_NAME}" ]]; then
        "${INSTALL_DIR}/${BINARY_NAME}" --version 2>/dev/null || echo "unknown"
    else
        echo "not installed"
    fi
}

# Download and install binary
update_binary() {
    local version="$1"
    local os="$2"
    local arch="$3"
    local download_url="https://github.com/${REPO}/releases/latest/download/${BINARY_NAME}-${os}-${arch}"

    info "Downloading Crybot ${version}..."

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
    fi

    chmod +x "${temp_file}"
    mv "${temp_file}" "${INSTALL_DIR}/${BINARY_NAME}"
    success "Binary updated to ${version}"
}

# Restart service if running
restart_service() {
    if systemctl --user is-active --quiet crybot.service 2>/dev/null; then
        info "Restarting Crybot service..."
        systemctl --user restart crybot.service
        success "Service restarted"
    fi
}

# Main flow
main() {
    echo -e "${BLUE}"
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║           Crybot Update Script                            ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo -e "${NC}"

    local VERSION=""
    local RESTART_SERVICE=false

    while [[ $# -gt 0 ]]; do
        case $1 in
            --version)
                VERSION="$2"
                shift 2
                ;;
            --restart-service)
                RESTART_SERVICE=true
                shift
                ;;
            --help|-h)
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  --version VERSION  Update to specific version (default: latest)"
                echo "  --restart-service Restart systemd service after update"
                echo "  --help, -h         Show this help message"
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                exit 1
                ;;
        esac
    done

    # Check if installed
    if [[ ! -f "${INSTALL_DIR}/${BINARY_NAME}" ]]; then
        error "Crybot is not installed at ${INSTALL_DIR}/${BINARY_NAME}"
        info "Run the install script first:"
        echo "  curl -sSL https://raw.githubusercontent.com/${REPO}/main/install.sh | bash"
        exit 1
    fi

    # Get versions
    local CURRENT=$(get_current_version)
    local OS=$(detect_os)
    local ARCH=$(detect_arch)

    if [[ -z "${VERSION}" ]]; then
        VERSION=$(get_latest_version)
        if [[ -z "${VERSION}" ]]; then
            error "Failed to fetch latest version"
            exit 1
        fi
    fi

    info "Current version: ${CURRENT}"
    info "Latest version:  ${VERSION}"

    if [[ "${CURRENT}" == "${VERSION}" ]]; then
        success "Already up to date!"
        exit 0
    fi

    echo ""
    warn "This will update Crybot from ${CURRENT} to ${VERSION}"
    read -p "Continue? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        info "Update cancelled"
        exit 0
    fi

    echo ""

    # Update binary
    update_binary "${VERSION}" "${OS}" "${ARCH}"

    # Restart service if requested
    if [[ "${RESTART_SERVICE}" == true ]]; then
        restart_service
    fi

    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════╗"
    echo "║              Update Complete! ✓                              ║"
    echo "╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""
    success "Crybot has been updated to ${VERSION}"
    echo ""
}

main "$@"
