#!/bin/bash
#
# Gentoo Linux Automated Installation Script
# Based on the Gentoo AMD64 Handbook (December 2025)
#
# Configured for: HP ZBook Power 15.6 G9
# - UEFI boot with Btrfs
# - OpenRC init system
# - Hyprland (Wayland compositor)
# - Intel + NVIDIA RTX A2000 (proprietary driver)
#
# WARNING: This script will DESTROY all data on the target disk!
#
# Usage: Boot from Gentoo minimal installation media, then run:
#   chmod +x gentoo-install.sh
#   ./gentoo-install.sh
#

set -e  # Exit on error
set -o pipefail

#==============================================================================
# LOGGING SYSTEM
#==============================================================================

# Log file location (created on the live environment, copied to installed system)
LOG_DIR="/var/log/gentoo-install"
LOG_FILE="${LOG_DIR}/install-$(date +%Y%m%d-%H%M%S).log"
LOG_VERBOSE="${LOG_DIR}/install-verbose-$(date +%Y%m%d-%H%M%S).log"

# Initialize logging
init_logging() {
    mkdir -p "$LOG_DIR"

    # Create log files with headers
    cat > "$LOG_FILE" << EOF
================================================================================
GENTOO INSTALLATION LOG
================================================================================
Started: $(date '+%Y-%m-%d %H:%M:%S')
Script Version: 1.0.0
Host: $(hostname)
================================================================================

EOF

    cat > "$LOG_VERBOSE" << EOF
================================================================================
GENTOO INSTALLATION VERBOSE LOG
================================================================================
Started: $(date '+%Y-%m-%d %H:%M:%S')
Script Version: 1.0.0
================================================================================

EOF

    # Log system information
    log_section "SYSTEM INFORMATION"
    log_detail "Date/Time" "$(date '+%Y-%m-%d %H:%M:%S %Z')"
    log_detail "Kernel" "$(uname -r)"
    log_detail "Architecture" "$(uname -m)"
    log_detail "CPU Model" "$(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2 | xargs)"
    log_detail "CPU Cores" "$(nproc)"
    log_detail "Total Memory" "$(free -h | awk '/^Mem:/ {print $2}')"
    log_detail "Boot Mode" "$([ -d /sys/firmware/efi ] && echo 'UEFI' || echo 'BIOS')"

    # Log available disks
    log_subsection "Available Disks"
    lsblk -d -o NAME,SIZE,MODEL,TRAN >> "$LOG_FILE" 2>&1
    echo "" >> "$LOG_FILE"

    # Log network status
    log_subsection "Network Status"
    ip addr show | grep -E '^[0-9]+:|inet ' >> "$LOG_FILE" 2>&1
    echo "" >> "$LOG_FILE"

    # Log PCI devices (for hardware detection)
    log_subsection "PCI Devices (GPU/Network)"
    lspci | grep -iE 'vga|3d|network|ethernet|wifi' >> "$LOG_FILE" 2>&1 || true
    echo "" >> "$LOG_FILE"
}

# Log a section header
log_section() {
    local section="$1"
    local separator="$(printf '=%.0s' {1..78})"
    echo "" >> "$LOG_FILE"
    echo "$separator" >> "$LOG_FILE"
    echo "[$section]" >> "$LOG_FILE"
    echo "$separator" >> "$LOG_FILE"
    echo "" >> "$LOG_FILE"

    echo "" >> "$LOG_VERBOSE"
    echo "$separator" >> "$LOG_VERBOSE"
    echo "[$section] - $(date '+%H:%M:%S')" >> "$LOG_VERBOSE"
    echo "$separator" >> "$LOG_VERBOSE"
}

# Log a subsection
log_subsection() {
    local subsection="$1"
    echo "" >> "$LOG_FILE"
    echo "--- $subsection ---" >> "$LOG_FILE"
    echo "" >> "$LOG_VERBOSE"
    echo "--- $subsection --- $(date '+%H:%M:%S')" >> "$LOG_VERBOSE"
}

# Log a key-value detail
log_detail() {
    local key="$1"
    local value="$2"
    printf "  %-20s : %s\n" "$key" "$value" >> "$LOG_FILE"
    printf "  %-20s : %s\n" "$key" "$value" >> "$LOG_VERBOSE"
}

# Log a message
log_msg() {
    local level="$1"
    local msg="$2"
    local timestamp=$(date '+%H:%M:%S')
    echo "[$timestamp] [$level] $msg" >> "$LOG_FILE"
    echo "[$timestamp] [$level] $msg" >> "$LOG_VERBOSE"
}

# Log command execution with output capture
log_cmd() {
    local cmd="$1"
    local description="${2:-Executing command}"
    local timestamp=$(date '+%H:%M:%S')
    local start_time=$(date +%s)

    echo "" >> "$LOG_VERBOSE"
    echo "[$timestamp] COMMAND: $cmd" >> "$LOG_VERBOSE"
    echo "[$timestamp] DESC: $description" >> "$LOG_VERBOSE"
    echo "--- OUTPUT START ---" >> "$LOG_VERBOSE"

    # Execute and capture output
    local output
    local exit_code
    if output=$(eval "$cmd" 2>&1); then
        exit_code=0
    else
        exit_code=$?
    fi

    echo "$output" >> "$LOG_VERBOSE"
    echo "--- OUTPUT END ---" >> "$LOG_VERBOSE"

    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    echo "[$timestamp] EXIT CODE: $exit_code (duration: ${duration}s)" >> "$LOG_VERBOSE"

    # Log to main file (abbreviated)
    if [[ $exit_code -eq 0 ]]; then
        echo "[$timestamp] [OK] $description (${duration}s)" >> "$LOG_FILE"
    else
        echo "[$timestamp] [FAIL] $description (exit: $exit_code)" >> "$LOG_FILE"
        echo "  Command: $cmd" >> "$LOG_FILE"
        echo "  Output: $(echo "$output" | tail -5)" >> "$LOG_FILE"
    fi

    # Return output and preserve exit code
    echo "$output"
    return $exit_code
}

# Log configuration values
log_config() {
    log_section "INSTALLATION CONFIGURATION"
    log_detail "Target Disk" "${TARGET_DISK:-<to be selected>}"
    log_detail "Boot Mode" "$BOOT_MODE"
    log_detail "EFI Size" "$EFI_SIZE"
    log_detail "Swap Size" "$SWAP_SIZE"
    log_detail "Root FS" "$ROOT_FS"
    log_detail "Hostname" "$HOSTNAME"
    log_detail "Timezone" "$TIMEZONE"
    log_detail "Locale" "$LOCALE"
    log_detail "Keymap" "$KEYMAP"
    log_detail "Username" "$USERNAME"
    log_detail "Init System" "$INIT_SYSTEM"
    log_detail "CPU Arch" "$CPU_ARCH"
    log_detail "Make Jobs" "$MAKE_JOBS"
    log_detail "Video Cards" "$VIDEO_CARDS"
    log_detail "Kernel Type" "$KERNEL_TYPE"
    log_detail "Binary Packages" "$USE_BINPKGS"

    log_subsection "Hyprland Packages"
    echo "$HYPRLAND_PACKAGES" | tr -s ' \n' '\n' | grep -v '^$' | sed 's/^/  /' >> "$LOG_FILE"

    log_subsection "Base Packages"
    echo "$BASE_PACKAGES" | tr -s ' \n' '\n' | grep -v '^$' | sed 's/^/  /' >> "$LOG_FILE"
}

# Log an error to file (internal use)
_log_file_error() {
    local msg="$1"
    local timestamp=$(date '+%H:%M:%S')

    echo "" >> "$LOG_FILE"
    echo "!!! ERROR !!! [$timestamp]" >> "$LOG_FILE"
    echo "$msg" >> "$LOG_FILE"
    echo "" >> "$LOG_FILE"

    # Capture stack trace
    echo "Stack trace:" >> "$LOG_FILE"
    local frame=0
    while caller $frame >> "$LOG_FILE" 2>/dev/null; do
        ((frame++))
    done
    echo "" >> "$LOG_FILE"
}

# Log timing for a function
log_timer_start() {
    TIMER_START=$(date +%s)
    TIMER_NAME="$1"
}

log_timer_end() {
    local end_time=$(date +%s)
    local duration=$((end_time - TIMER_START))
    local minutes=$((duration / 60))
    local seconds=$((duration % 60))
    log_msg "TIMER" "$TIMER_NAME completed in ${minutes}m ${seconds}s"
}

# Finalize log with summary
finalize_log() {
    local status="${1:-SUCCESS}"
    local end_time=$(date '+%Y-%m-%d %H:%M:%S')

    log_section "INSTALLATION SUMMARY"
    log_detail "Status" "$status"
    log_detail "Completed" "$end_time"
    log_detail "Target Disk" "$TARGET_DISK"
    log_detail "Log File" "$LOG_FILE"
    log_detail "Verbose Log" "$LOG_VERBOSE"

    # Copy logs to installed system if mounted
    if [[ -d /mnt/gentoo/var/log ]]; then
        mkdir -p /mnt/gentoo/var/log/gentoo-install
        cp "$LOG_FILE" /mnt/gentoo/var/log/gentoo-install/ 2>/dev/null || true
        cp "$LOG_VERBOSE" /mnt/gentoo/var/log/gentoo-install/ 2>/dev/null || true
        log_msg "INFO" "Logs copied to /mnt/gentoo/var/log/gentoo-install/"
    fi

    echo "" >> "$LOG_FILE"
    echo "================================================================================" >> "$LOG_FILE"
    echo "END OF LOG - $status" >> "$LOG_FILE"
    echo "================================================================================" >> "$LOG_FILE"
}

#==============================================================================
# CONFIGURATION
#==============================================================================

# Target disk - will be selected interactively
TARGET_DISK=""
PART_SUFFIX=""

# Boot mode
BOOT_MODE="uefi"

# Partition sizes
EFI_SIZE="1G"
SWAP_SIZE="8G"

# Filesystem for root partition
ROOT_FS="btrfs"

# Hostname
HOSTNAME="gentoo"

# Timezone
TIMEZONE="Europe/Stockholm"

# Locale settings
LOCALE="en_US.UTF-8"
KEYMAP="se"

