#!/bin/bash

# Display Mode Toggle - Switch between Extend and Mirror modes for Hyprland
# State file to track current mode
STATE_FILE="${XDG_RUNTIME_DIR:-/tmp}/display-mode-state"

# Primary monitor (laptop)
PRIMARY="eDP-1"

# Get list of currently connected external monitors
get_connected_monitors() {
    hyprctl monitors -j | jq -r '.[].name' | grep -v "$PRIMARY"
}

# Get current mode from state file
get_mode() {
    if [[ -f "$STATE_FILE" ]] && grep -q "mirror" "$STATE_FILE"; then
        echo "mirror"
    else
        echo "extend"
    fi
}

# Set extend mode - restore monitors to their configured positions
set_extend() {
    # Dock monitors
    hyprctl keyword monitor "DP-6, 1920x1080@120, 1920x0, 1.0"
    hyprctl keyword monitor "DP-5, 1920x1080@120, 3840x0, 1.0"
    hyprctl keyword monitor "DP-7, 1920x1200@120, 5760x0, 1.0"

    # External monitors (TVs)
    hyprctl keyword monitor "DP-1, 1920x1080@120, 1920x0, 1.0"
    hyprctl keyword monitor "HDMI-A-1, 1920x1080@120, 1920x0, 1.0"

    echo "extend" > "$STATE_FILE"
}

# Set mirror mode - all monitors mirror the primary
set_mirror() {
    for mon in $(get_connected_monitors); do
        hyprctl keyword monitor "$mon, preferred, auto, 1, mirror, $PRIMARY"
    done

    echo "mirror" > "$STATE_FILE"
}

# Toggle between modes
toggle() {
    if [[ "$(get_mode)" == "extend" ]]; then
        set_mirror
    else
        set_extend
    fi
}

# Output JSON for waybar
get_status() {
    local mode=$(get_mode)
    local connected=$(get_connected_monitors | wc -l)

    # Hide widget when no external monitors connected
    if [[ "$connected" -eq 0 ]]; then
        echo "{\"text\": \"\", \"tooltip\": \"\", \"class\": \"hidden\"}"
        return
    fi

    if [[ "$mode" == "mirror" ]]; then
        echo "{\"text\": \"󰍹\", \"tooltip\": \"Display: Mirror ($connected external)\nClick to extend\", \"class\": \"mirror\"}"
    else
        echo "{\"text\": \"󰍺\", \"tooltip\": \"Display: Extend ($connected external)\nClick to mirror\", \"class\": \"extend\"}"
    fi
}

case "$1" in
    toggle)
        toggle
        ;;
    extend)
        set_extend
        ;;
    mirror)
        set_mirror
        ;;
    *)
        get_status
        ;;
esac
