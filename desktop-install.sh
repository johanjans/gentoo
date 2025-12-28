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

# State file for checkpoint/resume functionality
STATE_FILE="${LOG_DIR}/desktop-install.state"
CURRENT_STEP=""

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
# CHECKPOINT/RESUME SYSTEM
#==============================================================================

# Installation steps in order
INSTALL_STEPS=(
    "preflight_checks"
    "configure_portage"
    "install_session"
    "install_hyprland"
    "install_fonts"
    "install_configs"
    "configure_autostart"
)

# Human-readable step descriptions
declare -A STEP_DESCRIPTIONS=(
    ["preflight_checks"]="Pre-flight checks (user, configs)"
    ["configure_portage"]="Configure Portage for Wayland/graphics"
    ["install_session"]="Install session/login packages"
    ["install_hyprland"]="Install Hyprland and Wayland packages"
    ["install_fonts"]="Install fonts (JetBrainsMono Nerd Font)"
    ["install_configs"]="Install configuration files"
    ["configure_autostart"]="Configure Hyprland auto-start"
)

# Save completed step to state file
checkpoint_save() {
    local step="$1"
    mkdir -p "$LOG_DIR"
    echo "$step" >> "$STATE_FILE"
    log_to_file "[CHECKPOINT] Saved: $step"
}

# Check if step is already completed
checkpoint_completed() {
    local step="$1"
    [[ -f "$STATE_FILE" ]] && grep -qx "$step" "$STATE_FILE"
}

# Get last completed step
checkpoint_get_last() {
    if [[ -f "$STATE_FILE" ]]; then
        tail -1 "$STATE_FILE"
    fi
}

# Clear all checkpoints
checkpoint_clear() {
    rm -f "$STATE_FILE"
    log_to_file "[CHECKPOINT] Cleared all checkpoints"
}

# Get step index
get_step_index() {
    local step="$1"
    for i in "${!INSTALL_STEPS[@]}"; do
        if [[ "${INSTALL_STEPS[$i]}" == "$step" ]]; then
            echo "$i"
            return 0
        fi
    done
    echo "-1"
}

# List all steps with status
list_steps() {
    echo ""
    echo "Desktop Installation Steps:"
    echo "============================"
    local last_completed=$(checkpoint_get_last)
    local last_index=-1
    if [[ -n "$last_completed" ]]; then
        last_index=$(get_step_index "$last_completed")
    fi

    for i in "${!INSTALL_STEPS[@]}"; do
        local step="${INSTALL_STEPS[$i]}"
        local desc="${STEP_DESCRIPTIONS[$step]}"
        local status=""

        if checkpoint_completed "$step"; then
            status="${GREEN}[DONE]${NC}"
        elif [[ $i -eq $((last_index + 1)) ]]; then
            status="${YELLOW}[NEXT]${NC}"
        else
            status="[    ]"
        fi

        printf "  %d. %-20s %b %s\n" "$((i+1))" "$step" "$status" "$desc"
    done
    echo ""
}

# Show failure message with resume instructions
show_failure_message() {
    local failed_step="$1"
    local exit_code="$2"
    local error_output="$3"

    echo ""
    echo -e "${RED}╔══════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║                     DESKTOP INSTALLATION FAILED                              ║${NC}"
    echo -e "${RED}╚══════════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${RED}Failed Step:${NC}  $failed_step"
    echo -e "${RED}Description:${NC}  ${STEP_DESCRIPTIONS[$failed_step]}"
    echo -e "${RED}Exit Code:${NC}    $exit_code"
    echo ""

    if [[ -n "$error_output" ]]; then
        echo -e "${RED}Last Output:${NC}"
        echo "─────────────────────────────────────────────────────────────────────"
        echo "$error_output" | tail -20
        echo "─────────────────────────────────────────────────────────────────────"
        echo ""
    fi

    echo -e "${YELLOW}Log File:${NC}     $LOG_FILE"
    echo ""
    echo -e "${CYAN}To investigate:${NC}"
    echo "  1. Check the log file:  less $LOG_FILE"
    echo "  2. Check emerge logs:   less /var/tmp/portage/*/*/temp/build.log"
    echo ""
    echo -e "${CYAN}To resume after fixing the issue:${NC}"
    echo ""
    echo "  # Resume from the failed step:"
    echo -e "  ${GREEN}doas ./desktop-install.sh --resume${NC}"
    echo ""
    echo "  # Or restart from a specific step:"
    echo -e "  ${GREEN}doas ./desktop-install.sh --start-from=$failed_step${NC}"
    echo ""
    echo "  # List all steps and their status:"
    echo -e "  ${GREEN}./desktop-install.sh --list-steps${NC}"
    echo ""
    echo "  # Start fresh (clear all checkpoints):"
    echo -e "  ${GREEN}doas ./desktop-install.sh --fresh${NC}"
    echo ""

    log_to_file "=== INSTALLATION FAILED at $failed_step ==="
}

