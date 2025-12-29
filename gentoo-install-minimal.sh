#!/bin/bash
#
# Gentoo Linux Installation Script
# Desktop profile, Btrfs snapshots, Wayland-ready
#
set -e

# Double console font size for readability
setfont -d 2>/dev/null || true

###############################################################################
# CONFIGURATION
###############################################################################

MIRROR="https://ftp.lysator.liu.se/gentoo"
HOSTNAME="gentoo"
TIMEZONE="Europe/Stockholm"
USERNAME="johan"
KEYMAP="sv-latin1"
JOBS=$(nproc)

###############################################################################
# HELPER FUNCTIONS
###############################################################################

die() {
    echo "ERROR: $1"
    exit 1
}

chr() {
    chroot /mnt/gentoo /bin/bash -c "source /etc/profile && $1"
}

###############################################################################
# PRE-FLIGHT CHECKS
###############################################################################

[[ $EUID -eq 0 ]] || die "Run as root"
[[ -d /sys/firmware/efi ]] || die "UEFI required"
ping -c1 gentoo.org &>/dev/null || die "No network"

###############################################################################
# DISK SELECTION
###############################################################################

echo "Available disks:"
lsblk -d -o NAME,SIZE,MODEL | grep -E 'nvme|sd'
echo ""

read -p "Enter disk name (e.g. nvme0n1): " DISK
[[ -b /dev/$DISK ]] || die "Invalid disk"

# Set partition suffix (p for nvme, empty for sata)
[[ $DISK == nvme* ]] && PSUF="p" || PSUF=""

read -p "ERASE /dev/$DISK? Type 'yes' to confirm: " CONFIRM
[[ "$CONFIRM" == "yes" ]] || die "Aborted"

# Define partition paths
EFI_PART="/dev/${DISK}${PSUF}1"
SWAP_PART="/dev/${DISK}${PSUF}2"
ROOT_PART="/dev/${DISK}${PSUF}3"
HOME_PART="/dev/${DISK}${PSUF}4"

###############################################################################
# PARTITIONING
###############################################################################

echo "Creating partitions..."

umount -R /mnt/gentoo 2>/dev/null || true
wipefs -af /dev/$DISK

parted -s /dev/$DISK mklabel gpt \
    mkpart EFI fat32 1M 1G set 1 esp on \
    mkpart swap linux-swap 1G 5G \
    mkpart root btrfs 5G 130G \
    mkpart home btrfs 130G 100%

partprobe /dev/$DISK
sleep 2

###############################################################################
# FILESYSTEMS
###############################################################################

echo "Creating filesystems..."

mkfs.vfat -F32 $EFI_PART
mkswap $SWAP_PART && swapon $SWAP_PART
mkfs.btrfs -f $ROOT_PART
mkfs.btrfs -f $HOME_PART

###############################################################################
# BTRFS SUBVOLUMES
###############################################################################

echo "Creating Btrfs subvolumes..."

# Root partition subvolumes
mount $ROOT_PART /mnt/gentoo
btrfs subvolume create /mnt/gentoo/@
btrfs subvolume create /mnt/gentoo/@snapshots
umount /mnt/gentoo

# Home partition subvolumes
mount $HOME_PART /mnt/gentoo
btrfs subvolume create /mnt/gentoo/@home
btrfs subvolume create /mnt/gentoo/@home-snapshots
umount /mnt/gentoo

###############################################################################
# MOUNT FILESYSTEMS
###############################################################################

echo "Mounting filesystems..."

# Root
mount -o noatime,compress=zstd,subvol=@ $ROOT_PART /mnt/gentoo

# Create mount points
mkdir -p /mnt/gentoo/{home,.snapshots,efi}

# Snapshots, home, EFI
mount -o noatime,compress=zstd,subvol=@snapshots $ROOT_PART /mnt/gentoo/.snapshots
mount -o noatime,compress=zstd,subvol=@home $HOME_PART /mnt/gentoo/home
mkdir -p /mnt/gentoo/home/.snapshots
mount -o noatime,compress=zstd,subvol=@home-snapshots $HOME_PART /mnt/gentoo/home/.snapshots
mount $EFI_PART /mnt/gentoo/efi

