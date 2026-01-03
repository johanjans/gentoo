#!/bin/bash

# Presentation Mode - combines DND and screen wake

is_presentation_mode() {
    # Presentation mode is active when DND is on AND hypridle is stopped
    if makoctl mode | grep -q "do-not-disturb" && ! pgrep -x hypridle >/dev/null; then
        return 0
    else
        return 1
    fi
}

enable_presentation() {
    # Enable DND if not already
    if ! makoctl mode | grep -q "do-not-disturb"; then
        makoctl mode -t do-not-disturb
        makoctl dismiss -a
    fi
    # Stop hypridle if running
    pkill -x hypridle 2>/dev/null
    notify-send "🎬 Presentation Mode" "Enabled - Notifications silenced, screen stays awake"
}

disable_presentation() {
    # Disable DND if active
    if makoctl mode | grep -q "do-not-disturb"; then
        makoctl mode -t do-not-disturb
    fi
    # Start hypridle if not running
    if ! pgrep -x hypridle >/dev/null; then
        hypridle &disown
    fi
    notify-send "🎬 Presentation Mode" "Disabled - Normal operation restored"
}

toggle() {
    if is_presentation_mode; then
        disable_presentation
    else
        enable_presentation
    fi
    pkill -RTMIN+2 waybar
}

get_status() {
    if is_presentation_mode; then
        echo '{"text": "󰀏", "tooltip": "🟢 Presentation Mode: ON\n\n🔇 Notifications: silenced\n🔆 Screen: stays awake\n\n🖱️ Click to disable", "class": "active"}'
    else
        echo '{"text": "󰐨", "tooltip": "⚫ Presentation Mode: OFF\n\n🔔 Notifications: enabled\n🌑 Screen: normal idle\n\n🖱️ Click to enable", "class": "inactive"}'
    fi
}

case "$1" in
    toggle)
        toggle
        ;;
    *)
        get_status
        ;;
esac