# Error trap handler
handle_error() {
    local exit_code=$?
    local line_number=$1

    local error_output=""
    if [[ -f "$LOG_FILE" ]]; then
        error_output=$(tail -30 "$LOG_FILE" 2>/dev/null || true)
    fi

    show_failure_message "$CURRENT_STEP" "$exit_code" "$error_output"
    exit $exit_code
}

# Run a step with checkpoint tracking
run_step() {
    local step="$1"
    CURRENT_STEP="$step"

    "$step"

    checkpoint_save "$step"
}

# Show usage
show_usage() {
    echo ""
    echo "Gentoo Desktop Installation Script - Checkpoint/Resume System"
    echo ""
    echo "Usage: doas $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --resume              Resume from last completed checkpoint"
    echo "  --start-from=STEP    Start from specific step (skips previous steps)"
    echo "  --list-steps         List all steps and their completion status"
    echo "  --fresh              Clear checkpoints and start fresh"
    echo "  --help               Show this help message"
    echo ""
    echo "Examples:"
    echo "  doas $0                    Start new installation"
    echo "  doas $0 --resume           Resume from where it left off"
    echo "  doas $0 --start-from=install_hyprland"
    echo "  $0 --list-steps"
    echo ""
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
    local resume_mode=false
    local start_from=""
    local fresh_install=false

    # Parse command-line arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --help|-h)
                show_usage
                exit 0
                ;;
            --list-steps)
                list_steps
                exit 0
                ;;
            --resume)
                resume_mode=true
                shift
                ;;
            --start-from=*)
                start_from="${1#*=}"
                shift
                ;;
            --fresh)
                fresh_install=true
                shift
                ;;
            *)
                echo "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done

    # Initialize logging
    init_logging

    # Handle fresh install request
    if [[ "$fresh_install" == true ]]; then
        checkpoint_clear
        echo -e "${YELLOW}Cleared all checkpoints. Starting fresh installation.${NC}"
    fi

    # Set up error trap
    trap 'handle_error $LINENO' ERR

    # Determine starting point
    local start_index=0
    local last_completed=$(checkpoint_get_last)

    if [[ -n "$start_from" ]]; then
        start_index=$(get_step_index "$start_from")
        if [[ "$start_index" == "-1" ]]; then
            echo -e "${RED}Error: Unknown step '$start_from'${NC}"
            echo "Valid steps:"
            for step in "${INSTALL_STEPS[@]}"; do
                echo "  - $step"
            done
            exit 1
        fi
        echo -e "${CYAN}Starting from step: $start_from${NC}"
    elif [[ "$resume_mode" == true ]] || [[ -n "$last_completed" ]]; then
        if [[ -n "$last_completed" ]]; then
            local last_index=$(get_step_index "$last_completed")
            start_index=$((last_index + 1))

            if [[ $start_index -ge ${#INSTALL_STEPS[@]} ]]; then
                echo -e "${GREEN}All steps already completed!${NC}"
                echo "Use --fresh to start a new installation."
                exit 0
            fi

            echo -e "${CYAN}Resuming from: ${INSTALL_STEPS[$start_index]}${NC}"
            echo -e "${CYAN}Last completed: $last_completed${NC}"
            echo ""

            list_steps

            read -p "Press Enter to resume or Ctrl+C to abort..."
        fi
    fi

    # Show banner for fresh installs
    if [[ $start_index -eq 0 ]]; then
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
        echo -e "${YELLOW}Checkpoint system enabled:${NC} If installation fails, you can resume"
        echo "                           with: doas ./desktop-install.sh --resume"
        echo ""
        echo -e "${BLUE}Log file: ${LOG_FILE}${NC}"
        echo ""

        read -p "Press Enter to continue or Ctrl+C to abort..."
    fi

    # Run installation steps from start_index
    for ((i=start_index; i<${#INSTALL_STEPS[@]}; i++)); do
        local step="${INSTALL_STEPS[$i]}"
        local step_num=$((i + 1))
        local total_steps=${#INSTALL_STEPS[@]}

        echo ""
        echo -e "${MAUVE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${MAUVE}  Step $step_num/$total_steps: ${STEP_DESCRIPTIONS[$step]}${NC}"
        echo -e "${MAUVE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

        run_step "$step"
    done

    # Clear error trap
    trap - ERR

    # Installation complete - clear checkpoints
    checkpoint_clear

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