# User account
USERNAME="johan"

# Init system: openrc
INIT_SYSTEM="openrc"

# Desktop: Hyprland/Wayland
DESKTOP_PROFILE="desktop"

# CPU optimization
CPU_ARCH="native"
MAKE_JOBS=$(nproc)

# Video drivers: Intel integrated + NVIDIA proprietary
VIDEO_CARDS="intel nvidia"

# Compile from source (no binary packages)
USE_BINPKGS="no"

# Kernel type: "dist" (distribution), "custom" (hardware-optimized), "bin" (binary)
KERNEL_TYPE="custom"

# Hyprland and Wayland packages
HYPRLAND_PACKAGES="
    gui-wm/hyprland
    gui-apps/waybar
    gui-apps/mako
    gui-apps/grim
    gui-apps/slurp
    gui-apps/wl-clipboard
    x11-terms/kitty
    x11-misc/wofi
    media-sound/pipewire
    media-video/wireplumber
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

# Base packages (minimal)
BASE_PACKAGES="
    app-editors/neovim
    sys-apps/pciutils
    net-misc/chrony
    dev-vcs/git
    sys-process/htop
    app-admin/doas
    media-libs/fontconfig
"

#==============================================================================
# HELPER FUNCTIONS
#==============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
    log_msg "INFO" "$1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
    log_msg "SUCCESS" "$1"
}

log_warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
    log_msg "WARNING" "$1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    _log_file_error "$1"
    finalize_log "FAILED"
    exit 1
}

log_step() {
    echo -e "\n${CYAN}========================================${NC}"
    echo -e "${CYAN} $1${NC}"
    echo -e "${CYAN}========================================${NC}\n"
    log_section "$1"
    log_timer_start "$1"
}

confirm() {
    echo -e "${YELLOW}$1${NC}"
    read -p "Continue? (yes/no): " response
    if [[ "$response" != "yes" ]]; then
        log_msg "USER" "Installation aborted by user"
        log_error "Installation aborted by user."
    fi
}

run_chroot() {
    local cmd="$1"
    log_msg "CHROOT" "$cmd"

    # Capture output for logging
    local output
    local exit_code

    if output=$(chroot /mnt/gentoo /bin/bash -c "source /etc/profile && $cmd" 2>&1); then
        exit_code=0
    else
        exit_code=$?
    fi

    # Log to verbose log
    echo "CHROOT: $cmd" >> "$LOG_VERBOSE"
    echo "$output" >> "$LOG_VERBOSE"
    echo "EXIT: $exit_code" >> "$LOG_VERBOSE"
    echo "" >> "$LOG_VERBOSE"

    # Output to console
    echo "$output"

    return $exit_code
}

#==============================================================================
# WIFI SETUP
#==============================================================================

setup_wifi() {
    log_step "WiFi Setup"

    # Check if NetworkManager is available
    if ! command -v nmcli &>/dev/null; then
        log_warn "nmcli not found, trying to start NetworkManager..."
        rc-service NetworkManager start 2>/dev/null || true
        sleep 2
    fi

    # Check current connection
    if ping -c 1 gentoo.org &>/dev/null; then
        log_success "Already connected to the internet"
        return 0
    fi

    log_info "Scanning for WiFi networks..."
    nmcli device wifi rescan 2>/dev/null || true
    sleep 2

    echo ""
    echo "Available WiFi networks:"
    nmcli device wifi list
    echo ""

    log_info "Connecting to WiFi (you will be prompted for the password)..."
    nmcli device wifi connect --ask

    # Verify connection
    sleep 3
    if ping -c 1 gentoo.org &>/dev/null; then
        log_success "WiFi connected successfully"
    else
        log_error "Failed to connect to WiFi. Please check credentials and try again."
    fi
}

#==============================================================================
# INTERACTIVE DISK SELECTION
#==============================================================================

