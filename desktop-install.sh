#!/bin/bash
#
# Gentoo Desktop Environment Installation Script
# Installs Hyprland, Wayland, and Catppuccin theming
#
# Run this AFTER booting into the base Gentoo system installed by gentoo-install.sh
#
# Usage:
#   doas ./desktop-install.sh
#

set -e
set -o pipefail

#==============================================================================
# SCRIPT DIRECTORY (for external config files)
#==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIGS_DIR="${SCRIPT_DIR}/configs"

#==============================================================================
# LOGGING
#==============================================================================

LOG_DIR="/var/log/gentoo-install"
LOG_TIMESTAMP="$(date '+%Y-%m-%d_%H-%M')"
LOG_FILE="${LOG_DIR}/desktop-install_${LOG_TIMESTAMP}.log"

init_logging() {
    mkdir -p "$LOG_DIR"
    cat > "$LOG_FILE" << EOF
================================================================================
GENTOO DESKTOP INSTALLATION LOG
================================================================================
Started: $(date '+%Y-%m-%d %H:%M:%S')
================================================================================

EOF
}

log_to_file() {
    echo "[$(date '+%H:%M:%S')] $1" >> "$LOG_FILE"
}

#==============================================================================
# CONFIGURATION
#==============================================================================

# Get the current user (the one who invoked doas/sudo)
if [[ -n "$SUDO_USER" ]]; then
    USERNAME="$SUDO_USER"
elif [[ -n "$DOAS_USER" ]]; then
    USERNAME="$DOAS_USER"
else
    USERNAME=$(whoami)
fi

# Hyprland and Wayland packages
# Note: pipewire, wireplumber, bluez already installed by gentoo-install.sh
HYPRLAND_PACKAGES="
    gui-wm/hyprland
    x11-base/xwayland
    gui-apps/waybar
    gui-apps/mako
    gui-apps/grim
    gui-apps/slurp
    gui-apps/wl-clipboard
    x11-terms/kitty
    x11-misc/wofi
    media-video/playerctl
    gui-libs/xdg-desktop-portal-hyprland
    gui-libs/xdg-desktop-portal-wlr
    sys-apps/xdg-desktop-portal-gtk
    x11-misc/xdg-utils
    app-misc/brightnessctl
    gui-apps/hyprlock
    gui-apps/hypridle
    media-fonts/fontawesome
"

#==============================================================================
# COLORS (Catppuccin Mocha)
#==============================================================================

RED='\033[38;2;243;139;168m'
GREEN='\033[38;2;166;227;161m'
YELLOW='\033[38;2;249;226;175m'
BLUE='\033[38;2;137;180;250m'
CYAN='\033[38;2;148;226;213m'
MAUVE='\033[38;2;203;166;247m'
TEXT='\033[38;2;205;214;244m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
    log_to_file "[INFO] $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
    log_to_file "[SUCCESS] $1"
}

log_warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
    log_to_file "[WARNING] $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    log_to_file "[ERROR] $1"
    exit 1
}

log_step() {
    echo -e "\n${CYAN}========================================${NC}"
    echo -e "${CYAN} $1${NC}"
    echo -e "${CYAN}========================================${NC}\n"
    log_to_file "=== $1 ==="
}

#==============================================================================
# PRE-FLIGHT CHECKS
#==============================================================================

preflight_checks() {
    log_step "Pre-flight Checks"

    # Check if running as root
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root (use doas or sudo)"
    fi

    # Check if we're in the real system (not chroot)
    if [[ -f /mnt/gentoo/etc/gentoo-release ]]; then
        log_error "You appear to be in the live environment. Boot into your installed system first."
    fi

    # Check if configs directory exists
    if [[ ! -d "$CONFIGS_DIR" ]]; then
        log_error "Configs directory not found: $CONFIGS_DIR"
    fi

    # Check username
    if [[ -z "$USERNAME" ]] || [[ "$USERNAME" == "root" ]]; then
        log_error "Could not determine non-root username. Run with: doas ./desktop-install.sh"
    fi

    if ! id "$USERNAME" &>/dev/null; then
        log_error "User '$USERNAME' does not exist"
    fi

    log_info "Installing desktop environment for user: $USERNAME"
    log_success "Pre-flight checks passed"
}

#==============================================================================
# CONFIGURE PORTAGE FOR WAYLAND
#==============================================================================

