# Gentoo Installation Scripts - Development Context

This document provides comprehensive context for continuing development of the Gentoo installation scripts.

## Project Overview

**Purpose**: Automated Gentoo Linux installation scripts tailored for an HP ZBook Power 15.6 G9 laptop.

**Architecture**: Two-stage installation:
1. `gentoo-install.sh` - Base system (boots to console with audio/bluetooth ready)
2. `desktop-install.sh` - Desktop environment (Hyprland/Wayland)

**Target Hardware**:
- CPU: Intel Core i7-12800H (Alder Lake, hybrid P+E cores)
- GPU: Intel integrated + NVIDIA RTX A2000 (proprietary driver)
- Storage: NVMe SSD
- WiFi/Bluetooth: Intel wireless

**Software Stack**:
- Init System: OpenRC (not systemd)
- Desktop: Hyprland (Wayland compositor)
- Terminal: Kitty
- Launcher: Wofi
- Notifications: Mako
- Status Bar: Waybar
- Lock Screen: Hyprlock
- Idle Daemon: Hypridle
- Theme: Catppuccin Mocha (applied to all components)
- Editor: Neovim with lazy.nvim

## Script Locations

```
/home/johan/gentoo/
├── gentoo-install.sh      # Stage 1: Base system (run from live USB)
├── desktop-install.sh     # Stage 2: Desktop environment (run after first boot)
```

## Installation Workflow

```
1. Boot from Gentoo minimal USB
2. Run: ./gentoo-install.sh
   -> Installs base system with audio/bluetooth
   -> Includes Catppuccin GRUB theme
   -> Reboots to installed system

3. Log in as user
4. Connect to network: nmtui
5. Run: doas ./desktop-install.sh
   -> Installs Hyprland/Wayland
   -> Configures Catppuccin theming for apps
   -> Reboots to graphical desktop
```

## Configuration Summary

| Setting | Value |
|---------|-------|
| Boot Mode | UEFI |
| Filesystem | Btrfs with subvolumes (@, @home, @snapshots) |
| EFI Partition | 1GB |
| Swap | 8GB |
| Hostname | gentoo |
| Timezone | Europe/Stockholm |
| Keymap | Swedish (se) |
| Locale | en_US.UTF-8 |
| Username | johan |
| Kernel | Custom compiled (hardware-optimized) |
| CPU Mitigations | Disabled (performance focus) |

## Partitioning Scheme

```
/dev/nvmeXn1p1 (1GB)  - FAT32 - EFI System Partition (/efi)
/dev/nvmeXn1p2 (8GB)  - swap
/dev/nvmeXn1p3 (rest) - Btrfs with subvolumes:
  @           -> /
  @home       -> /home
  @snapshots  -> /.snapshots
```

## USE Flags

### Base System (configs/portage/make.conf)
```bash
USE="vulkan dbus elogind \
     -systemd -gnome -kde -qt5 -X \
     bluetooth networkmanager \
     nvenc vaapi cuda opencl \
     zstd lz4 lto"
```

### Desktop Environment (desktop-install.sh adds)
```bash
USE="wayland ..."
```

## Package Lists

### Base System (gentoo-install.sh)
- sys-apps/pciutils
- net-misc/chrony
- dev-vcs/git
- app-admin/doas
- app-editors/neovim
- sys-process/btop (with Catppuccin theme)
- media-sound/pipewire
- media-video/wireplumber
- net-wireless/bluez
- sys-apps/dbus
- net-misc/networkmanager
- sys-fs/btrfs-progs
- Catppuccin GRUB theme

### Desktop Environment (desktop-install.sh)
- gui-wm/hyprland
- x11-base/xwayland
- gui-apps/waybar
- gui-apps/mako
- gui-apps/grim, slurp, wl-clipboard
- x11-terms/kitty
- x11-misc/wofi
- media-video/playerctl
- gui-libs/xdg-desktop-portal-hyprland
- gui-libs/xdg-desktop-portal-wlr
- sys-apps/xdg-desktop-portal-gtk
- gui-apps/hyprlock, hypridle
- media-fonts/fontawesome
- app-misc/brightnessctl
- sys-auth/elogind, polkit
- JetBrainsMono Nerd Font