select_disk() {
    log_step "Disk Selection"

    # Find all NVMe drives
    local nvme_drives=($(lsblk -d -n -o NAME,TYPE | grep nvme | awk '{print "/dev/"$1}'))

    if [[ ${#nvme_drives[@]} -eq 0 ]]; then
        log_error "No NVMe drives found!"
    fi

    echo "Found ${#nvme_drives[@]} NVMe drive(s):"
    echo ""

    local drive_info=()
    local idx=1

    for drive in "${nvme_drives[@]}"; do
        local size=$(lsblk -d -n -o SIZE "$drive")
        local model=$(lsblk -d -n -o MODEL "$drive" | xargs)
        echo -e "${CYAN}[$idx]${NC} $drive - $size - $model"

        # Try to find and mount partitions to show /home/johan contents
        local partitions=($(lsblk -n -o NAME "$drive" | tail -n +2))
        local found_home=false

        for part in "${partitions[@]}"; do
            local part_path="/dev/$part"
            local mount_point="/tmp/disk_check_$$_$part"

            # Skip swap partitions
            if blkid "$part_path" 2>/dev/null | grep -q 'TYPE="swap"'; then
                continue
            fi

            mkdir -p "$mount_point" 2>/dev/null || continue

            if mount -o ro "$part_path" "$mount_point" 2>/dev/null; then
                # Check for /home/johan
                if [[ -d "$mount_point/home/johan" ]]; then
                    echo -e "    ${GREEN}Found /home/johan on $part_path:${NC}"
                    ls -la "$mount_point/home/johan" 2>/dev/null | head -15 | sed 's/^/      /'
                    found_home=true
                elif [[ -d "$mount_point/johan" ]]; then
                    # Maybe this is the home partition directly
                    echo -e "    ${GREEN}Found /johan (home partition?) on $part_path:${NC}"
                    ls -la "$mount_point/johan" 2>/dev/null | head -15 | sed 's/^/      /'
                    found_home=true
                fi
                umount "$mount_point" 2>/dev/null || true
            fi
            rmdir "$mount_point" 2>/dev/null || true
        done

        if [[ "$found_home" == "false" ]]; then
            echo -e "    ${YELLOW}No /home/johan found on this drive${NC}"
        fi

        echo ""
        drive_info+=("$drive")
        ((idx++))
    done

    # Ask user to select
    echo -e "${YELLOW}Which drive do you want to install Gentoo on?${NC}"
    echo -e "${RED}WARNING: ALL DATA ON THE SELECTED DRIVE WILL BE DESTROYED!${NC}"
    echo ""

    while true; do
        read -p "Enter drive number (1-${#nvme_drives[@]}): " selection
        if [[ "$selection" =~ ^[0-9]+$ ]] && [[ "$selection" -ge 1 ]] && [[ "$selection" -le ${#nvme_drives[@]} ]]; then
            TARGET_DISK="${drive_info[$((selection-1))]}"
            break
        else
            echo "Invalid selection. Please enter a number between 1 and ${#nvme_drives[@]}"
        fi
    done

    # Set partition suffix for NVMe
    PART_SUFFIX="p"

    echo ""
    log_info "Selected disk: $TARGET_DISK"
    confirm "This will ERASE ALL DATA on $TARGET_DISK!"
}

#==============================================================================
# PRE-FLIGHT CHECKS
#==============================================================================

preflight_checks() {
    log_step "Pre-flight Checks"

    # Check if running as root
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
    fi

    # Check if booted in UEFI mode
    if [[ ! -d /sys/firmware/efi ]]; then
        log_error "System not booted in UEFI mode. Please boot in UEFI mode."
    fi

    # Check network connectivity - if not connected, try WiFi
    log_info "Checking network connectivity..."
    if ! ping -c 1 gentoo.org &>/dev/null; then
        log_warn "No network connectivity detected"
        setup_wifi
    else
        log_success "Network OK"
    fi

    # Sync system time
    log_info "Synchronizing system time..."
    if command -v chronyd &>/dev/null; then
        chronyd -q 'server pool.ntp.org iburst' 2>/dev/null || true
    fi
    log_success "Time synchronized"

    log_success "Pre-flight checks passed"
}

#==============================================================================
# DISK PARTITIONING
#==============================================================================

partition_disk() {
    log_step "Partitioning Disk"

    log_info "Partitioning $TARGET_DISK..."

    # Unmount any existing partitions
    umount -R /mnt/gentoo 2>/dev/null || true
    swapoff "${TARGET_DISK}${PART_SUFFIX}"* 2>/dev/null || true

    # Wipe existing partition table
    wipefs -af "$TARGET_DISK"

    # GPT partitioning for UEFI
    log_info "Creating GPT partition table..."
    parted -s "$TARGET_DISK" mklabel gpt
    parted -s "$TARGET_DISK" mkpart "EFI" fat32 1MiB "${EFI_SIZE}"
    parted -s "$TARGET_DISK" set 1 esp on
    parted -s "$TARGET_DISK" mkpart "swap" linux-swap "${EFI_SIZE}" "$((${EFI_SIZE%G} + ${SWAP_SIZE%G}))G"
    parted -s "$TARGET_DISK" mkpart "root" btrfs "$((${EFI_SIZE%G} + ${SWAP_SIZE%G}))G" 100%

    # Wait for kernel to recognize new partitions
    partprobe "$TARGET_DISK"
    sleep 2

    log_success "Disk partitioned successfully"
    lsblk "$TARGET_DISK"
}

#==============================================================================
# CREATE FILESYSTEMS
#==============================================================================

create_filesystems() {
    log_step "Creating Filesystems"

    local part1="${TARGET_DISK}${PART_SUFFIX}1"
    local part2="${TARGET_DISK}${PART_SUFFIX}2"
    local part3="${TARGET_DISK}${PART_SUFFIX}3"

    # EFI partition (FAT32)
    log_info "Creating EFI filesystem on $part1..."
    mkfs.vfat -F 32 "$part1"

    # Swap partition
    log_info "Creating swap on $part2..."
    mkswap "$part2"
    swapon "$part2"

    # Root partition (Btrfs)
    log_info "Creating Btrfs filesystem on $part3..."
    mkfs.btrfs -f "$part3"

    log_success "Filesystems created"
}

#==============================================================================
# MOUNT FILESYSTEMS WITH BTRFS SUBVOLUMES
#==============================================================================

mount_filesystems() {
    log_step "Mounting Filesystems"

    local part1="${TARGET_DISK}${PART_SUFFIX}1"
    local part3="${TARGET_DISK}${PART_SUFFIX}3"

    # Create mount point
    mkdir -p /mnt/gentoo

    # Mount root temporarily to create subvolumes
    log_info "Creating Btrfs subvolumes..."
    mount "$part3" /mnt/gentoo

    # Create subvolumes
    btrfs subvolume create /mnt/gentoo/@
    btrfs subvolume create /mnt/gentoo/@home
    btrfs subvolume create /mnt/gentoo/@snapshots

    # Unmount and remount with subvolumes
    umount /mnt/gentoo

    log_info "Mounting subvolumes..."
    mount -o noatime,compress=zstd,subvol=@ "$part3" /mnt/gentoo
    mkdir -p /mnt/gentoo/{home,.snapshots,efi}
    mount -o noatime,compress=zstd,subvol=@home "$part3" /mnt/gentoo/home
    mount -o noatime,compress=zstd,subvol=@snapshots "$part3" /mnt/gentoo/.snapshots

    # Mount EFI
    mount "$part1" /mnt/gentoo/efi

    log_success "Filesystems mounted"
    df -h /mnt/gentoo /mnt/gentoo/home /mnt/gentoo/efi
}

#==============================================================================
# DOWNLOAD AND EXTRACT STAGE3
#==============================================================================

install_stage3() {
    log_step "Installing Stage3"

    cd /mnt/gentoo

    # Determine stage3 URL
    local base_url="https://distfiles.gentoo.org/releases/amd64/autobuilds"
    local stage3_path=$(wget -qO- "${base_url}/latest-stage3-amd64-openrc.txt" | grep -v "^#" | head -1 | awk '{print $1}')

    if [[ -z "$stage3_path" ]]; then
        log_error "Failed to find stage3 tarball URL"
    fi

    local stage3_url="${base_url}/${stage3_path}"
    local stage3_file=$(basename "$stage3_path")

    log_info "Downloading stage3 from: $stage3_url"
    wget -q --show-progress "$stage3_url"
    wget -q "${stage3_url}.sha256"

    log_info "Verifying stage3 checksum..."
    if ! sha256sum --check --ignore-missing "${stage3_file}.sha256"; then
        log_error "Stage3 checksum verification failed!"
    fi
    log_success "Checksum verified"

    log_info "Extracting stage3 tarball (this takes a few minutes)..."
    tar xpf "$stage3_file" --xattrs-include='*.*' --numeric-owner

    rm -f "$stage3_file" "${stage3_file}.sha256"

    log_success "Stage3 installed"
}

#==============================================================================
# CONFIGURE MAKE.CONF
#==============================================================================

configure_makeconf() {
    log_step "Configuring make.conf"

    local makeconf="/mnt/gentoo/etc/portage/make.conf"

    cat > "$makeconf" << EOF
# Compiler flags optimized for this system
COMMON_FLAGS="-march=${CPU_ARCH} -O2 -pipe"
CFLAGS="\${COMMON_FLAGS}"
CXXFLAGS="\${COMMON_FLAGS}"
FCFLAGS="\${COMMON_FLAGS}"
FFLAGS="\${COMMON_FLAGS}"
LDFLAGS="-Wl,-O2 -Wl,--as-needed"
RUSTFLAGS="-C target-cpu=${CPU_ARCH}"

# Parallel builds
MAKEOPTS="-j${MAKE_JOBS}"
EMERGE_DEFAULT_OPTS="--jobs=${MAKE_JOBS} --load-average=${MAKE_JOBS}"

# Language
L10N="en sv"

# Portage features
FEATURES="parallel-fetch parallel-install candy"

# Video cards: Intel integrated + NVIDIA proprietary
VIDEO_CARDS="${VIDEO_CARDS}"

# Input devices for laptop
INPUT_DEVICES="libinput"

# Accept all licenses
ACCEPT_LICENSE="*"

# USE flags for Wayland/Hyprland setup on HP ZBook Power G9
USE="wayland vulkan pipewire pulseaudio dbus elogind \
     -X -systemd -gnome -kde -qt5 \
     bluetooth networkmanager \
     nvenc vaapi cuda opencl \
     zstd lz4 lto"
EOF

    # Create package.use directory
    mkdir -p /mnt/gentoo/etc/portage/package.use
    mkdir -p /mnt/gentoo/etc/portage/package.accept_keywords
    mkdir -p /mnt/gentoo/etc/portage/package.license

    # NVIDIA driver requirements
    cat > /mnt/gentoo/etc/portage/package.use/nvidia << 'EOF'
x11-drivers/nvidia-drivers modules driver wayland
media-libs/mesa -video_cards_nouveau
dev-util/nvidia-cuda-toolkit -profiler -nsight -debugger
EOF

    # Hyprland requirements (often needs ~amd64)
    cat > /mnt/gentoo/etc/portage/package.accept_keywords/hyprland << 'EOF'
gui-wm/hyprland ~amd64
gui-libs/hyprutils ~amd64
gui-libs/hyprcursor ~amd64
gui-libs/hyprwayland-scanner ~amd64
dev-libs/hyprlang ~amd64
gui-libs/aquamarine ~amd64
gui-apps/hyprlock ~amd64
gui-apps/hypridle ~amd64
gui-apps/hyprpaper ~amd64
sys-apps/xdg-desktop-portal-hyprland ~amd64
EOF

    log_success "make.conf configured"
}

#==============================================================================
# SETUP CHROOT ENVIRONMENT
#==============================================================================

setup_chroot() {
    log_step "Setting up Chroot Environment"

    # Copy DNS info
    cp --dereference /etc/resolv.conf /mnt/gentoo/etc/

    # Mount necessary filesystems
    mount --types proc /proc /mnt/gentoo/proc
    mount --rbind /sys /mnt/gentoo/sys
    mount --make-rslave /mnt/gentoo/sys
    mount --rbind /dev /mnt/gentoo/dev
    mount --make-rslave /mnt/gentoo/dev
    mount --bind /run /mnt/gentoo/run
    mount --make-slave /mnt/gentoo/run

    log_success "Chroot environment ready"
}

#==============================================================================
# CONFIGURE PORTAGE
#==============================================================================

configure_portage() {
    log_step "Configuring Portage"

    # Create repos.conf
    run_chroot "mkdir -p /etc/portage/repos.conf"
    run_chroot "cp /usr/share/portage/config/repos.conf /etc/portage/repos.conf/gentoo.conf"

    # Sync repository
    log_info "Syncing Portage tree (this will take a while)..."
    run_chroot "emerge-webrsync"

    # Enable GURU repository for Hyprland packages
    log_info "Enabling GURU repository..."
    run_chroot "emerge app-eselect/eselect-repository"
    run_chroot "eselect repository enable guru"
    run_chroot "emerge --sync guru"

    # Read news
    run_chroot "eselect news read --quiet all" || true

    # Select desktop profile (OpenRC, no DE)
    log_info "Selecting desktop profile..."
    # Try to set the desktop/openrc profile directly, fall back to generic desktop
    if run_chroot "eselect profile set default/linux/amd64/23.0/desktop" 2>/dev/null; then
        log_info "Selected profile: default/linux/amd64/23.0/desktop"
    else
        # Fallback: find any desktop profile without systemd/gnome/kde
        local profile_num=$(run_chroot "eselect profile list" | grep -E '\[.*\].*default/linux/amd64/.*/desktop\s*$' | grep -v "gnome\|plasma\|systemd" | head -1 | sed 's/.*\[\([0-9]*\)\].*/\1/')
        if [[ -n "$profile_num" ]]; then
            run_chroot "eselect profile set $profile_num"
            log_info "Selected profile number: $profile_num"
        fi
    fi

    # Set CPU flags
    log_info "Setting CPU flags..."
    run_chroot "emerge --oneshot app-portage/cpuid2cpuflags"
    run_chroot "echo \"*/* \$(cpuid2cpuflags)\" > /etc/portage/package.use/00cpu-flags"

    # Update @world
    log_info "Updating @world set (this will take a long time)..."
    run_chroot "emerge --update --deep --newuse @world"

    log_success "Portage configured"
}

#==============================================================================
# CONFIGURE TIMEZONE AND LOCALE
#==============================================================================

configure_locale() {
    log_step "Configuring Timezone and Locale"

    # Timezone
    run_chroot "ln -sf /usr/share/zoneinfo/${TIMEZONE} /etc/localtime"
    echo "${TIMEZONE}" > /mnt/gentoo/etc/timezone
    run_chroot "emerge --config sys-libs/timezone-data" || true

    # Locale
    cat >> /mnt/gentoo/etc/locale.gen << EOF
en_US.UTF-8 UTF-8
en_US ISO-8859-1
sv_SE.UTF-8 UTF-8
sv_SE ISO-8859-1
EOF

    run_chroot "locale-gen"

    # Set system locale
    run_chroot "eselect locale set en_US.utf8" || \
    run_chroot "eselect locale set C.UTF8"

    # Reload environment
    run_chroot "env-update"

    log_success "Timezone and locale configured"
}

#==============================================================================
# INSTALL KERNEL
#==============================================================================

install_kernel() {
    log_step "Installing Kernel"

    # Install firmware
    log_info "Installing firmware..."
    run_chroot "emerge sys-kernel/linux-firmware sys-firmware/intel-microcode"

    # Install kernel build dependencies and dracut
    run_chroot "emerge sys-kernel/installkernel sys-kernel/dracut sys-apps/kmod"

    if [[ "$KERNEL_TYPE" == "custom" ]]; then
        install_custom_kernel
    elif [[ "$KERNEL_TYPE" == "bin" ]]; then
        log_info "Installing binary distribution kernel..."
        run_chroot "emerge sys-kernel/gentoo-kernel-bin"
    else
        log_info "Installing distribution kernel (compiling, this takes a while)..."
        run_chroot "emerge sys-kernel/gentoo-kernel"
    fi

    log_success "Kernel installed"
}

#==============================================================================
# CUSTOM KERNEL FOR HP ZBOOK POWER G9
#==============================================================================

install_custom_kernel() {
    log_info "Installing custom kernel optimized for HP ZBook Power G9..."

    # Install kernel sources
    run_chroot "emerge sys-kernel/gentoo-sources"
    run_chroot "eselect kernel set 1"

    # Create kernel config optimized for this hardware
    log_info "Generating hardware-optimized kernel config..."

    # Start with defconfig and customize
    run_chroot "cd /usr/src/linux && make defconfig"

    # Create a script to modify the config
    cat > /mnt/gentoo/tmp/kernel_config.sh << 'KERNELSCRIPT'
#!/bin/bash
cd /usr/src/linux

# Helper functions using scripts/config
enable_config() {
    scripts/config --enable "$1" 2>/dev/null || echo "Note: $1 may not exist"
}
disable_config() {
    scripts/config --disable "$1" 2>/dev/null || echo "Note: $1 may not exist"
}
module_config() {
    scripts/config --module "$1" 2>/dev/null || echo "Note: $1 may not exist"
}
set_val() {
    scripts/config --set-val "$1" "$2" 2>/dev/null || echo "Note: $1 may not exist"
}

echo "Configuring kernel for HP ZBook Power G9 (Intel i7-12800H + NVIDIA RTX A2000)..."

#=============================================================================
# PROCESSOR - Intel Alder Lake i7-12800H (Hybrid P+E cores)
#=============================================================================

# Intel CPU support only
enable_config CPU_SUP_INTEL
disable_config CPU_SUP_AMD
disable_config CPU_SUP_CENTAUR
disable_config CPU_SUP_ZHAOXIN

# Alder Lake hybrid scheduling support (P-cores + E-cores)
# CONFIG_SCHED_MC_PRIO enables Intel Turbo Boost Max 3.0 / ITMT priority scheduling
enable_config SCHED_MC
enable_config SCHED_MC_PRIO

# Intel Hardware Feedback Interface (Thread Director for hybrid CPUs)
# This is critical for proper Alder Lake P-core/E-core scheduling
enable_config THERMAL
enable_config INTEL_HFI_THERMAL

# Intel P-State driver for frequency scaling
enable_config X86_INTEL_PSTATE
enable_config X86_ACPI_CPUFREQ

# Performance - disable CPU vulnerability mitigations (user chose performance)
# WARNING: This improves performance but exposes system to speculative execution attacks
# CONFIG_CPU_MITIGATIONS controls all mitigation options (kernel 6.8+)
disable_config CPU_MITIGATIONS

# Processor features
enable_config X86_X2APIC
enable_config X86_TSC
enable_config X86_CPUID
enable_config X86_MSR
enable_config MTRR

# Intel performance monitoring
enable_config PERF_EVENTS
enable_config PERF_EVENTS_INTEL_UNCORE
enable_config PERF_EVENTS_INTEL_RAPL
enable_config PERF_EVENTS_INTEL_CSTATE

# Intel thermal and power management
enable_config INTEL_RAPL
enable_config INTEL_POWERCLAMP
enable_config X86_PKG_TEMP_THERMAL
enable_config INTEL_HID_EVENT
enable_config INTEL_VBTN

# Preemption model - full preemption for desktop responsiveness
enable_config PREEMPT
disable_config PREEMPT_NONE
disable_config PREEMPT_VOLUNTARY

# Timer frequency - 1000Hz for responsive desktop
set_val HZ 1000
enable_config HZ_1000
disable_config HZ_300
disable_config HZ_250
disable_config HZ_100

#=============================================================================
# GRAPHICS - Intel Iris Xe + NVIDIA RTX A2000 (proprietary driver)
#=============================================================================

# DRM core
enable_config DRM

# Intel integrated graphics (i915) - built-in for early boot
enable_config DRM_I915

# NVIDIA - DISABLE nouveau (we use proprietary nvidia-drivers)
# The proprietary driver provides its own kernel modules
disable_config DRM_NOUVEAU

# Framebuffer support (needed for console before NVIDIA driver loads)
enable_config DRM_FBDEV_EMULATION
enable_config FB
enable_config FB_EFI
enable_config FB_VESA
enable_config FRAMEBUFFER_CONSOLE
enable_config FRAMEBUFFER_CONSOLE_DETECT_PRIMARY

# VGA Arbitration (required by NVIDIA)
enable_config VGA_ARB

# Loadable module support (required for NVIDIA driver)
enable_config MODULES
enable_config MODULE_UNLOAD

#=============================================================================
# STORAGE - NVMe + Btrfs
#=============================================================================

# NVMe support (built-in for root on NVMe)
enable_config BLK_DEV_NVME
enable_config NVME_CORE

# Btrfs (built-in for root filesystem)
enable_config BTRFS_FS
enable_config BTRFS_FS_POSIX_ACL

# Required dependencies for Btrfs
enable_config CRYPTO
enable_config CRYPTO_CRC32C
enable_config CRYPTO_XXHASH
enable_config CRYPTO_SHA256
enable_config CRYPTO_BLAKE2B
enable_config LIBCRC32C
enable_config XOR_BLOCKS
enable_config RAID6_PQ

# Compression support for Btrfs (zstd, lzo, lz4)
enable_config ZSTD_COMPRESS
enable_config ZSTD_DECOMPRESS
enable_config LZO_COMPRESS
enable_config LZO_DECOMPRESS
enable_config LZ4_COMPRESS
enable_config LZ4_DECOMPRESS
enable_config CRYPTO_LZ4
enable_config CRYPTO_LZ4HC
enable_config CRYPTO_ZSTD

# CRC acceleration for Intel CPUs (improves Btrfs performance)
enable_config CRYPTO_CRC32C_INTEL

# Other filesystems
enable_config EXT4_FS
enable_config VFAT_FS
enable_config FAT_FS
enable_config MSDOS_FS
enable_config EXFAT_FS
enable_config NLS_CODEPAGE_437
enable_config NLS_ISO8859_1
enable_config NLS_UTF8

#=============================================================================
# NETWORKING - Intel WiFi AX211 + Bluetooth
#=============================================================================

# Wireless core
enable_config WIRELESS
enable_config WLAN
enable_config CFG80211
enable_config MAC80211

# Intel WiFi (iwlwifi - supports AX200/AX201/AX210/AX211)
enable_config IWLWIFI
enable_config IWLMVM
enable_config IWLDVM

# Bluetooth
enable_config BT
enable_config BT_BREDR
enable_config BT_LE
enable_config BT_HCIBTUSB
enable_config BT_HCIUART
enable_config BT_INTEL

# Intel Ethernet (if docked)
enable_config NET_VENDOR_INTEL
enable_config E1000E
enable_config IGB
enable_config IGBVF

# Network tools
enable_config NETDEVICES
enable_config NET_CORE
enable_config INET
enable_config IPV6

#=============================================================================
# LAPTOP / POWER MANAGEMENT / ACPI
#=============================================================================

# ACPI core
enable_config ACPI
enable_config ACPI_AC
enable_config ACPI_BATTERY
enable_config ACPI_BUTTON
enable_config ACPI_FAN
enable_config ACPI_PROCESSOR
enable_config ACPI_THERMAL
enable_config ACPI_VIDEO

# Power management
enable_config PM
enable_config PM_SLEEP
enable_config SUSPEND
enable_config HIBERNATION
enable_config PM_WAKELOCKS

# CPU idle
enable_config CPU_IDLE
enable_config CPU_IDLE_GOV_LADDER
enable_config CPU_IDLE_GOV_MENU
enable_config CPU_IDLE_GOV_TEO
enable_config INTEL_IDLE

# Thunderbolt/USB4 (ZBook has Thunderbolt ports)
enable_config THUNDERBOLT
enable_config USB4

# Backlight
enable_config BACKLIGHT_CLASS_DEVICE

#=============================================================================
# INPUT - Keyboard, Touchpad, Touchscreen
#=============================================================================

enable_config INPUT
enable_config INPUT_EVDEV
enable_config INPUT_KEYBOARD
enable_config KEYBOARD_ATKBD
enable_config INPUT_MOUSE
enable_config MOUSE_PS2
enable_config MOUSE_PS2_SYNAPTICS
enable_config MOUSE_PS2_SYNAPTICS_SMBUS
enable_config MOUSE_PS2_ELANTECH
enable_config MOUSE_PS2_ELANTECH_SMBUS
enable_config INPUT_TOUCHSCREEN

# HID (Human Interface Devices)
enable_config HID
enable_config HID_GENERIC
enable_config HID_MULTITOUCH
enable_config USB_HID
enable_config I2C_HID
enable_config I2C_HID_ACPI

#=============================================================================
# USB
#=============================================================================

enable_config USB_SUPPORT
enable_config USB
enable_config USB_PCI
enable_config USB_XHCI_HCD
enable_config USB_XHCI_PCI
enable_config USB_EHCI_HCD
enable_config USB_STORAGE
enable_config USB_UAS

#=============================================================================
# SOUND - Intel HDA (Realtek) + NVIDIA HDMI Audio
#=============================================================================

enable_config SOUND
enable_config SND
enable_config SND_PCI
enable_config SND_HDA
enable_config SND_HDA_INTEL
enable_config SND_HDA_CODEC_REALTEK
enable_config SND_HDA_CODEC_HDMI
enable_config SND_HDA_GENERIC
enable_config SND_USB_AUDIO

# Intel SOF (Sound Open Firmware) for newer Intel audio
enable_config SND_SOC
enable_config SND_SOC_SOF_TOPLEVEL
enable_config SND_SOC_SOF_PCI
enable_config SND_SOC_SOF_INTEL_TOPLEVEL
enable_config SND_SOC_SOF_ALDERLAKE

#=============================================================================
# SECURITY - Minimal (performance focus per user choice)
#=============================================================================

# Disable MAC security frameworks
disable_config SECURITY_SELINUX
disable_config SECURITY_APPARMOR
disable_config SECURITY_TOMOYO
disable_config SECURITY_SMACK
disable_config SECURITY_LOCKDOWN_LSM

# Disable kernel debugging (performance)
disable_config DEBUG_KERNEL
disable_config DEBUG_INFO
disable_config DEBUG_INFO_DWARF_TOOLCHAIN_DEFAULT
disable_config DEBUG_INFO_DWARF4
disable_config DEBUG_INFO_DWARF5
disable_config KASAN
disable_config UBSAN
disable_config DEBUG_MEMORY_INIT
disable_config DEBUG_PREEMPT

# Keep stack protector (minimal overhead, good protection)
enable_config STACKPROTECTOR
enable_config STACKPROTECTOR_STRONG

#=============================================================================
# VIRTUALIZATION (KVM for VMs)
#=============================================================================

enable_config VIRTUALIZATION
enable_config KVM
enable_config KVM_INTEL
module_config VHOST_NET
module_config TUN
module_config TAP
enable_config BRIDGE

#=============================================================================
# CONTAINERS & NAMESPACES
#=============================================================================

enable_config NAMESPACES
enable_config UTS_NS
enable_config IPC_NS
enable_config USER_NS
enable_config PID_NS
enable_config NET_NS
enable_config CGROUPS
enable_config CGROUP_SCHED
enable_config CGROUP_PIDS
enable_config CGROUP_CPUACCT
enable_config MEMCG
enable_config CGROUP_DEVICE
enable_config CGROUP_FREEZER

#=============================================================================
# MISC
#=============================================================================

# FUSE (user-space filesystems)
enable_config FUSE_FS

# inotify (file system event monitoring)
enable_config INOTIFY_USER

# EFI
enable_config EFI
enable_config EFI_STUB
enable_config EFI_MIXED
enable_config EFIVAR_FS

# Zswap for swap compression
enable_config ZSWAP
enable_config ZPOOL
enable_config Z3FOLD
enable_config ZBUD

# Random number generation
enable_config HW_RANDOM
enable_config HW_RANDOM_INTEL

echo "Kernel configuration complete."
KERNELSCRIPT

    chmod +x /mnt/gentoo/tmp/kernel_config.sh
    run_chroot "/tmp/kernel_config.sh"

    # Ensure config is complete
    run_chroot "cd /usr/src/linux && make olddefconfig"

    # Compile kernel
    log_info "Compiling kernel (this will take 20-40 minutes)..."
    run_chroot "cd /usr/src/linux && make -j${MAKE_JOBS}"

    # Install modules and kernel
    log_info "Installing kernel modules..."
    run_chroot "cd /usr/src/linux && make modules_install"
    run_chroot "cd /usr/src/linux && make install"

    # Generate initramfs with dracut
    log_info "Generating initramfs..."
    local kernel_version=$(run_chroot "ls /lib/modules/ | head -1")
    run_chroot "dracut --kver ${kernel_version} --force"

    # Cleanup
    rm -f /mnt/gentoo/tmp/kernel_config.sh

    log_success "Custom kernel compiled and installed"
}

#==============================================================================
# CONFIGURE FSTAB
#==============================================================================

configure_fstab() {
    log_step "Configuring fstab"

    local part1="${TARGET_DISK}${PART_SUFFIX}1"
    local part2="${TARGET_DISK}${PART_SUFFIX}2"
    local part3="${TARGET_DISK}${PART_SUFFIX}3"

    # Get UUIDs
    local uuid_efi=$(blkid -s UUID -o value "$part1")
    local uuid_swap=$(blkid -s UUID -o value "$part2")
    local uuid_root=$(blkid -s UUID -o value "$part3")

    cat > /mnt/gentoo/etc/fstab << EOF
# /etc/fstab: static file system information.
# <fs>                                  <mountpoint>   <type>   <opts>                              <dump/pass>

# Root subvolume
UUID=${uuid_root}  /              btrfs    noatime,compress=zstd,subvol=@          0 1

# Home subvolume
UUID=${uuid_root}  /home          btrfs    noatime,compress=zstd,subvol=@home      0 2

# Snapshots subvolume
UUID=${uuid_root}  /.snapshots    btrfs    noatime,compress=zstd,subvol=@snapshots 0 2

# Swap partition
UUID=${uuid_swap}  none           swap     sw                                       0 0

# EFI System Partition
UUID=${uuid_efi}   /efi           vfat     noatime,fmask=0137,dmask=0027            0 2
EOF

    log_success "fstab configured"
}

#==============================================================================
# CONFIGURE SYSTEM
#==============================================================================

configure_system() {
    log_step "Configuring System"

    # Hostname
    echo "$HOSTNAME" > /mnt/gentoo/etc/hostname

    # Hosts file
    cat > /mnt/gentoo/etc/hosts << EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   ${HOSTNAME}.localdomain ${HOSTNAME}
EOF

    # Keymap
    sed -i "s/keymap=\"us\"/keymap=\"${KEYMAP}\"/" /mnt/gentoo/etc/conf.d/keymaps

    # Console font for Swedish characters
    sed -i 's/consolefont="default8x16"/consolefont="lat9w-16"/' /mnt/gentoo/etc/conf.d/consolefont

    log_success "System configured"
}

#==============================================================================
# INSTALL NVIDIA DRIVER
#==============================================================================

install_nvidia() {
    log_step "Installing NVIDIA Driver"

    # Accept NVIDIA license
    echo "x11-drivers/nvidia-drivers NVIDIA-r2" > /mnt/gentoo/etc/portage/package.license/nvidia

    log_info "Installing NVIDIA proprietary driver..."
    run_chroot "emerge x11-drivers/nvidia-drivers"

    # Create modprobe config
    mkdir -p /mnt/gentoo/etc/modprobe.d
    cat > /mnt/gentoo/etc/modprobe.d/nvidia.conf << 'EOF'
# Enable DRM kernel mode setting
options nvidia_drm modeset=1 fbdev=1
EOF

    # Blacklist nouveau
    cat > /mnt/gentoo/etc/modprobe.d/blacklist-nouveau.conf << 'EOF'
blacklist nouveau
EOF

    # Add nvidia modules to load at boot (OpenRC method)
    cat >> /mnt/gentoo/etc/conf.d/modules << 'EOF'

# NVIDIA modules for Wayland/Hyprland
modules="nvidia nvidia_modeset nvidia_uvm nvidia_drm"
EOF

    log_success "NVIDIA driver installed"
}

#==============================================================================
# INSTALL HYPRLAND AND WAYLAND
#==============================================================================

install_hyprland() {
    log_step "Installing Hyprland and Wayland"

    # Install elogind for session management (OpenRC)
    log_info "Installing elogind..."
    run_chroot "emerge sys-auth/elogind sys-auth/polkit"
    run_chroot "rc-update add elogind boot"

    # Install dbus
    run_chroot "emerge sys-apps/dbus"
    run_chroot "rc-update add dbus default"

    # Install Hyprland and related packages
    log_info "Installing Hyprland (this will take a while)..."
    run_chroot "emerge ${HYPRLAND_PACKAGES}"

    # Create Hyprland config directory for user
    mkdir -p "/mnt/gentoo/home/${USERNAME}/.config/hypr"
    mkdir -p "/mnt/gentoo/home/${USERNAME}/Pictures/Screenshots"

    # Create basic Hyprland config (based on johanjans/arch dotfiles)
    cat > "/mnt/gentoo/home/${USERNAME}/.config/hypr/hyprland.conf" << 'EOF'
# Hyprland Configuration
# Based on https://github.com/johanjans/arch

#==============================================================================
# VARIABLES
#==============================================================================

$terminal = kitty
$menu = wofi --show drun

#==============================================================================
# MONITOR
#==============================================================================

monitor=,preferred,auto,1

#==============================================================================
# AUTOSTART
#==============================================================================

exec-once = waybar
exec-once = mako
exec-once = hypridle

#==============================================================================
# ENVIRONMENT VARIABLES (NVIDIA)
#==============================================================================

env = XCURSOR_SIZE,24
env = HYPRCURSOR_SIZE,24
env = LIBVA_DRIVER_NAME,nvidia
env = XDG_SESSION_TYPE,wayland
env = __GLX_VENDOR_LIBRARY_NAME,nvidia
env = ELECTRON_OZONE_PLATFORM_HINT,auto

#==============================================================================
# INPUT
#==============================================================================

input {
    kb_layout = se
    kb_variant =
    kb_model =
    kb_options =
    kb_rules =
    follow_mouse = 1
    sensitivity = 0
    numlock_by_default = true
    repeat_rate = 25
    repeat_delay = 300

    touchpad {
        natural_scroll = yes
        scroll_factor = 0.5
    }
}

#==============================================================================
# GENERAL
#==============================================================================

general {
    gaps_in = 5
    gaps_out = 10
    border_size = 2
    col.active_border = rgba(cba6f7ff) rgba(f38ba8ff) rgba(fab387ff) rgba(f9e2afff) rgba(a6e3a1ff) rgba(74c7ecff) rgba(b4befeff) 270deg
    col.inactive_border = rgba(6c7086aa)
    resize_on_border = false
    allow_tearing = false
    layout = dwindle
}

#==============================================================================
# DECORATION
#==============================================================================

decoration {
    rounding = 10
    active_opacity = 1.0
    inactive_opacity = 0.95

    shadow {
        enabled = true
        range = 32
        render_power = 4
        color = rgba(1a1a1aee)
    }

    blur {
        enabled = true
        size = 8
        passes = 4
        vibrancy = 0.1696
    }
}

#==============================================================================
# ANIMATIONS
#==============================================================================

animations {
    enabled = yes

    bezier = smooth, 0.25, 0.1, 0.25, 1
    bezier = smoothOut, 0.36, 0, 0.66, -0.56
    bezier = smoothIn, 0.25, 1, 0.5, 1
    bezier = gentle, 0.5, 0, 0.5, 1
    bezier = linear, 0, 0, 1, 1
    bezier = overshot, 0.05, 0.9, 0.1, 1.1

    animation = windows, 1, 5, smooth
    animation = windowsOut, 1, 5, smoothOut, popin 80%
    animation = windowsIn, 1, 5, smoothIn, popin 80%
    animation = fade, 1, 5, smooth
    animation = workspaces, 1, 4, gentle, slide
    animation = border, 1, 10, default
    animation = borderangle, 1, 150, linear, loop
}

#==============================================================================
# LAYOUT
#==============================================================================

dwindle {
    pseudotile = true
    preserve_split = true
}

master {
    new_status = master
}

misc {
    force_default_wallpaper = 0
    disable_hyprland_logo = true
}

#==============================================================================
# KEYBINDINGS
#==============================================================================

$mainMod = SUPER

# Application shortcuts
bind = $mainMod, Q, exec, $terminal
bind = $mainMod, R, exec, $menu
bind = $mainMod, L, exec, hyprlock

# Window management
bind = $mainMod, C, killactive,
bind = $mainMod, M, exit,
bind = $mainMod, V, togglefloating,
bind = $mainMod, P, pseudo,
bind = $mainMod, J, togglesplit,
bind = $mainMod, F, fullscreen, 2

# Alt-Tab window cycling
bind = ALT, Tab, cyclenext,
bind = ALT, Tab, bringactivetotop,

# Move focus with arrow keys
bind = $mainMod, left, movefocus, l
bind = $mainMod, right, movefocus, r
bind = $mainMod, up, movefocus, u
bind = $mainMod, down, movefocus, d

# Switch workspaces
bind = $mainMod, 1, workspace, 1
bind = $mainMod, 2, workspace, 2
bind = $mainMod, 3, workspace, 3
bind = $mainMod, 4, workspace, 4
bind = $mainMod, 5, workspace, 5
bind = $mainMod, 6, workspace, 6
bind = $mainMod, 7, workspace, 7
bind = $mainMod, 8, workspace, 8
bind = $mainMod, 9, workspace, 9
bind = $mainMod, 0, workspace, 10

# Move active window to workspace
bind = $mainMod SHIFT, 1, movetoworkspace, 1
bind = $mainMod SHIFT, 2, movetoworkspace, 2
bind = $mainMod SHIFT, 3, movetoworkspace, 3
bind = $mainMod SHIFT, 4, movetoworkspace, 4
bind = $mainMod SHIFT, 5, movetoworkspace, 5
bind = $mainMod SHIFT, 6, movetoworkspace, 6
bind = $mainMod SHIFT, 7, movetoworkspace, 7
bind = $mainMod SHIFT, 8, movetoworkspace, 8
bind = $mainMod SHIFT, 9, movetoworkspace, 9
bind = $mainMod SHIFT, 0, movetoworkspace, 10

# Special workspace (scratchpad)
bind = $mainMod, S, togglespecialworkspace, magic
bind = $mainMod SHIFT, S, movetoworkspace, special:magic

# Scroll through workspaces with mouse wheel
bind = $mainMod, mouse_down, workspace, e+1
bind = $mainMod, mouse_up, workspace, e-1

# Move/resize windows with mouse
bindm = $mainMod, mouse:272, movewindow
bindm = $mainMod, mouse:273, resizewindow

# Screenshots
bind = , Print, exec, grim -g "$(slurp)" - | wl-copy
bind = SHIFT, Print, exec, grim -g "$(slurp)" ~/Pictures/Screenshots/$(date +'%s_grim.png')

# Media controls
bindel = ,XF86AudioRaiseVolume, exec, wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+
bindel = ,XF86AudioLowerVolume, exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-
bindel = ,XF86AudioMute, exec, wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle
bindel = ,XF86AudioMicMute, exec, wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle

# Brightness controls
bindel = ,XF86MonBrightnessUp, exec, brightnessctl -e4 -n2 set 5%+
bindel = ,XF86MonBrightnessDown, exec, brightnessctl -e4 -n2 set 5%-

# Media playback
bindl = , XF86AudioNext, exec, playerctl next
bindl = , XF86AudioPause, exec, playerctl play-pause
bindl = , XF86AudioPlay, exec, playerctl play-pause
bindl = , XF86AudioPrev, exec, playerctl previous

#==============================================================================
# WINDOW RULES
#==============================================================================

windowrulev2 = suppressevent maximize, class:.*
EOF

    log_success "Hyprland installed and configured"
}

#==============================================================================
# INSTALL CATPPUCCIN MOCHA THEMES
#==============================================================================

install_catppuccin_themes() {
    log_step "Installing Catppuccin Mocha Themes"

    local config_dir="/mnt/gentoo/home/${USERNAME}/.config"

    #==========================================================================
    # JETBRAINSMONO NERD FONT
    #==========================================================================
    log_info "Installing JetBrainsMono Nerd Font..."

    local font_dir="/mnt/gentoo/usr/share/fonts/nerd-fonts"
    mkdir -p "${font_dir}"

    # Download and extract JetBrainsMono Nerd Font
    local font_url="https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.tar.xz"
    curl -sL "${font_url}" | tar -xJ -C "${font_dir}"

    # Update font cache in chroot
    run_chroot "fc-cache -fv"

    log_success "JetBrainsMono Nerd Font installed"

    #==========================================================================
    # HYPRLAND - Catppuccin Mocha color definitions
    #==========================================================================
    log_info "Configuring Hyprland with Catppuccin Mocha..."

    cat > "${config_dir}/hypr/mocha.conf" << 'EOF'
# Catppuccin Mocha colors for Hyprland
# https://github.com/catppuccin/hyprland

$rosewater = 0xfff5e0dc
$flamingo  = 0xfff2cdcd
$pink      = 0xfff5c2e7
$mauve     = 0xffcba6f7
$red       = 0xfff38ba8
$maroon    = 0xffeba0ac
$peach     = 0xfffab387
$yellow    = 0xfff9e2af
$green     = 0xffa6e3a1
$teal      = 0xff94e2d5
$sky       = 0xff89dceb
$sapphire  = 0xff74c7ec
$blue      = 0xff89b4fa
$lavender  = 0xffb4befe
$text      = 0xffcdd6f4
$subtext1  = 0xffbac2de
$subtext0  = 0xffa6adc8
$overlay2  = 0xff9399b2
$overlay1  = 0xff7f849c
$overlay0  = 0xff6c7086
$surface2  = 0xff585b70
$surface1  = 0xff45475a
$surface0  = 0xff313244
$base      = 0xff1e1e2e
$mantle    = 0xff181825
$crust     = 0xff11111b
EOF

    #==========================================================================
    # KITTY - Catppuccin Mocha theme (built-in for Kitty 0.26+)
    #==========================================================================
    log_info "Configuring Kitty with Catppuccin Mocha..."

    mkdir -p "${config_dir}/kitty"
    cat > "${config_dir}/kitty/kitty.conf" << 'EOF'
# Kitty Configuration with Catppuccin Mocha
# https://github.com/catppuccin/kitty

# Font
font_family      JetBrainsMono Nerd Font
bold_font        auto
italic_font      auto
bold_italic_font auto
font_size        11.0

# Cursor
cursor_shape beam
cursor_blink_interval 0

# Scrollback
scrollback_lines 10000

# Mouse
mouse_hide_wait 3.0
copy_on_select yes

# Bell
enable_audio_bell no
visual_bell_duration 0.0

# Window
window_padding_width 8
confirm_os_window_close 0

# Tab bar
tab_bar_min_tabs            1
tab_bar_edge                bottom
tab_bar_style               powerline
tab_powerline_style         slanted
tab_title_template          {title}{' :{}:'.format(num_windows) if num_windows > 1 else ''}

# Catppuccin Mocha Theme
include mocha.conf
EOF

    # Kitty Mocha theme file
    cat > "${config_dir}/kitty/mocha.conf" << 'EOF'
# Catppuccin Mocha for Kitty
# https://github.com/catppuccin/kitty

# The basic colors
foreground              #CDD6F4
background              #1E1E2E
selection_foreground    #1E1E2E
selection_background    #F5E0DC

# Cursor colors
cursor                  #F5E0DC
cursor_text_color       #1E1E2E

# URL underline color when hovering with mouse
url_color               #F5E0DC

# Kitty window border colors
active_border_color     #B4BEFE
inactive_border_color   #6C7086
bell_border_color       #F9E2AF

# OS Window titlebar colors
wayland_titlebar_color  #1E1E2E
macos_titlebar_color    #1E1E2E

# Tab bar colors
active_tab_foreground   #11111B
active_tab_background   #CBA6F7
inactive_tab_foreground #CDD6F4
inactive_tab_background #181825
tab_bar_background      #11111B

# Colors for marks
mark1_foreground #1E1E2E
mark1_background #B4BEFE
mark2_foreground #1E1E2E
mark2_background #CBA6F7
mark3_foreground #1E1E2E
mark3_background #74C7EC

# The 16 terminal colors

# black
color0 #45475A
color8 #585B70

# red
color1 #F38BA8
color9 #F38BA8

# green
color2  #A6E3A1
color10 #A6E3A1

# yellow
color3  #F9E2AF
color11 #F9E2AF

# blue
color4  #89B4FA
color12 #89B4FA

# magenta
color5  #F5C2E7
color13 #F5C2E7

# cyan
color6  #94E2D5
color14 #94E2D5

# white
color7  #BAC2DE
color15 #A6ADC8
EOF

    #==========================================================================
    # WAYBAR - Catppuccin Mocha CSS
    #==========================================================================
    log_info "Configuring Waybar with Catppuccin Mocha..."

    mkdir -p "${config_dir}/waybar"

    # Mocha color definitions
    cat > "${config_dir}/waybar/mocha.css" << 'EOF'
/* Catppuccin Mocha colors for Waybar */
/* https://github.com/catppuccin/waybar */

@define-color rosewater #f5e0dc;
@define-color flamingo #f2cdcd;
@define-color pink #f5c2e7;
@define-color mauve #cba6f7;
@define-color red #f38ba8;
@define-color maroon #eba0ac;
@define-color peach #fab387;
@define-color yellow #f9e2af;
@define-color green #a6e3a1;
@define-color teal #94e2d5;
@define-color sky #89dceb;
@define-color sapphire #74c7ec;
@define-color blue #89b4fa;
@define-color lavender #b4befe;
@define-color text #cdd6f4;
@define-color subtext1 #bac2de;
@define-color subtext0 #a6adc8;
@define-color overlay2 #9399b2;
@define-color overlay1 #7f849c;
@define-color overlay0 #6c7086;
@define-color surface2 #585b70;
@define-color surface1 #45475a;
@define-color surface0 #313244;
@define-color base #1e1e2e;
@define-color mantle #181825;
@define-color crust #11111b;
EOF

    # Waybar config
    cat > "${config_dir}/waybar/config" << 'EOF'
{
    "layer": "top",
    "position": "top",
    "height": 30,
    "spacing": 4,
    "modules-left": ["hyprland/workspaces", "hyprland/window"],
    "modules-center": ["clock"],
    "modules-right": ["pulseaudio", "network", "cpu", "memory", "temperature", "backlight", "battery", "tray"],

    "hyprland/workspaces": {
        "format": "{icon}",
        "on-click": "activate",
        "format-icons": {
            "1": "1",
            "2": "2",
            "3": "3",
            "4": "4",
            "5": "5",
            "6": "6",
            "7": "7",
            "8": "8",
            "9": "9",
            "10": "0"
        },
        "sort-by-number": true
    },

    "hyprland/window": {
        "max-length": 50
    },

    "clock": {
        "format": "{:%H:%M}",
        "format-alt": "{:%Y-%m-%d %H:%M:%S}",
        "tooltip-format": "<tt><small>{calendar}</small></tt>",
        "calendar": {
            "mode": "month",
            "format": {
                "months": "<span color='#f5e0dc'><b>{}</b></span>",
                "days": "<span color='#cdd6f4'>{}</span>",
                "weekdays": "<span color='#f9e2af'><b>{}</b></span>",
                "today": "<span color='#f38ba8'><b><u>{}</u></b></span>"
            }
        }
    },

    "cpu": {
        "format": " {usage}%",
        "tooltip": true
    },

    "memory": {
        "format": " {}%"
    },

    "temperature": {
        "critical-threshold": 80,
        "format": " {temperatureC}°C"
    },

    "backlight": {
        "format": "{icon} {percent}%",
        "format-icons": ["", "", "", "", "", "", "", "", ""]
    },

    "battery": {
        "states": {
            "warning": 30,
            "critical": 15
        },
        "format": "{icon} {capacity}%",
        "format-charging": " {capacity}%",
        "format-plugged": " {capacity}%",
        "format-icons": ["", "", "", "", ""]
    },

    "network": {
        "format-wifi": " {signalStrength}%",
        "format-ethernet": " {ipaddr}",
        "format-disconnected": "⚠ Disconnected",
        "tooltip-format": "{ifname}: {ipaddr}"
    },

    "pulseaudio": {
        "format": "{icon} {volume}%",
        "format-muted": " Muted",
        "format-icons": {
            "default": ["", "", ""]
        },
        "on-click": "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"
    },

    "tray": {
        "spacing": 10
    }
}
EOF

    # Waybar style
    cat > "${config_dir}/waybar/style.css" << 'EOF'
/* Catppuccin Mocha Waybar Theme */
@import "mocha.css";

* {
    font-family: "JetBrainsMono Nerd Font", "Font Awesome 6 Free";
    font-size: 13px;
    min-height: 0;
}

window#waybar {
    background-color: @base;
    color: @text;
    border-bottom: 2px solid @surface0;
}

window#waybar.hidden {
    opacity: 0.2;
}

#workspaces button {
    padding: 0 8px;
    color: @text;
    background-color: transparent;
    border-radius: 0;
}

#workspaces button:hover {
    background: @surface0;
}

#workspaces button.active {
    background-color: @mauve;
    color: @base;
}

#workspaces button.urgent {
    background-color: @red;
    color: @base;
}

#clock,
#battery,
#cpu,
#memory,
#temperature,
#backlight,
#network,
#pulseaudio,
#tray,
#window {
    padding: 0 10px;
    color: @text;
}

