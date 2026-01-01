#!/bin/bash

PRIMARY="eDP-1"

get_external() {
    hyprctl monitors all -j | jq -r '.[].name' | grep -v "$PRIMARY" | head -1
}

is_mirroring() {
    pgrep -x wl-mirror >/dev/null
}

case "$1" in
    toggle)
        if is_mirroring; then
            pkill -x wl-mirror
        else
            mon=$(get_external)
            if [[ -n "$mon" ]]; then
                # Save current workspace
                current_ws=$(hyprctl activeworkspace -j | jq -r '.name')
                # Move focus to external monitor, launch wl-mirror fullscreen
                hyprctl dispatch focusmonitor "$mon"
                wl-mirror -F -s cover -s linear "$PRIMARY" &
                sleep 0.2
                # Return to original workspace
                hyprctl dispatch workspace "$current_ws"
            fi
        fi
        pkill -RTMIN+3 waybar
        ;;
    stop)
        pkill -x wl-mirror
        pkill -RTMIN+3 waybar
        ;;
    *)
        if [[ -n "$(get_external)" ]]; then
            if is_mirroring; then
                echo '{"text": "󰍹", "tooltip": "Mirroring active\n\nClick to stop mirroring", "class": "mirroring"}'
            else
                echo '{"text": "󰍺", "tooltip": "Mirror display\n\nClick to mirror to external"}'
            fi
        else
            echo '{"text": "", "class": "hidden"}'
        fi
        ;;
esac
