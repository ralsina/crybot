#!/usr/bin/env bash
set -euo pipefail

# Crybot Installer Script
# Downloads and installs Crybot for the current system

# Configuration
REPO="ralsina/crybot"
BINARY_NAME="crybot"
CRYSH_NAME="crysh"
INSTALL_DIR="${HOME}/.local/bin"
CONFIG_DIR="${HOME}/.crybot"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default options
SKIP_ONBOARDING=false
SERVICE_TYPE=""
RESTART_SERVICE=false

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
    local binary_name="$4"
    local download_url="https://github.com/${REPO}/releases/latest/download/${binary_name}-${os}-${arch}"

    info "Downloading ${binary_name} ${version} for ${os}-${arch}..."
    info "From: ${download_url}"

    local temp_file=$(mktemp)

    if command -v curl &> /dev/null; then
        if ! curl -L -o "${temp_file}" "${download_url}"; then
            error "Failed to download ${binary_name}"
            rm -f "${temp_file}"
            return 1
        fi
    elif command -v wget &> /dev/null; then
        if ! wget -O "${temp_file}" "${download_url}"; then
            error "Failed to download ${binary_name}"
            rm -f "${temp_file}"
            return 1
        fi
    else
        error "Neither curl nor wget found. Please install one of them."
        return 1
    fi

    # Make executable
    chmod +x "${temp_file}"
    mv "${temp_file}" "${INSTALL_DIR}/${binary_name}"
    success "Binary installed to ${INSTALL_DIR}/${binary_name}"
    return 0
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

# Run onboarding wizard
run_onboarding() {
    if [[ "${SKIP_ONBOARDING}" == "true" ]]; then
        info "Skipping onboarding (configure manually later)"
        return
    fi

    info "Running onboarding wizard..."
    if "${INSTALL_DIR}/${BINARY_NAME}" onboard; then
        success "Onboarding complete"
    else
        warn "Onboarding failed or was cancelled"
        info "You can run onboard later with: ${BINARY_NAME} onboard"
    fi
}

# Create systemd service
create_systemd_service() {
    local service_type="$1"  # "user" or "auto"

    info "Creating systemd ${service_type} service..."

    local systemd_dir="${HOME}/.config/systemd/user"
    local service_file="${systemd_dir}/crybot.service"

    # Ensure directory exists
    mkdir -p "${systemd_dir}"

    # Get crybot path
    local crybot_path="${INSTALL_DIR}/${BINARY_NAME}"

    # Create service file
    cat > "${service_file}" << EOF
[Unit]
Description=Crybot AI Assistant
After=network.target

[Service]
Type=simple
ExecStart=${crybot_path} start
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
EOF

    success "Service file created: ${service_file}"

    # Reload systemd
    info "Reloading systemd daemon..."
    systemctl --user daemon-reload

    # Enable service
    info "Enabling crybot service..."
    systemctl --user enable crybot.service

    # Enable lingering for auto service
    if [[ "${service_type}" == "auto" ]]; then
        info "Enabling 24/7 operation (lingering)..."
        loginctl enable-linger "$USER"
        success "Service will run 24/7, even when logged out"
    else
        success "Service will start automatically when you log in"
    fi

    # Ask if user wants to start now
    echo ""
    read -p "Would you like to start the service now? [Y/n] " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]] || [[ -z $REPLY ]]; then
        info "Starting crybot service..."
        systemctl --user start crybot.service
        success "Service started!"
        echo ""
        info "Service management commands:"
        echo "  systemctl --user status crybot.service   # Check status"
        echo "  systemctl --user stop crybot.service    # Stop service"
        echo "  systemctl --user restart crybot.service # Restart service"
        echo "  journalctl --user -u crybot.service -f  # View logs"
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
            --skip-onboarding)
                SKIP_ONBOARDING=true
                shift
                ;;
            --service)
                SERVICE_TYPE="$2"
                if [[ "${SERVICE_TYPE}" != "user" ]] && [[ "${SERVICE_TYPE}" != "auto" ]]; then
                    error "Invalid service type: ${SERVICE_TYPE}"
                    error "Must be 'user' or 'auto'"
                    exit 1
                fi
                shift 2
                ;;
            --help|-h)
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  --version VERSION        Install specific version (default: latest)"
                echo "  --skip-onboarding        Skip the onboarding wizard"
                echo "  --service TYPE           Create systemd service (TYPE: user|auto)"
                echo "                           'user' - starts when you log in"
                echo "                           'auto' - runs 24/7 even when logged out"
                echo "  --help, -h               Show this help message"
                echo ""
                echo "Examples:"
                echo "  $0                                    # Install latest with onboarding"
                echo "  $0 --version v0.7.0                   # Install specific version"
                echo "  $0 --skip-onboarding                  # Skip configuration wizard"
                echo "  $0 --service user                     # Install with login auto-start"
                echo "  $0 --service auto                     # Install with 24/7 operation"
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

    # Download crybot binary
    if ! download_binary "${VERSION}" "${OS}" "${ARCH}" "${BINARY_NAME}"; then
        error "Failed to download crybot binary"
        exit 1
    fi

    # Download crysh binary if available (for newer versions)
    info "Downloading crysh (shell wrapper)..."
    if ! download_binary "${VERSION}" "${OS}" "${ARCH}" "${CRYSH_NAME}"; then
        warn "crysh not available for this version (requires v0.7.0+)"
    fi

    # Create systemd service if requested
    if [[ -n "${SERVICE_TYPE}" ]]; then
        create_systemd_service "${SERVICE_TYPE}"
    fi

    # Run onboarding unless skipped
    run_onboarding

    # Success message
    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════╗"
    echo "║              Installation Complete! ✓                        ║"
    echo "╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""
    success "Crybot has been installed to: ${INSTALL_DIR}/${BINARY_NAME}"
    if [[ -f "${INSTALL_DIR}/${CRYSH_NAME}" ]]; then
        success "Crysh has been installed to: ${INSTALL_DIR}/${CRYSH_NAME}"
    fi
    echo ""

    if [[ "${SKIP_ONBOARDING}" == "true" ]]; then
        info "Next steps:"
        echo "  1. Make sure ${INSTALL_DIR} is in your PATH"
        echo "  2. Run onboarding to configure: ${BINARY_NAME} onboard"
    elif [[ -z "${SERVICE_TYPE}" ]]; then
        info "Next steps:"
        echo "  1. Make sure ${INSTALL_DIR} is in your PATH"
        echo "  2. Start crybot: ${BINARY_NAME} start"
        echo "     Or enable auto-start with: $0 --service user"
    fi

    echo ""
    info "For more information, see: https://github.com/${REPO}"
    echo ""
}

# Run main function
main "$@"