#window {
    color: @mauve;
}

#clock {
    color: @rosewater;
    font-weight: bold;
}

#battery {
    color: @green;
}

#battery.charging {
    color: @green;
}

#battery.warning:not(.charging) {
    color: @yellow;
}

#battery.critical:not(.charging) {
    color: @red;
    animation: blink 0.5s linear infinite alternate;
}

@keyframes blink {
    to {
        color: @text;
    }
}

#cpu {
    color: @sapphire;
}

#memory {
    color: @peach;
}

#temperature {
    color: @yellow;
}

#temperature.critical {
    color: @red;
}

#backlight {
    color: @yellow;
}

#network {
    color: @teal;
}

#network.disconnected {
    color: @red;
}

#pulseaudio {
    color: @lavender;
}

#pulseaudio.muted {
    color: @overlay0;
}

#tray {
    color: @text;
}

#tray > .passive {
    -gtk-icon-effect: dim;
}

#tray > .needs-attention {
    -gtk-icon-effect: highlight;
    background-color: @red;
}
EOF

    #==========================================================================
    # WOFI - Catppuccin Mocha CSS
    #==========================================================================
    log_info "Configuring Wofi with Catppuccin Mocha..."

    mkdir -p "${config_dir}/wofi"

    cat > "${config_dir}/wofi/config" << 'EOF'