## Script Architecture

### Logging System
The base installer creates a single log file in `/var/log/gentoo-install/`:

**gentoo-install_YYYY-MM-DD_HH-MM.log** containing:
- System information
- Configuration values
- Step completion status with timestamps
- Command execution results
- Chroot command logs
- Errors with output context
- Timing information

The log is automatically copied to the installed system at `/mnt/gentoo/var/log/gentoo-install/`.

### gentoo-install.sh Function Flow

```
main()
  -> init_logging()
  -> log_config()
  -> preflight_checks()
  -> select_disk()          # Interactive NVMe selection
  -> partition_disk()       # GPT partitioning
  -> create_filesystems()   # FAT32, swap, Btrfs
  -> mount_filesystems()    # Btrfs subvolumes
  -> install_stage3()       # Download + SHA256 verify
  -> configure_makeconf()   # Copy from configs/portage/make.conf
  -> setup_chroot()         # Mount /proc, /sys, /dev
  -> configure_portage()    # GURU repo, sync, profile
  -> configure_locale()     # Timezone, locale-gen
  -> configure_fstab()      # UUID-based fstab
  -> configure_system()     # Hostname, keymaps, etc.
  -> install_kernel()       # Custom kernel config
  -> install_nvidia()       # Proprietary driver
  -> install_tools()        # System tools
  -> install_base_packages()# Core packages + enable services
  -> install_user_configs() # Neovim config
  -> install_bootloader()   # GRUB + Catppuccin theme
  -> create_user()          # User + doas + lock root
  -> finalize()             # Cleanup
  -> finalize_log()
```

### desktop-install.sh Function Flow

```
main()
  -> preflight_checks()       # Verify running as root, user exists
  -> configure_portage()      # Add wayland USE, Hyprland keywords
  -> install_session()        # elogind, polkit
  -> install_hyprland()       # Hyprland + Wayland packages
  -> install_fonts()          # JetBrainsMono Nerd Font
  -> install_configs()        # Copy config files from configs/
  -> configure_autostart()    # Hyprland autostart in .bash_profile
```

## Custom Kernel Configuration

The kernel is configured for Intel Alder Lake with:

- Hybrid CPU support (P+E cores via Thread Director)
- Intel HFI thermal management
- NVIDIA proprietary driver support (nouveau disabled)
- NVMe and Btrfs built-in (not modules)
- Intel WiFi/Bluetooth
- SOF audio for Alder Lake
- **CPU mitigations disabled** for performance

## NVIDIA Wayland Configuration

Environment variables set in Hyprland config:
```
env = LIBVA_DRIVER_NAME,nvidia
env = XDG_SESSION_TYPE,wayland
env = __GLX_VENDOR_LIBRARY_NAME,nvidia
env = ELECTRON_OZONE_PLATFORM_HINT,auto
```

Kernel parameters (GRUB):
```
nvidia_drm.modeset=1 nvidia_drm.fbdev=1
```

Module loading (OpenRC via /etc/conf.d/modules):
```
modules="nvidia nvidia_modeset nvidia_uvm nvidia_drm"
```

## Catppuccin Mocha Theming

Applied by gentoo-install.sh:
- GRUB bootloader
- btop system monitor
- Neovim (via lazy.nvim)

Applied by desktop-install.sh:
- Hyprland (mocha.conf color definitions)
- Kitty terminal
- Waybar (CSS + config)
- Wofi launcher
- Mako notifications
- Hyprlock lock screen
- Hypridle

## Security Configuration

