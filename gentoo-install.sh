#!/bin/bash
#
# Gentoo Linux Base System Installation Script
# Based on the Gentoo AMD64 Handbook (December 2025)
#
# Configured for: HP ZBook Power 15.6 G9
# - UEFI boot with Btrfs
# - OpenRC init system
# - Intel + NVIDIA RTX A2000 (proprietary driver)
# - Console-only base system (run desktop-install.sh for Hyprland)
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
# SCRIPT DIRECTORY (for external config files)
#==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIGS_DIR="${SCRIPT_DIR}/configs"

#==============================================================================
# LOGGING SYSTEM
#==============================================================================

# Log file location (created on the live environment, copied to installed system)
# Single log file with human-readable timestamp: gentoo-install_2024-12-28_09-30.log
LOG_DIR="/var/log/gentoo-install"
LOG_TIMESTAMP="$(date '+%Y-%m-%d_%H-%M')"
LOG_FILE="${LOG_DIR}/gentoo-install_${LOG_TIMESTAMP}.log"

# Initialize logging
init_logging() {
    mkdir -p "$LOG_DIR"

    # Create log file with header
    cat > "$LOG_FILE" << EOF
================================================================================
GENTOO INSTALLATION LOG
================================================================================
Started: $(date '+%Y-%m-%d %H:%M:%S')
Script Version: 1.0.0
Host: $(hostname)
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
    echo "[$section] - $(date '+%H:%M:%S')" >> "$LOG_FILE"
    echo "$separator" >> "$LOG_FILE"
    echo "" >> "$LOG_FILE"
}

# Log a subsection
log_subsection() {
    local subsection="$1"
    echo "" >> "$LOG_FILE"
    echo "--- $subsection --- $(date '+%H:%M:%S')" >> "$LOG_FILE"
}

# Log a key-value detail
log_detail() {
    local key="$1"
    local value="$2"
    printf "  %-20s : %s\n" "$key" "$value" >> "$LOG_FILE"
}

# Log a message
log_msg() {
    local level="$1"
    local msg="$2"
    local timestamp=$(date '+%H:%M:%S')
    echo "[$timestamp] [$level] $msg" >> "$LOG_FILE"
}