configure_portage() {
    log_step "Configuring Portage for Wayland"

    # Add graphics and Wayland USE flags (deferred from base install for reliability)
    log_info "Adding graphics and Wayland USE flags..."

    # Graphics flags: vulkan, nvenc, vaapi for NVIDIA hardware acceleration
    # These were deferred from gentoo-install.sh to avoid circular deps during bootstrap
    local graphics_flags="wayland vulkan nvenc vaapi X"

    for flag in $graphics_flags; do
        if ! grep -q "$flag" /etc/portage/make.conf; then
            if grep -qE '^USE\s*=' /etc/portage/make.conf; then
                sed -i -E "s/^(USE\s*=\s*\")/\1${flag} /" /etc/portage/make.conf
            fi
        fi
    done

    # Remove -X flag if present (XWayland needs X support)
    if grep -q -- '-X' /etc/portage/make.conf; then
        log_info "Removing -X USE flag (XWayland needs X support)..."
        sed -i 's/-X /X /g; s/-X"/X"/g' /etc/portage/make.conf
    fi

    # Temporary circular dependency workarounds for desktop packages
    # These are removed after the initial update
    log_info "Adding temporary circular dependency workarounds..."
    cat > /etc/portage/package.use/zzz-desktop-circular-deps << 'EOF'
# TEMPORARY: Break circular dependencies for desktop install
# This file is removed after @world update

# openimageio/opencolorio cycle (common in graphics stacks)
media-libs/openimageio -color-management

# If qt6 pulls in circular deps with multimedia
dev-qt/qtmultimedia -qml
EOF

    # Hyprland keywords (often needs ~amd64)
    log_info "Adding Hyprland package keywords..."
    cat > /etc/portage/package.accept_keywords/hyprland << 'EOF'
gui-wm/hyprland ~amd64
gui-libs/hyprutils ~amd64
gui-libs/hyprcursor ~amd64
gui-libs/hyprwayland-scanner ~amd64
dev-libs/hyprlang ~amd64
gui-libs/aquamarine ~amd64
gui-apps/hyprlock ~amd64
gui-apps/hypridle ~amd64
gui-apps/hyprpaper ~amd64
gui-libs/xdg-desktop-portal-hyprland ~amd64
EOF

    # Update world with new USE flags
    log_info "Updating system with new USE flags (this may take a while)..."
    emerge --update --deep --newuse @world --quiet-build || log_warn "World update had issues, continuing..."

    # Remove temporary workarounds and rebuild affected packages
    log_info "Removing temporary circular dependency workarounds..."
    rm -f /etc/portage/package.use/zzz-desktop-circular-deps

    log_info "Rebuilding packages with full USE flags..."
    emerge --oneshot --usepkg=n --changed-use \
        media-libs/openimageio \
        2>/dev/null || true

    log_success "Portage configured for Wayland"
}

#==============================================================================
# INSTALL SESSION MANAGEMENT
#==============================================================================

install_session() {
    log_step "Installing Session Management"

    # Install elogind for session management (OpenRC)
    log_info "Installing elogind..."
    emerge --quiet-build sys-auth/elogind sys-auth/polkit

    # Enable elogind
    rc-update add elogind boot 2>/dev/null || true

    # Install dbus if not present
    if ! rc-service dbus status &>/dev/null; then
        log_info "Installing and enabling dbus..."
        emerge --quiet-build sys-apps/dbus
        rc-update add dbus default 2>/dev/null || true
    fi

    log_success "Session management installed"
}

#==============================================================================
# INSTALL HYPRLAND AND WAYLAND
#==============================================================================

install_hyprland() {
    log_step "Installing Hyprland and Wayland"

    log_info "This will take a while..."
    emerge --quiet-build ${HYPRLAND_PACKAGES}

    log_success "Hyprland and Wayland installed"
}

#==============================================================================
# INSTALL JETBRAINSMONO NERD FONT
#==============================================================================

install_fonts() {
    log_step "Installing JetBrainsMono Nerd Font"

    local font_dir="/usr/share/fonts/nerd-fonts"
    mkdir -p "${font_dir}"

    log_info "Downloading JetBrainsMono Nerd Font..."
    local font_url="https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.tar.xz"
    curl -sL "${font_url}" | tar -xJ -C "${font_dir}"

    # Update font cache
    fc-cache -fv

    log_success "JetBrainsMono Nerd Font installed"
}

#==============================================================================
# INSTALL CONFIGURATION FILES
#==============================================================================