width=600
height=400
location=center
show=drun
prompt=Search...
filter_rate=100
allow_markup=true
no_actions=true
halign=fill
orientation=vertical
content_halign=fill
insensitive=true
allow_images=true
image_size=32
gtk_dark=true
EOF

    cat > "${config_dir}/wofi/style.css" << 'EOF'
/* Catppuccin Mocha for Wofi */
/* https://github.com/quantumfate/wofi */

@define-color base   #1e1e2e;
@define-color mantle #181825;
@define-color crust  #11111b;

@define-color text     #cdd6f4;
@define-color subtext0 #a6adc8;
@define-color subtext1 #bac2de;

@define-color surface0 #313244;
@define-color surface1 #45475a;
@define-color surface2 #585b70;

@define-color overlay0 #6c7086;
@define-color overlay1 #7f849c;
@define-color overlay2 #9399b2;

@define-color blue      #89b4fa;
@define-color lavender  #b4befe;
@define-color sapphire  #74c7ec;
@define-color sky       #89dceb;
@define-color teal      #94e2d5;
@define-color green     #a6e3a1;
@define-color yellow    #f9e2af;
@define-color peach     #fab387;
@define-color maroon    #eba0ac;
@define-color red       #f38ba8;
@define-color mauve     #cba6f7;
@define-color pink      #f5c2e7;
@define-color flamingo  #f2cdcd;
@define-color rosewater #f5e0dc;

