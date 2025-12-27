# Gentoo Installation Script - Development Context

This document provides comprehensive context for continuing development of the Gentoo installation script (`gentoo-install.sh`).

## Project Overview

**Purpose**: Automated Gentoo Linux installation script tailored for an HP ZBook Power 15.6 G9 laptop.

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

## Script Location

```
/home/johan/gentoo/gentoo-install.sh
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

## Key USE Flags

```bash
USE="wayland vulkan pipewire pulseaudio dbus elogind \
     -X -systemd -gnome -kde -qt5 \
     bluetooth networkmanager \
     nvenc vaapi cuda opencl \
     zstd lz4 lto"
```

## Package Lists

### Hyprland Stack
- gui-wm/hyprland
- gui-apps/waybar
- gui-apps/mako
- gui-apps/grim, slurp, wl-clipboard
- x11-terms/kitty
- x11-misc/wofi
- media-sound/pipewire
- media-video/wireplumber
- gui-libs/xdg-desktop-portal-hyprland
- gui-libs/xdg-desktop-portal-wlr
- sys-apps/xdg-desktop-portal-gtk
- gui-apps/hyprlock, hypridle
- media-fonts/fontawesome

### Base System
- app-editors/neovim
- sys-apps/pciutils
- net-misc/chrony
- dev-vcs/git
- sys-process/htop
- app-admin/doas
- media-libs/fontconfig

## Script Architecture

### Logging System
The script creates two log files in `/var/log/gentoo-install/`:

1. **install-YYYYMMDD-HHMMSS.log** - Summary log with:
   - System information
   - Configuration values
   - Step completion status
   - Errors and warnings
   - Timing information

2. **install-verbose-YYYYMMDD-HHMMSS.log** - Detailed log with:
   - All command executions
   - Full command output
   - Chroot command logs
   - Exit codes and durations

Logs are automatically copied to the installed system at `/mnt/gentoo/var/log/gentoo-install/`.

### Function Flow

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
  -> configure_makeconf()   # USE flags, CFLAGS, etc.
  -> setup_chroot()         # Mount /proc, /sys, /dev
  -> configure_portage()    # GURU repo, sync, profile
  -> configure_locale()     # Timezone, locale-gen
  -> configure_fstab()      # UUID-based fstab
  -> configure_system()     # Hostname, keymaps, etc.
  -> install_kernel()       # Custom kernel config
  -> install_nvidia()       # Proprietary driver
  -> install_tools()        # Base packages
  -> install_hyprland()     # Wayland stack
  -> install_catppuccin_themes()  # All theming
  -> install_bootloader()   # GRUB + Catppuccin theme
  -> create_user()          # User + doas + lock root
  -> finalize()             # Cleanup
  -> finalize_log()
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

Applied to:
- GRUB bootloader
- Hyprland (mocha.conf color definitions)
- Kitty terminal
- Waybar (CSS + config)
- Wofi launcher
- Mako notifications
- Hyprlock lock screen
- Hypridle
- Neovim (via lazy.nvim)

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

## Log File Analysis

When analyzing log files for debugging:

1. **Summary log** - Check for `[FAIL]` entries and timing
2. **Verbose log** - Full command output for failed steps
3. Look for:
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
├── gentoo-install.sh          # Main installation script
├── DEVELOPMENT-CONTEXT.md     # This file
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