###############################################################################
# STAGE3 TARBALL
###############################################################################

echo "Downloading and extracting stage3..."

cd /mnt/gentoo

STAGE3_PATH=$(wget -qO- ${MIRROR}/releases/amd64/autobuilds/latest-stage3-amd64-openrc.txt \
    | grep -oP '^\d+T\d+Z/stage3[^\s]+\.tar\.xz' | head -1)

wget -q --show-progress "${MIRROR}/releases/amd64/autobuilds/${STAGE3_PATH}"
tar xpf stage3*.tar.xz --xattrs-include='*.*' --numeric-owner
rm stage3*.tar.xz

###############################################################################
# PORTAGE CONFIGURATION
###############################################################################

echo "Configuring Portage..."

cat > /mnt/gentoo/etc/portage/make.conf << EOF
# Compiler
COMMON_FLAGS="-march=native -O2 -pipe"
CFLAGS="\${COMMON_FLAGS}"
CXXFLAGS="\${COMMON_FLAGS}"
MAKEOPTS="-j${JOBS}"

# Portage
ACCEPT_LICENSE="*"
GENTOO_MIRRORS="${MIRROR}"

# Localization
L10N="en sv"

# Hardware
VIDEO_CARDS="intel"
INPUT_DEVICES="libinput"

# USE flags (Wayland/Hyprland ready)
USE="bluetooth pipewire networkmanager elogind dbus \
     wayland gles2 opengl vulkan X screencast vaapi \
     zstd -systemd -gnome -kde -doc -test \
     -tiff -webp -freetype -harfbuzz"

# Bootloader
GRUB_PLATFORMS="efi-64"
EOF

# Create portage directories
mkdir -p /mnt/gentoo/etc/portage/{package.use,package.license,package.accept_keywords}

###############################################################################
# CHROOT SETUP
###############################################################################

echo "Setting up chroot environment..."

cp --dereference /etc/resolv.conf /mnt/gentoo/etc/

mount -t proc /proc /mnt/gentoo/proc
mount --rbind /sys /mnt/gentoo/sys
mount --make-rslave /mnt/gentoo/sys
mount --rbind /dev /mnt/gentoo/dev
mount --make-rslave /mnt/gentoo/dev
mount --bind /run /mnt/gentoo/run
mount --make-slave /mnt/gentoo/run

###############################################################################
# PORTAGE SYNC & PROFILE
###############################################################################

echo "Syncing Portage and setting profile..."

chr "emerge-webrsync"
chr "eselect profile set default/linux/amd64/23.0/desktop" || true

# Enable GURU repository for grub-btrfs
chr "emerge --verbose app-eselect/eselect-repository"
chr "eselect repository enable guru"
chr "emerge --sync guru"

echo "Updating @world (this takes a while)..."
chr "emerge --verbose --update --deep --newuse --backtrack=1000 --complete-graph --keep-going @world"

###############################################################################
# LOCALE & TIMEZONE
###############################################################################

echo "Configuring locale and timezone..."

chr "ln -sf /usr/share/zoneinfo/${TIMEZONE} /etc/localtime"
echo "${TIMEZONE}" > /mnt/gentoo/etc/timezone

cat >> /mnt/gentoo/etc/locale.gen << EOF
en_US.UTF-8 UTF-8
sv_SE.UTF-8 UTF-8
EOF

chr "locale-gen"
chr "eselect locale set en_US.utf8" || true
chr "env-update"

###############################################################################
# SYSTEM CONFIGURATION
###############################################################################

echo "Configuring system..."

# Hostname
echo "$HOSTNAME" > /mnt/gentoo/etc/hostname

# Hosts file
cat > /mnt/gentoo/etc/hosts << EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   ${HOSTNAME}
EOF