* {
    font-family: "JetBrainsMono Nerd Font", monospace;
    font-size: 14px;
}

window {
    margin: 0px;
    border: 2px solid @mauve;
    border-radius: 10px;
    background-color: @base;
}

#input {
    padding: 10px;
    margin: 10px;
    border: none;
    border-radius: 8px;
    color: @text;
    background-color: @surface0;
}

#input:focus {
    border: 2px solid @mauve;
}

#inner-box {
    margin: 0px 10px 10px 10px;
    background-color: transparent;
}

#outer-box {
    margin: 0px;
    padding: 0px;
    background-color: transparent;
}

#scroll {
    margin: 0px;
    padding: 0px;
}

#text {
    margin: 5px;
    color: @text;
}

#text:selected {
    color: @base;
}

#entry {
    padding: 8px;
    margin: 2px;
    border-radius: 8px;
    background-color: transparent;
}

#entry:selected {
    background-color: @mauve;
    color: @base;
}

#entry:hover {
    background-color: @surface1;
}
EOF

    #==========================================================================
    # MAKO - Catppuccin Mocha notifications
    #==========================================================================
    log_info "Configuring Mako with Catppuccin Mocha..."

    mkdir -p "${config_dir}/mako"

    cat > "${config_dir}/mako/config" << 'EOF'