# Log command execution with output capture
log_cmd() {
    local cmd="$1"
    local description="${2:-Executing command}"
    local timestamp=$(date '+%H:%M:%S')
    local start_time=$(date +%s)

    # Execute and capture output
    local output
    local exit_code
    if output=$(eval "$cmd" 2>&1); then
        exit_code=0
    else
        exit_code=$?
    fi

    local end_time=$(date +%s)
    local duration=$((end_time - start_time))

    # Log result
    if [[ $exit_code -eq 0 ]]; then
        echo "[$timestamp] [OK] $description (${duration}s)" >> "$LOG_FILE"
    else
        echo "[$timestamp] [FAIL] $description (exit: $exit_code)" >> "$LOG_FILE"
        echo "  Command: $cmd" >> "$LOG_FILE"
        echo "  Output: $(echo "$output" | tail -10)" >> "$LOG_FILE"
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

    # Copy log to installed system if mounted
    if [[ -d /mnt/gentoo/var/log ]]; then
        mkdir -p /mnt/gentoo/var/log/gentoo-install
        cp "$LOG_FILE" /mnt/gentoo/var/log/gentoo-install/ 2>/dev/null || true
        log_msg "INFO" "Log copied to /mnt/gentoo/var/log/gentoo-install/"
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

# Base packages (console system with hardware support)
BASE_PACKAGES="
    sys-apps/pciutils
    net-misc/chrony
    dev-vcs/git
    app-admin/doas
    app-editors/neovim
    sys-process/btop
    media-sound/pipewire
    media-video/wireplumber
    net-wireless/bluez
    sys-apps/dbus
    media-libs/fontconfig
"

#==============================================================================
# HELPER FUNCTIONS
#==============================================================================

# Catppuccin Mocha color palette
RED='\033[38;2;243;139;168m'      # #f38ba8
GREEN='\033[38;2;166;227;161m'    # #a6e3a1
YELLOW='\033[38;2;249;226;175m'   # #f9e2af
BLUE='\033[38;2;137;180;250m'     # #89b4fa
CYAN='\033[38;2;148;226;213m'     # #94e2d5 (Teal)
MAUVE='\033[38;2;203;166;247m'    # #cba6f7
PEACH='\033[38;2;250;179;135m'    # #fab387
PINK='\033[38;2;245;194;231m'     # #f5c2e7
TEXT='\033[38;2;205;214;244m'     # #cdd6f4
SUBTEXT='\033[38;2;166;173;200m'  # #a6adc8
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
    local timestamp=$(date '+%H:%M:%S')

    # Capture output for logging
    local output
    local exit_code

    if output=$(chroot /mnt/gentoo /bin/bash -c "source /etc/profile && $cmd" 2>&1); then
        exit_code=0
        echo "[$timestamp] [CHROOT] $cmd" >> "$LOG_FILE"
    else
        exit_code=$?
        echo "[$timestamp] [CHROOT FAIL] $cmd (exit: $exit_code)" >> "$LOG_FILE"
        echo "  Output: $(echo "$output" | tail -5)" >> "$LOG_FILE"
    fi

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
                local home_path=""
                local home_label=""

                # Check for /home/johan or /johan (home partition)
                if [[ -d "$mount_point/home/johan" ]]; then
                    home_path="$mount_point/home/johan"
                    home_label="/home/johan"
                elif [[ -d "$mount_point/johan" ]]; then
                    home_path="$mount_point/johan"
                    home_label="/johan (home partition)"
                fi

                if [[ -n "$home_path" ]]; then
                    found_home=true
                    local file_count=$(find "$home_path" -maxdepth 1 -type f 2>/dev/null | wc -l)
                    local dir_count=$(find "$home_path" -maxdepth 1 -type d 2>/dev/null | wc -l)
                    dir_count=$((dir_count - 1))  # Exclude the directory itself
                    local total_size=$(du -sh "$home_path" 2>/dev/null | cut -f1)

                    echo -e "    ${GREEN}Found ${home_label} on $part_path${NC}"
                    echo -e "    ${TEXT}Size: ${total_size} | Files: ${file_count} | Directories: ${dir_count}${NC}"
                    echo -e "    ${SUBTEXT}Contents:${NC}"

                    # Show directory contents with more detail
                    ls -lah "$home_path" 2>/dev/null | tail -n +2 | while read -r line; do
                        echo -e "      ${TEXT}${line}${NC}"
                    done

                    echo ""
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
    # The file has PGP signature, so we need to extract the actual path (line with .tar.xz)
    local stage3_path=$(wget -qO- "${base_url}/latest-stage3-amd64-openrc.txt" | grep -E '^[0-9]+.*\.tar\.xz' | head -1 | awk '{print $1}')

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

    # Copy from config file and substitute variables
    if [[ -f "${CONFIGS_DIR}/portage/make.conf" ]]; then
        sed -e "s/__MAKE_JOBS__/${MAKE_JOBS}/g" \
            "${CONFIGS_DIR}/portage/make.conf" > "$makeconf"
    else
        log_error "make.conf template not found: ${CONFIGS_DIR}/portage/make.conf"
    fi

    # Create package.use directory
    mkdir -p /mnt/gentoo/etc/portage/package.use
    mkdir -p /mnt/gentoo/etc/portage/package.accept_keywords
    mkdir -p /mnt/gentoo/etc/portage/package.license

    # Temporary flags to break circular dependencies (removed after @world update)
    cat > /mnt/gentoo/etc/portage/package.use/zzz-circular-deps << 'EOF'
# TEMPORARY: Break circular dependencies for initial bootstrap
# These are removed after @world and packages are rebuilt with full features
media-libs/tiff -webp
media-libs/libwebp -tiff
dev-python/pillow -truetype
EOF

    # NVIDIA driver requirements
    cat > /mnt/gentoo/etc/portage/package.use/nvidia << 'EOF'
x11-drivers/nvidia-drivers modules driver
media-libs/mesa -video_cards_nouveau
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

    # Rebuild packages with full features now that circular deps are resolved
    log_info "Removing temporary circular dependency workarounds..."
    run_chroot "rm -f /etc/portage/package.use/zzz-circular-deps"

    log_info "Rebuilding packages with full features..."
    # Only rebuild if packages are actually installed (they may not be yet)
    run_chroot "emerge --oneshot --usepkg=n media-libs/tiff media-libs/libwebp 2>/dev/null" || true
    run_chroot "emerge --oneshot --usepkg=n dev-python/pillow 2>/dev/null" || true

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

    # Copy kernel config script from external file
    cp "${CONFIGS_DIR}/kernel/config.sh" /mnt/gentoo/tmp/kernel_config.sh
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
# INSTALL BASE PACKAGES
#==============================================================================

install_base_packages() {
    log_step "Installing Base Packages"

    log_info "Installing base packages..."
    run_chroot "emerge ${BASE_PACKAGES}"

    # Enable bluetooth service
    run_chroot "rc-update add bluetooth default"

    # Enable dbus (required by many services)
    run_chroot "rc-update add dbus default"

    log_success "Base packages installed"
}

#==============================================================================
# INSTALL USER CONFIGS
#==============================================================================

install_user_configs() {
    log_step "Installing User Configuration Files"

    local config_dir="/mnt/gentoo/home/${USERNAME}/.config"
    mkdir -p "${config_dir}"

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

    # Neovim
    log_info "Installing Neovim config..."
    mkdir -p "${config_dir}/nvim"
    copy_config "${CONFIGS_DIR}/nvim/init.lua" "${config_dir}/nvim/init.lua"

    # btop with Catppuccin theme
    log_info "Installing btop config..."
    mkdir -p "${config_dir}/btop/themes"
    copy_config "${CONFIGS_DIR}/btop/btop.conf" "${config_dir}/btop/btop.conf"
    copy_config "${CONFIGS_DIR}/btop/catppuccin_mocha.theme" "${config_dir}/btop/themes/catppuccin_mocha.theme"

    # Set ownership
    run_chroot "chown -R ${USERNAME}:${USERNAME} /home/${USERNAME}/.config"

    log_success "User configuration files installed"
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

    # Install Catppuccin GRUB theme
    log_info "Installing Catppuccin GRUB theme..."
    local grub_theme_installed=false
    if run_chroot "git clone --depth 1 https://github.com/catppuccin/grub.git /tmp/catppuccin-grub" 2>/dev/null; then
        run_chroot "mkdir -p /usr/share/grub/themes"
        run_chroot "cp -r /tmp/catppuccin-grub/src/* /usr/share/grub/themes/"
        run_chroot "rm -rf /tmp/catppuccin-grub"
        grub_theme_installed=true
        log_info "Catppuccin GRUB theme installed"
    else
        log_warn "Failed to download Catppuccin GRUB theme (network issue?). Continuing without theme."
    fi

    # Configure GRUB for NVIDIA
    cat >> /mnt/gentoo/etc/default/grub << 'EOF'

# NVIDIA DRM
GRUB_CMDLINE_LINUX="nvidia_drm.modeset=1 nvidia_drm.fbdev=1"
EOF

    # Add theme configuration only if theme was installed
    if [[ "$grub_theme_installed" == "true" ]]; then
        cat >> /mnt/gentoo/etc/default/grub << 'EOF'

# Catppuccin Mocha theme
GRUB_THEME="/usr/share/grub/themes/catppuccin-mocha-grub-theme/theme.txt"
GRUB_GFXMODE=1920x1080
GRUB_GFXPAYLOAD_LINUX=keep
EOF
        # Disable terminal output (required for graphical theme)
        sed -i 's/^GRUB_TERMINAL_OUTPUT/#GRUB_TERMINAL_OUTPUT/' /mnt/gentoo/etc/default/grub
    fi

    # Install GRUB
    run_chroot "grub-install --target=x86_64-efi --efi-directory=/efi --removable"
    run_chroot "grub-mkconfig -o /boot/grub/grub.cfg"

    if [[ "$grub_theme_installed" == "true" ]]; then
        log_success "Bootloader installed with Catppuccin theme"
    else
        log_success "Bootloader installed (without theme)"
    fi
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

    # Set ownership of home directory
    run_chroot "chown -R ${USERNAME}:${USERNAME} /home/${USERNAME}"

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
    echo "║         Gentoo Linux Base System Installation Script         ║"
    echo "║                                                              ║"
    echo "║  Target: HP ZBook Power 15.6 G9                              ║"
    echo "║  Config: UEFI + Btrfs + OpenRC + NVIDIA (console only)       ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo ""
    echo "This script will:"
    echo "  1. Help you select the correct NVMe drive"
    echo "  2. Partition and format with Btrfs subvolumes"
    echo "  3. Install Gentoo with OpenRC"
    echo "  4. Install NVIDIA proprietary drivers"
    echo "  5. Create user account: ${USERNAME}"
    echo ""
    echo "Note: This installs a console-only base system."
    echo "      Run desktop-install.sh after first boot for Hyprland/Wayland."
    echo ""
    echo -e "${BLUE}Log file: ${LOG_FILE}${NC}"
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
    install_base_packages
    install_bootloader
    create_user
    install_user_configs
    finalize

    echo ""
    echo -e "${GREEN}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║           Base System Installation Complete!                 ║"
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
    echo "  - Log in as ${USERNAME}"
    echo "  - Connect to network:    nmtui"
    echo "  - Install desktop:       doas ./desktop-install.sh"
    echo ""

    # Finalize logging
    finalize_log "SUCCESS"

    echo -e "${BLUE}Installation log saved to:${NC}"
    echo "  ${LOG_FILE}"
    echo "  (also copied to /mnt/gentoo/var/log/gentoo-install/)"
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