# Keymap
sed -i "s/keymap=\"us\"/keymap=\"${KEYMAP}\"/" /mnt/gentoo/etc/conf.d/keymaps

###############################################################################
# FSTAB
###############################################################################

echo "Generating fstab..."

cat > /mnt/gentoo/etc/fstab << EOF
# Root
UUID=$(blkid -s UUID -o value $ROOT_PART)  /                 btrfs  noatime,compress=zstd,subvol=@                0 1
UUID=$(blkid -s UUID -o value $ROOT_PART)  /.snapshots       btrfs  noatime,compress=zstd,subvol=@snapshots       0 2

# Home
UUID=$(blkid -s UUID -o value $HOME_PART)  /home             btrfs  noatime,compress=zstd,subvol=@home            0 2
UUID=$(blkid -s UUID -o value $HOME_PART)  /home/.snapshots  btrfs  noatime,compress=zstd,subvol=@home-snapshots  0 2

# Swap & EFI
UUID=$(blkid -s UUID -o value $SWAP_PART)  none              swap   sw                                             0 0
UUID=$(blkid -s UUID -o value $EFI_PART)   /efi              vfat   noatime                                        0 2
EOF

###############################################################################
# KERNEL
###############################################################################

echo "Installing kernel and firmware..."

chr "emerge --verbose \
    sys-kernel/linux-firmware \
    sys-firmware/intel-microcode \
    sys-firmware/sof-firmware \
    sys-kernel/installkernel \
    sys-kernel/gentoo-kernel"

###############################################################################
# SYSTEM PACKAGES
###############################################################################

echo "Installing system packages..."

chr "emerge --verbose \
    sys-auth/elogind \
    sys-apps/dbus \
    net-misc/networkmanager \
    net-wireless/bluez \
    media-sound/pipewire \
    media-video/wireplumber \
    sys-fs/btrfs-progs \
    app-admin/doas \
    app-admin/sysklogd \
    sys-process/cronie \
    net-misc/chrony \
    app-backup/snapper \
    dev-vcs/git"

###############################################################################
# SERVICES
###############################################################################

echo "Enabling services..."

chr "rc-update add elogind boot"
chr "rc-update add dbus default"
chr "rc-update add NetworkManager default"
chr "rc-update add bluetooth default"
chr "rc-update add sysklogd default"
chr "rc-update add cronie default"
chr "rc-update add chronyd default"

###############################################################################
# DOAS (SUDO ALTERNATIVE)
###############################################################################

echo "Configuring doas..."

cat > /mnt/gentoo/etc/doas.conf << 'EOF'
permit persist :wheel
EOF
chmod 600 /mnt/gentoo/etc/doas.conf

###############################################################################
# SNAPPER (BTRFS SNAPSHOTS)
###############################################################################

echo "Configuring Snapper for Btrfs snapshots..."

# Root snapshots
# (Snapper wants to create its own .snapshots subvolume, so we work around it)
umount /mnt/gentoo/.snapshots
chr "snapper -c root create-config /"
chr "btrfs subvolume delete /.snapshots"
mkdir -p /mnt/gentoo/.snapshots
mount -o noatime,compress=zstd,subvol=@snapshots $ROOT_PART /mnt/gentoo/.snapshots

# Home snapshots
umount /mnt/gentoo/home/.snapshots
chr "snapper -c home create-config /home"
chr "btrfs subvolume delete /home/.snapshots"
mkdir -p /mnt/gentoo/home/.snapshots
mount -o noatime,compress=zstd,subvol=@home-snapshots $HOME_PART /mnt/gentoo/home/.snapshots

# Snapper settings
sed -i "s/ALLOW_USERS=\"\"/ALLOW_USERS=\"${USERNAME}\"/" /mnt/gentoo/etc/snapper/configs/home
sed -i 's/TIMELINE_CREATE="yes"/TIMELINE_CREATE="no"/' /mnt/gentoo/etc/snapper/configs/root
sed -i 's/TIMELINE_CREATE="yes"/TIMELINE_CREATE="yes"/' /mnt/gentoo/etc/snapper/configs/home