# Catppuccin Mocha for Mako
# https://github.com/catppuccin/mako

# General
max-visible=5
sort=-time
layer=overlay
anchor=top-right
margin=10
padding=15
width=350
default-timeout=5000

# Appearance
font=JetBrainsMono Nerd Font 11
border-size=2
border-radius=10
icons=1
icon-location=left
max-icon-size=48

# Colors (Catppuccin Mocha)
background-color=#1e1e2e
text-color=#cdd6f4
border-color=#cba6f7
progress-color=over #313244

[urgency=low]
border-color=#313244

[urgency=normal]
border-color=#cba6f7

[urgency=high]
border-color=#f38ba8
default-timeout=0
EOF

    #==========================================================================
    # HYPRLOCK - Catppuccin Mocha lockscreen
    #==========================================================================
    log_info "Configuring Hyprlock with Catppuccin Mocha..."

    cat > "${config_dir}/hypr/hyprlock.conf" << 'EOF'
# Hyprlock Configuration with Catppuccin Mocha
# https://github.com/catppuccin/hyprlock

source = ~/.config/hypr/mocha.conf

$accent = $mauve
$accentAlpha = cba6f7
$font = JetBrainsMono Nerd Font

general {
    disable_loading_bar = true
    hide_cursor = true
    grace = 0
    no_fade_in = false
    no_fade_out = false
}

background {
    monitor =
    path = screenshot
    blur_passes = 3
    blur_size = 8
    color = $base
}

# Time
label {
    monitor =
    text = $TIME
    color = $text
    font_size = 90
    font_family = $font
    position = 0, 200
    halign = center
    valign = center
}

# Date
label {
    monitor =
    text = cmd[update:60000] date +"%A, %d %B"
    color = $text
    font_size = 24
    font_family = $font
    position = 0, 100
    halign = center
    valign = center
}

# User
label {
    monitor =
    text = $USER
    color = $accent
    font_size = 18
    font_family = $font
    position = 0, -50
    halign = center
    valign = center
}

# Password input
input-field {
    monitor =
    size = 300, 50
    outline_thickness = 2
    dots_size = 0.2
    dots_spacing = 0.2
    dots_center = true
    outer_color = $accent
    inner_color = $surface0
    font_color = $text
    fade_on_empty = false
    placeholder_text = <span foreground="##$subtext1">󰌾 Enter Password</span>
    hide_input = false
    check_color = $accent
    fail_color = $red
    fail_text = <i>$FAIL <b>($ATTEMPTS)</b></i>
    fail_transition = 300
    capslock_color = $yellow
    numlock_color = -1
    bothlock_color = -1
    invert_numlock = false
    swap_font_color = false
    position = 0, -150
    halign = center
    valign = center
}
EOF

    #==========================================================================
    # HYPRIDLE - Idle daemon config
    #==========================================================================
    log_info "Configuring Hypridle..."

    cat > "${config_dir}/hypr/hypridle.conf" << 'EOF'