- **Root password disabled** (`passwd -l root`)
- **doas** configured for wheel group: `permit persist :wheel`
- User groups: users, wheel, audio, video, input, usb, portage, plugdev, seat
- Stage3 verification via SHA256 checksum

## Known Considerations

### OpenRC-specific
- Uses `/etc/conf.d/modules` instead of systemd's `/etc/modules-load.d/`
- Hypridle uses `loginctl suspend` instead of `systemctl suspend`
- Elogind for session management (not systemd-logind)

### Repository
- GURU overlay enabled for Hyprland packages
- Package-specific `~amd64` keywords in `/etc/portage/package.accept_keywords/`

### Font
- JetBrainsMono Nerd Font downloaded directly from GitHub releases
- Installed to `/usr/share/fonts/nerd-fonts/`

## Circular Dependency Handling

The scripts handle known Gentoo circular dependencies during bootstrap. These are
managed via temporary `/etc/portage/package.use/zzz-*` files that are removed after
the initial `@world` update, followed by a rebuild of affected packages with full flags.

### Base System (gentoo-install.sh)

Handled in `/etc/portage/package.use/zzz-circular-deps`:

| Cycle | Packages | Solution |
|-------|----------|----------|
| harfbuzz/freetype | media-libs/harfbuzz ↔ media-libs/freetype | Disable `truetype` on harfbuzz initially |
| webp/tiff | media-libs/libwebp ↔ media-libs/tiff | Disable `webp` on tiff initially |
| openimageio/opencolorio | media-libs/openimageio ↔ media-libs/opencolorio | Disable `color-management` on openimageio initially |
| pillow/freetype | dev-python/pillow ↔ media-libs/freetype | Disable `truetype` on pillow initially |

After `@world` update, these packages are rebuilt with:
```bash
emerge --oneshot --usepkg=n --changed-use \
    media-libs/harfbuzz \
    media-libs/tiff \
    media-libs/libwebp \
    dev-python/pillow
```

### Desktop Environment (desktop-install.sh)

Handled in `/etc/portage/package.use/zzz-desktop-circular-deps`:

| Cycle | Solution |
|-------|----------|
| openimageio/opencolorio | Disable `color-management` on openimageio |
| qt6 multimedia | Disable `qml` on qtmultimedia if needed |

### libglvnd (Modern OpenGL Dispatch)

The scripts use `libglvnd` (GL Vendor-Neutral Dispatch) which is the modern replacement
for `eselect-opengl`. This allows Mesa and NVIDIA drivers to coexist without symlink conflicts.

Configuration in `/etc/portage/package.use/nvidia`:
```bash
media-libs/libglvnd X
media-libs/mesa -video_cards_nouveau
```

### Manual Resolution

If you encounter additional circular dependencies, the general pattern is:
1. Identify the USE flag causing the cycle (check emerge error message)
2. Add temporary disable to `package.use`: `pkg/name -problematic_flag`
3. Run `emerge --update @world`
4. Remove the temporary override
5. Rebuild affected packages: `emerge --oneshot --changed-use pkg1 pkg2`

