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

###############################################################################
# USER PASSWORD
###############################################################################

echo ""
echo "Set password for user '${USERNAME}':"
read -sp "Password: " USER_PASSWORD
echo ""
read -sp "Confirm password: " USER_PASSWORD_CONFIRM
echo ""
[[ "$USER_PASSWORD" == "$USER_PASSWORD_CONFIRM" ]] || die "Passwords do not match"
[[ -n "$USER_PASSWORD" ]] || die "Password cannot be empty"

# Define partition paths
EFI_PART="/dev/${DISK}${PSUF}1"
SWAP_PART="/dev/${DISK}${PSUF}2"
ROOT_PART="/dev/${DISK}${PSUF}3"

###############################################################################
# PARTITIONING
###############################################################################

echo "Creating partitions..."

umount -R /mnt/gentoo 2>/dev/null || true
wipefs -af /dev/$DISK

parted -s /dev/$DISK mklabel gpt \
    mkpart EFI fat32 1M 1G set 1 esp on \
    mkpart swap linux-swap 1G 5G \
    mkpart root btrfs 5G 100%

partprobe /dev/$DISK
sleep 2

###############################################################################
# FILESYSTEMS
###############################################################################

echo "Creating filesystems..."

mkfs.vfat -F32 $EFI_PART
mkswap $SWAP_PART && swapon $SWAP_PART
mkfs.btrfs -f $ROOT_PART

###############################################################################
# BTRFS SUBVOLUMES
###############################################################################

echo "Creating Btrfs subvolumes..."

mount $ROOT_PART /mnt/gentoo
btrfs subvolume create /mnt/gentoo/@
btrfs subvolume create /mnt/gentoo/@home
umount /mnt/gentoo

###############################################################################
# MOUNT FILESYSTEMS
###############################################################################

echo "Mounting filesystems..."

mount -o noatime,compress=zstd,subvol=@ $ROOT_PART /mnt/gentoo
mkdir -p /mnt/gentoo/{home,efi}
mount -o noatime,compress=zstd,subvol=@home $ROOT_PART /mnt/gentoo/home
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
     zstd udisks policykit acpi \
     -systemd -gnome -kde -test -doc"

# Bootloader
GRUB_PLATFORMS="efi-64"
EOF

# Create portage directories
mkdir -p /mnt/gentoo/etc/portage/{package.use,package.license,package.accept_keywords}

# Fix a circular dependency (dracut) and make sure that grub is updated on new kernel install
echo "sys-kernel/installkernel dracut grub" >> /mnt/gentoo/etc/portage/package.use/installkernel

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

chr "emerge --sync"
chr "eselect profile set default/linux/amd64/23.0/desktop" || true

###############################################################################
# USER ACCOUNT
###############################################################################

echo "Creating user account..."

chr "useradd -m -G users,wheel,audio,video,input -s /bin/bash ${USERNAME}"
echo "${USERNAME}:${USER_PASSWORD}" | chr "chpasswd"

# Resolve circular dependency (ok)
chr "USE='-harfbuzz' emerge --oneshot media-libs/freetype"

# Resolve circular dependency (ok)
chr "USE='-tiff' emerge --oneshot media-libs/libwebp"
chr "emerge --oneshot media-libs/tiff"
chr "emerge --oneshot media-libs/libwebp"

# Resolve circular dependency (ok)
chr "USE='-truetype' emerge --oneshot dev-python/pillow"

# Emerge world, but break on errors...
chr "emerge --verbose --update --deep --newuse --backtrack=1000 --complete-graph @world"

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
# Root & Home
UUID=$(blkid -s UUID -o value $ROOT_PART)  /      btrfs  noatime,compress=zstd,subvol=@      0 1
UUID=$(blkid -s UUID -o value $ROOT_PART)  /home  btrfs  noatime,compress=zstd,subvol=@home  0 2

# Swap & EFI
UUID=$(blkid -s UUID -o value $SWAP_PART)  none   swap   sw                                   0 0
UUID=$(blkid -s UUID -o value $EFI_PART)   /efi   vfat   noatime                              0 2
EOF

###############################################################################
# KERNEL
###############################################################################

echo "Installing kernel and firmware..."

chr "emerge --verbose \
    sys-kernel/linux-firmware \
    sys-firmware/intel-microcode \
    sys-firmware/sof-firmware \
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
    media-video/pipewire \
    media-video/wireplumber \
    sys-fs/btrfs-progs \
    app-admin/doas \
    app-admin/sysklogd \
    sys-process/cronie \
    net-misc/chrony \
    app-backup/snapper \
    dev-vcs/git"

# Add user to groups created by installed packages
chr "usermod -aG pipewire,plugdev,usb ${USERNAME}" 2>/dev/null || true

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
# DOAS
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

chr "snapper -c root create-config /"

# Daily cleanup cron job
cat > /mnt/gentoo/etc/cron.daily/snapper << 'EOF'
#!/bin/sh
snapper -c root cleanup number
EOF
chmod +x /mnt/gentoo/etc/cron.daily/snapper

###############################################################################
# BOOTLOADER
###############################################################################

echo "Installing GRUB bootloader..."

chr "emerge --verbose sys-boot/grub sys-boot/efibootmgr"
chr "grub-install --target=x86_64-efi --efi-directory=/efi --removable"
chr "grub-mkconfig -o /boot/grub/grub.cfg"

###############################################################################
# CLEANUP
###############################################################################

echo "Cleaning up..."

chr "emerge --verbose --depclean"

###############################################################################
# DISABLE ROOT LOGIN
###############################################################################

echo "Disabling root login..."

chr "passwd -l root"
chr "usermod -s /sbin/nologin root"

###############################################################################
# DONE
###############################################################################

cat << EOF

================================================================================
                         INSTALLATION COMPLETE
================================================================================

User '${USERNAME}' created with password set.
Root login has been disabled.

Reboot into your new system.

--------------------------------------------------------------------------------
SNAPSHOT COMMANDS
--------------------------------------------------------------------------------

    snapper -c root list              # List snapshots
    snapper -c root create -d "desc"  # Create snapshot before updates
    snapper -c root undochange 1..0   # Revert last change

================================================================================
EOF
