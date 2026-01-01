#!/bin/bash

# Hypridle toggle with notifications

is_active() {
    pgrep -x hypridle >/dev/null
}

toggle() {
    if is_active; then
        pkill -x hypridle
        notify-send "☕ Caffeine" "Enabled - Screen will not sleep"
    else
        hypridle &disown
        notify-send "😴 Caffeine" "Disabled - Screen can sleep"
    fi
    pkill -RTMIN+4 waybar
}

case "$1" in
    toggle)
        toggle
        ;;
    *)
        if is_active; then
            echo '{"text": "󰈉", "tooltip": "😴 Caffeine: OFF\n\nScreen will dim and lock after idle timeout.\n\nClick to keep screen awake.", "class": "inactive"}'
        else
            echo '{"text": "󰈈", "tooltip": "☕ Caffeine: ON\n\nScreen will stay awake indefinitely.\nUseful for presentations or watching videos.\n\nClick to restore normal idle behavior.", "class": "active"}'
        fi
        ;;
esac
