#!/usr/bin/env bash
set -euo pipefail

# Crybot Uninstaller Script
# Removes Crybot and optionally cleans up configuration

# Configuration
BINARY_NAME="crybot"
INSTALL_DIR="${HOME}/.local/bin"
CONFIG_DIR="${HOME}/.crybot"
SYSTEMD_USER_DIR="${HOME}/.config/systemd/user"

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

# Parse arguments
PURGE_CONFIG=false
STOP_SERVICE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --purge)
            PURGE_CONFIG=true
            shift
            ;;
        --stop-service)
            STOP_SERVICE=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --purge         Remove configuration directory (~/.crybot)"
            echo "  --stop-service  Stop and disable systemd service"
            echo "  --help, -h      Show this help message"
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            echo "Run '$0 --help' for usage information"
            exit 1
            ;;
    esac
done

echo -e "${BLUE}"
echo "╔══════════════════════════════════════════════════════════╗"
echo "║           Crybot Uninstaller                               ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# Stop and disable service if requested
if [[ "${STOP_SERVICE}" == true ]]; then
    info "Stopping Crybot service..."
    if systemctl --user is-active --quiet crybot.service 2>/dev/null; then
        systemctl --user stop crybot.service
        success "Service stopped"
    fi

    info "Disabling Crybot service..."
    if systemctl --user is-enabled --quiet crybot.service 2>/dev/null; then
        systemctl --user disable crybot.service
        success "Service disabled"
    fi
fi

# Remove systemd unit file
if [[ -f "${SYSTEMD_USER_DIR}/crybot.service" ]]; then
    info "Removing systemd unit..."
    rm -f "${SYSTEMD_USER_DIR}/crybot.service"
    systemctl --user daemon-reload 2>/dev/null || true
    success "Systemd unit removed"
else
    info "No systemd unit found"
fi

# Remove binary
if [[ -f "${INSTALL_DIR}/${BINARY_NAME}" ]]; then
    info "Removing binary..."
    rm -f "${INSTALL_DIR}/${BINARY_NAME}"
    success "Binary removed from ${INSTALL_DIR}/${BINARY_NAME}"
else
    warn "Binary not found at ${INSTALL_DIR}/${BINARY_NAME}"
fi

# Remove configuration if requested
if [[ "${PURGE_CONFIG}" == true ]]; then
    if [[ -d "${CONFIG_DIR}" ]]; then
        info "Removing configuration directory..."
        rm -rf "${CONFIG_DIR}"
        success "Configuration removed"
    else
        info "No configuration directory found"
    fi
else
    if [[ -d "${CONFIG_DIR}" ]]; then
        info "Configuration preserved at ${CONFIG_DIR}"
        info "To remove it, run: $0 --purge"
    fi
fi

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════╗"
echo "║              Uninstallation Complete! ✓                        ║"
echo "╚══════════════════════════════════════════════════════════╝${NC}"
echo ""