Reference: [Gentoo Wiki - Circular Dependencies](https://wiki.gentoo.org/wiki/Portage/Help/Circular_dependencies)

## Hyprland Keybindings

| Shortcut | Action |
|----------|--------|
| Super+Q | Open terminal (Kitty) |
| Super+R | Open launcher (Wofi) |
| Super+C | Close window |
| Super+L | Lock screen |
| Super+M | Exit Hyprland |
| Super+V | Toggle floating |
| Super+F | Fullscreen |
| Super+1-9 | Switch workspace |
| Super+Shift+1-9 | Move to workspace |

## Development History

### Issues Fixed
1. **xdg-desktop-portal-hyprland** - Changed from `sys-apps/` to `gui-libs/`
2. **NVIDIA modules for OpenRC** - Changed from `/etc/modules-load.d/` to `/etc/conf.d/modules`
3. **Hypridle suspend** - Changed `systemctl suspend` to `loginctl suspend`
4. **Global ~amd64** - Removed, using package-specific keywords
5. **Stage3 verification** - Added SHA256 checksum verification
6. **USE flags** - Removed `-gtk` (breaks apps), changed `wifi` to `networkmanager`
7. **GURU repository** - Added enable commands
8. **Deprecated env vars** - Removed `GBM_BACKEND`, `WLR_NO_HARDWARE_CURSORS`
9. **Hyprlock variable** - Fixed undefined `$subtext1Alpha`
10. **Neovim vim.loop** - Updated to `(vim.uv or vim.loop)` for compatibility
11. **User groups** - Added `plugdev,seat`
12. **Profile selection** - Made more robust with direct path setting
13. **Kernel debug options** - Removed `BTRFS_FS_CHECK_INTEGRITY`
14. **CPU mitigations** - Simplified to just `CPU_MITIGATIONS`
15. **LINGUAS** - Removed deprecated option
16. **Script separation** - Split into base + desktop installers
17. **make.conf externalized** - Moved to configs/portage/make.conf
18. **Hardware packages in base** - Moved pipewire, wireplumber, bluez to base installer

## Log File Analysis

When analyzing log files for debugging:

1. Check for `[FAIL]` or `[CHROOT FAIL]` entries
2. Look at timestamps to identify slow steps
3. Common issues to look for:
   - emerge failures (circular dependencies, USE conflicts)
   - Kernel config errors
   - Mount/partition issues
   - Network connectivity problems

## Future Improvements

Potential enhancements to consider:
- [ ] Add backup/restore for existing data
- [ ] Support for different GPU configurations
- [ ] Optional Secure Boot support
- [ ] Automated testing framework
- [ ] Support for additional Wayland compositors
- [ ] Disk encryption (LUKS) option
- [ ] Snapshot management with snapper

## File Structure

```
/home/johan/gentoo/
├── gentoo-install.sh          # Stage 1: Base system installer
├── desktop-install.sh         # Stage 2: Desktop environment installer
├── DEVELOPMENT-CONTEXT.md     # This file
├── configs/                   # External configuration files
│   ├── portage/
│   │   └── make.conf          # Portage configuration template
│   ├── btop/
│   │   ├── btop.conf          # btop configuration
│   │   └── catppuccin_mocha.theme  # Catppuccin Mocha theme
│   ├── hypr/
│   │   ├── hyprland.conf      # Hyprland compositor config
│   │   ├── mocha.conf         # Catppuccin Mocha color definitions
│   │   ├── hyprlock.conf      # Lock screen config
│   │   └── hypridle.conf      # Idle daemon config
│   ├── kitty/
│   │   ├── kitty.conf         # Terminal config
│   │   └── mocha.conf         # Catppuccin Mocha theme
│   ├── waybar/
│   │   ├── config             # Status bar config (JSON)
│   │   ├── style.css          # Status bar styling
│   │   └── mocha.css          # Catppuccin Mocha colors
│   ├── wofi/
│   │   ├── config             # App launcher config
│   │   └── style.css          # Catppuccin Mocha styling
│   ├── mako/
│   │   └── config             # Notification daemon config
│   ├── nvim/
│   │   └── init.lua           # Neovim config with lazy.nvim
│   └── kernel/
│       └── config.sh          # Kernel configuration script
└── (logs will be in /var/log/gentoo-install/)
```

## How to Use This Context

When continuing development:

1. Read this document for architecture overview
2. Check the logging system for debugging
3. Refer to the "Issues Fixed" section for known pitfalls
4. Use the function flow to understand execution order
5. Test changes in a VM before running on hardware

## Contact/Attribution

Script developed through iterative conversation, based on:
- Gentoo AMD64 Handbook (December 2025)
- Hyprland Wiki (NVIDIA section)
- Catppuccin GitHub repositories