# Hypridle Configuration

general {
    lock_cmd = pidof hyprlock || hyprlock
    before_sleep_cmd = loginctl lock-session
    after_sleep_cmd = hyprctl dispatch dpms on
}

# Screen dim after 2.5 minutes
listener {
    timeout = 150
    on-timeout = brightnessctl -s set 30%
    on-resume = brightnessctl -r
}

# Lock screen after 5 minutes
listener {
    timeout = 300
    on-timeout = loginctl lock-session
}

# Turn off screen after 10 minutes
listener {
    timeout = 600
    on-timeout = hyprctl dispatch dpms off
    on-resume = hyprctl dispatch dpms on
}

# Suspend after 30 minutes
listener {
    timeout = 1800
    on-timeout = loginctl suspend
}
EOF

    #==========================================================================
    # NEOVIM - Catppuccin Mocha with lazy.nvim
    #==========================================================================
    log_info "Configuring Neovim with Catppuccin Mocha..."

    mkdir -p "${config_dir}/nvim"

    cat > "${config_dir}/nvim/init.lua" << 'EOF'
-- Bootstrap lazy.nvim
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not (vim.uv or vim.loop).fs_stat(lazypath) then
    vim.fn.system({
        "git",
        "clone",
        "--filter=blob:none",
        "https://github.com/folke/lazy.nvim.git",
        "--branch=stable",
        lazypath,
    })
end
vim.opt.rtp:prepend(lazypath)

-- Basic settings
vim.g.mapleader = " "
vim.opt.number = true
vim.opt.relativenumber = true
vim.opt.tabstop = 4
vim.opt.shiftwidth = 4
vim.opt.expandtab = true
vim.opt.smartindent = true
vim.opt.wrap = false
vim.opt.termguicolors = true
vim.opt.signcolumn = "yes"
vim.opt.updatetime = 250
vim.opt.clipboard = "unnamedplus"
vim.opt.mouse = "a"

-- Plugins
require("lazy").setup({
    {
        "catppuccin/nvim",
        name = "catppuccin",
        priority = 1000,
        config = function()
            require("catppuccin").setup({
                flavour = "mocha",
                transparent_background = false,
                integrations = {
                    treesitter = true,
                    native_lsp = {
                        enabled = true,
                    },
                },
            })
            vim.cmd.colorscheme("catppuccin")
        end,
    },
})
EOF

    log_success "Neovim configured with Catppuccin Mocha"

    #==========================================================================
    # Set ownership
    #==========================================================================
    run_chroot "chown -R ${USERNAME}:${USERNAME} /home/${USERNAME}/.config"

    log_success "Catppuccin Mocha themes installed for all applications"
}

#==============================================================================
# INSTALL SYSTEM TOOLS
#==============================================================================

install_tools() {
    log_step "Installing System Tools"

    # System logger
    run_chroot "emerge app-admin/sysklogd"
    run_chroot "rc-update add sysklogd default"

    # Btrfs tools
    run_chroot "emerge sys-fs/btrfs-progs"

    # Network (NetworkManager for nmcli/nmtui)
    run_chroot "emerge net-misc/networkmanager"
    run_chroot "rc-update add NetworkManager default"

    # Install base packages
    log_info "Installing base packages..."
    run_chroot "emerge ${BASE_PACKAGES}"

    # Time sync
    run_chroot "rc-update add chronyd default"

    log_success "System tools installed"
}

#==============================================================================
# INSTALL BOOTLOADER
#==============================================================================

install_bootloader() {
    log_step "Installing Bootloader"

    # GRUB for UEFI
    echo 'GRUB_PLATFORMS="efi-64"' >> /mnt/gentoo/etc/portage/make.conf
    run_chroot "emerge sys-boot/grub sys-boot/efibootmgr"

    # Install Catppuccin Mocha GRUB theme
    log_info "Installing Catppuccin Mocha GRUB theme..."
    run_chroot "git clone https://github.com/catppuccin/grub.git /tmp/catppuccin-grub"
    run_chroot "mkdir -p /usr/share/grub/themes"
    run_chroot "cp -r /tmp/catppuccin-grub/src/* /usr/share/grub/themes/"
    run_chroot "rm -rf /tmp/catppuccin-grub"

    # Configure GRUB
    cat >> /mnt/gentoo/etc/default/grub << 'EOF'

# NVIDIA DRM
GRUB_CMDLINE_LINUX="nvidia_drm.modeset=1 nvidia_drm.fbdev=1"

# Catppuccin Mocha theme
GRUB_THEME="/usr/share/grub/themes/catppuccin-mocha-grub-theme/theme.txt"
GRUB_GFXMODE=1920x1080
GRUB_GFXPAYLOAD_LINUX=keep
EOF

    # Ensure GRUB_TERMINAL_OUTPUT is not set (required for theme)
    sed -i 's/^GRUB_TERMINAL_OUTPUT/#GRUB_TERMINAL_OUTPUT/' /mnt/gentoo/etc/default/grub

    # Install GRUB
    run_chroot "grub-install --target=x86_64-efi --efi-directory=/efi --removable"
    run_chroot "grub-mkconfig -o /boot/grub/grub.cfg"

    log_success "Bootloader installed with Catppuccin Mocha theme"
}

#==============================================================================
# CREATE USER ACCOUNT
#==============================================================================

create_user() {
    log_step "Creating User Account"

    # Create user with appropriate groups
    run_chroot "useradd -m -G users,wheel,audio,video,input,usb,portage,plugdev,seat -s /bin/bash ${USERNAME}"

    # Configure doas (sudo alternative)
    cat > /mnt/gentoo/etc/doas.conf << 'EOF'
permit persist :wheel
EOF
    chmod 600 /mnt/gentoo/etc/doas.conf

    # Set ownership of home directory config
    run_chroot "chown -R ${USERNAME}:${USERNAME} /home/${USERNAME}"

    # Create .bash_profile to start Hyprland on login
    cat > "/mnt/gentoo/home/${USERNAME}/.bash_profile" << 'EOF'
# Start Hyprland on TTY1 login
if [ -z "$DISPLAY" ] && [ "$XDG_VTNR" = 1 ]; then
    exec Hyprland
fi
EOF
    run_chroot "chown ${USERNAME}:${USERNAME} /home/${USERNAME}/.bash_profile"

    # Disable root login (user will use doas instead)
    run_chroot "passwd -l root"
    log_info "Root password disabled - use 'doas' for privileged commands"

    log_success "User account created"
    log_warn "Remember to set user password after first boot!"
}

#==============================================================================
# FINALIZE INSTALLATION
#==============================================================================

finalize() {
    log_step "Finalizing Installation"

    # Clean up
    run_chroot "emerge --depclean"

    log_success "Installation finalized"
}

#==============================================================================
# CLEANUP AND UNMOUNT
#==============================================================================

cleanup() {
    log_info "Cleaning up..."

    cd /

    # Unmount everything
    umount -l /mnt/gentoo/dev{/shm,/pts,} 2>/dev/null || true
    umount -R /mnt/gentoo 2>/dev/null || true

    log_success "Cleanup completed"
}

#==============================================================================
# MAIN INSTALLATION FLOW
#==============================================================================

main() {
    # Initialize logging first
    init_logging

    clear
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║         Gentoo Linux Automated Installation Script           ║"
    echo "║                                                              ║"
    echo "║  Target: HP ZBook Power 15.6 G9                              ║"
    echo "║  Config: UEFI + Btrfs + OpenRC + Hyprland + NVIDIA           ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo ""
    echo "This script will:"
    echo "  1. Help you select the correct NVMe drive"
    echo "  2. Partition and format with Btrfs subvolumes"
    echo "  3. Install Gentoo with OpenRC"
    echo "  4. Set up Hyprland (Wayland compositor)"
    echo "  5. Install NVIDIA proprietary drivers"
    echo "  6. Create user account: ${USERNAME}"
    echo ""
    echo -e "${BLUE}Logging to: ${LOG_FILE}${NC}"
    echo -e "${BLUE}Verbose log: ${LOG_VERBOSE}${NC}"
    echo ""

    read -p "Press Enter to continue or Ctrl+C to abort..."

    # Log configuration after user confirms
    log_config

    # Run installation steps
    preflight_checks
    select_disk
    partition_disk
    create_filesystems
    mount_filesystems
    install_stage3
    configure_makeconf
    setup_chroot
    configure_portage
    configure_locale
    configure_fstab
    configure_system
    install_kernel
    install_nvidia
    install_tools
    install_hyprland
    install_catppuccin_themes
    install_bootloader
    create_user
    finalize

    echo ""
    echo -e "${GREEN}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║              Installation Complete!                          ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo ""
    echo "Next steps:"
    echo "  1. Set user password:    chroot /mnt/gentoo passwd ${USERNAME}"
    echo "  2. Reboot:               reboot"
    echo ""
    echo "Note: Root password is disabled. Use 'doas' for privileged commands."
    echo ""
    echo "After reboot:"
    echo "  - Log in as ${USERNAME} on TTY1"
    echo "  - Hyprland will start automatically"
    echo "  - Press Super+Q for terminal (kitty)"
    echo "  - Press Super+R for application launcher (wofi)"
    echo "  - Press Super+C to close window"
    echo "  - Press Super+L to lock screen"
    echo ""

    # Finalize logging
    finalize_log "SUCCESS"

    echo -e "${BLUE}Installation logs saved to:${NC}"
    echo "  - ${LOG_FILE}"
    echo "  - ${LOG_VERBOSE}"
    echo "  - /mnt/gentoo/var/log/gentoo-install/ (after mount)"
    echo ""

    # Prompt for user password
    read -p "Would you like to set ${USERNAME}'s password now? (y/n): " setpw
    if [[ "$setpw" == "y" ]]; then
        echo "Setting ${USERNAME} password:"
        run_chroot "passwd ${USERNAME}"
    fi

    read -p "Would you like to unmount and reboot now? (y/n): " doreboot
    if [[ "$doreboot" == "y" ]]; then
        cleanup
        echo "Rebooting in 5 seconds..."
        sleep 5
        reboot
    fi
}

# Run main function
main "$@"