install_configs() {
    log_step "Installing Configuration Files"

    local config_dir="/home/${USERNAME}/.config"
    mkdir -p "${config_dir}"
    mkdir -p "/home/${USERNAME}/Pictures/Screenshots"

    # Helper function to copy config with error handling
    copy_config() {
        local src="$1"
        local dst="$2"
        if [[ -f "$src" ]]; then
            cp "$src" "$dst"
        else
            log_warn "Config file not found: $src"
        fi
    }

    # Hyprland
    log_info "Installing Hyprland configs..."
    mkdir -p "${config_dir}/hypr"
    copy_config "${CONFIGS_DIR}/hypr/hyprland.conf" "${config_dir}/hypr/hyprland.conf"
    copy_config "${CONFIGS_DIR}/hypr/mocha.conf" "${config_dir}/hypr/mocha.conf"
    copy_config "${CONFIGS_DIR}/hypr/hyprlock.conf" "${config_dir}/hypr/hyprlock.conf"
    copy_config "${CONFIGS_DIR}/hypr/hypridle.conf" "${config_dir}/hypr/hypridle.conf"

    # Kitty
    log_info "Installing Kitty configs..."
    mkdir -p "${config_dir}/kitty"
    copy_config "${CONFIGS_DIR}/kitty/kitty.conf" "${config_dir}/kitty/kitty.conf"
    copy_config "${CONFIGS_DIR}/kitty/mocha.conf" "${config_dir}/kitty/mocha.conf"

    # Waybar
    log_info "Installing Waybar configs..."
    mkdir -p "${config_dir}/waybar"
    copy_config "${CONFIGS_DIR}/waybar/config" "${config_dir}/waybar/config"
    copy_config "${CONFIGS_DIR}/waybar/style.css" "${config_dir}/waybar/style.css"
    copy_config "${CONFIGS_DIR}/waybar/mocha.css" "${config_dir}/waybar/mocha.css"

    # Wofi
    log_info "Installing Wofi configs..."
    mkdir -p "${config_dir}/wofi"
    copy_config "${CONFIGS_DIR}/wofi/config" "${config_dir}/wofi/config"
    copy_config "${CONFIGS_DIR}/wofi/style.css" "${config_dir}/wofi/style.css"

    # Mako
    log_info "Installing Mako config..."
    mkdir -p "${config_dir}/mako"
    copy_config "${CONFIGS_DIR}/mako/config" "${config_dir}/mako/config"

    # Note: Neovim and btop configs already installed by gentoo-install.sh

    # Set ownership
    chown -R "${USERNAME}:${USERNAME}" "${config_dir}"
    chown -R "${USERNAME}:${USERNAME}" "/home/${USERNAME}/Pictures"

    log_success "Configuration files installed"
}

#==============================================================================
# CONFIGURE AUTO-START
#==============================================================================
# Note: GRUB theme installed by gentoo-install.sh

configure_autostart() {
    log_step "Configuring Hyprland Auto-Start"

    # Create .bash_profile to start Hyprland on TTY1 login
    cat > "/home/${USERNAME}/.bash_profile" << 'EOF'
# Start Hyprland on TTY1 login
if [ -z "$DISPLAY" ] && [ "$XDG_VTNR" = 1 ]; then
    exec Hyprland
fi
EOF

    chown "${USERNAME}:${USERNAME}" "/home/${USERNAME}/.bash_profile"

    log_success "Hyprland will start automatically on TTY1 login"
}

#==============================================================================
# MAIN
#==============================================================================

main() {
    # Initialize logging first
    init_logging

    clear
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║       Gentoo Desktop Environment Installation Script         ║"
    echo "║                                                              ║"
    echo "║  Installs: Hyprland + Wayland + Catppuccin Mocha theming    ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo ""
    echo "This script will install:"
    echo "  - Hyprland (Wayland compositor)"
    echo "  - Kitty (terminal)"
    echo "  - Waybar (status bar)"
    echo "  - Wofi (application launcher)"
    echo "  - Mako (notifications)"
    echo "  - JetBrainsMono Nerd Font"
    echo "  - Catppuccin Mocha theming for all apps"
    echo ""
    echo "Note: Neovim, btop, GRUB theme, pipewire, bluez"
    echo "      already installed by gentoo-install.sh"
    echo ""
    echo -e "${BLUE}Log file: ${LOG_FILE}${NC}"
    echo ""

    read -p "Press Enter to continue or Ctrl+C to abort..."

    preflight_checks
    configure_portage
    install_session
    install_hyprland
    install_fonts
    install_configs
    configure_autostart

    echo ""
    echo -e "${GREEN}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║           Desktop Installation Complete!                     ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo ""
    echo "To start Hyprland:"
    echo "  1. Log out or switch to TTY1 (Ctrl+Alt+F1)"
    echo "  2. Log in as ${USERNAME}"
    echo "  3. Hyprland will start automatically"
    echo ""
    echo "Or start manually with: Hyprland"
    echo ""
    echo "Keybindings:"
    echo "  Super+Q     Open terminal (Kitty)"
    echo "  Super+R     Open launcher (Wofi)"
    echo "  Super+C     Close window"
    echo "  Super+L     Lock screen"
    echo "  Super+M     Exit Hyprland"
    echo "  Super+1-9   Switch workspace"
    echo ""
    echo -e "${BLUE}Installation log saved to: ${LOG_FILE}${NC}"
    echo ""

    log_to_file "=== Installation completed successfully ==="
}

main "$@"