###############################################################################
# PORTAGE SNAPSHOT HOOKS
###############################################################################

echo "Setting up automatic snapshots for Portage..."

mkdir -p /mnt/gentoo/etc/portage/bashrc.d

# Pre-install snapshot
cat > /mnt/gentoo/etc/portage/bashrc.d/snapper-pre.sh << 'EOF'
if [[ ${EBUILD_PHASE} == "setup" && -z ${SNAPPER_PRE_DONE} ]]; then
    export SNAPPER_PRE_DONE=1
    snapper -c root create -t pre -d "portage: ${CATEGORY}/${PN}" \
        --print-number > /tmp/.snapper_pre_num 2>/dev/null || true
fi
EOF

# Post-install snapshot
cat > /mnt/gentoo/etc/portage/bashrc.d/snapper-post.sh << 'EOF'
if [[ ${EBUILD_PHASE} == "postinst" && -f /tmp/.snapper_pre_num ]]; then
    PRE=$(cat /tmp/.snapper_pre_num)
    snapper -c root create -t post --pre-number="$PRE" \
        -d "portage: ${CATEGORY}/${PN}" 2>/dev/null || true
    rm -f /tmp/.snapper_pre_num
fi
EOF

# Daily cleanup cron job
cat > /mnt/gentoo/etc/cron.daily/snapper << 'EOF'
#!/bin/sh
snapper -c root cleanup number
snapper -c home cleanup number
EOF
chmod +x /mnt/gentoo/etc/cron.daily/snapper

###############################################################################
# BOOTLOADER
###############################################################################

echo "Installing GRUB bootloader..."

# Accept grub-btrfs from GURU
echo "app-backup/grub-btrfs ~amd64" >> /mnt/gentoo/etc/portage/package.accept_keywords/grub-btrfs

chr "emerge --verbose sys-boot/grub sys-boot/efibootmgr"
chr "emerge --verbose app-backup/grub-btrfs" || true

# Catppuccin GRUB theme
echo "Installing Catppuccin GRUB theme..."
chr "git clone --depth1 https://github.com/catppuccin/grub /tmp/catppuccin-grub" || true
chr "mkdir -p /usr/share/grub/themes" || true
chr "cp -r /tmp/catppuccin-grub/src/* /usr/share/grub/themes/" || true

cat >> /mnt/gentoo/etc/default/grub << 'EOF'
GRUB_THEME="/usr/share/grub/themes/catppuccin-mocha-grub-theme/theme.txt"
GRUB_GFXMODE=1920x1080
EOF

chr "grub-install --target=x86_64-efi --efi-directory=/efi --removable"
chr "grub-mkconfig -o /boot/grub/grub.cfg"

###############################################################################
# USER ACCOUNT
###############################################################################

echo "Creating user account..."

chr "useradd -m -G users,wheel,audio,video,pipewire,input,plugdev,usb,bluetooth -s /bin/bash ${USERNAME}"

###############################################################################
# CLEANUP
###############################################################################

echo "Cleaning up..."

chr "emerge --verbose --depclean"

###############################################################################
# DONE
###############################################################################

cat << EOF

================================================================================
                         INSTALLATION COMPLETE
================================================================================

Set passwords:
    chroot /mnt/gentoo passwd
    chroot /mnt/gentoo passwd ${USERNAME}

Then reboot into your new system.

--------------------------------------------------------------------------------
SNAPSHOT COMMANDS
--------------------------------------------------------------------------------

    snapper -c root list              # List system snapshots
    snapper -c home list              # List home snapshots
    snapper -c root undochange 1..0   # Revert last system change
    snapper -c home undochange 1..0   # Revert last home change
    snapper -c root create -d "desc"  # Create manual snapshot

Portage automatically creates pre/post snapshots for each package.
Boot into snapshots via GRUB "Snapshots" menu.

================================================================================
EOF
