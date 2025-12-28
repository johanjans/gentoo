#!/bin/bash
#
# Kernel configuration script for HP ZBook Power G9
# Intel i7-12800H (Alder Lake) + NVIDIA RTX A2000
#

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
