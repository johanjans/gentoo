#!/bin/bash

PRIMARY="eDP-1"

get_external() {
    hyprctl monitors all -j | jq -r '.[].name' | grep -v "$PRIMARY" | head -1
}

get_focused() {
    hyprctl monitors -j | jq -r '.[] | select(.focused) | .name'
}

get_resolution() {
    hyprctl monitors -j | jq -r ".[] | select(.name == \"$1\") | \"\(.width)x\(.height)\""
}

is_mirroring() {
    pgrep -x wl-mirror >/dev/null
}

case "$1" in
    toggle)
        if is_mirroring; then
            pkill -x wl-mirror
        else
            ext=$(get_external)
            focused=$(get_focused)
            if [[ -n "$ext" ]]; then
                if [[ "$focused" == "$PRIMARY" ]]; then
                    # Clicked on laptop → mirror laptop to external
                    res=$(get_resolution "$PRIMARY")
                    hyprctl dispatch focusmonitor "$ext"
                    wl-mirror "$PRIMARY" &
                    sleep 0.1
                    hyprctl dispatch fullscreen 0
                    hyprctl dispatch focusmonitor "$PRIMARY"
                    notify-send "🖥️ Mirroring" "Laptop → External ($res)"
                else
                    # Clicked on external → mirror external to laptop
                    res=$(get_resolution "$ext")
                    hyprctl dispatch focusmonitor "$PRIMARY"
                    wl-mirror "$ext" &
                    sleep 0.1
                    hyprctl dispatch fullscreen 0
                    hyprctl dispatch focusmonitor "$ext"
                    notify-send "🖥️ Mirroring" "External → Laptop ($res)"
                fi
            fi
        fi
        pkill -RTMIN+3 waybar
        ;;
    stop)
        pkill -x wl-mirror
        pkill -RTMIN+3 waybar
        ;;
    *)
        monitor_count=$(hyprctl monitors all -j | jq 'length')
        if [[ "$monitor_count" -eq 2 ]]; then
            if is_mirroring; then
                echo '{"text": "󰍹", "tooltip": "🔴 Mirroring active\n\nClick to stop", "class": "mirroring"}'
            else
                echo '{"text": "󰍺", "tooltip": "🖥️ Mirror display\n\nClick to mirror this screen to the other"}'
            fi
        else
            echo '{"text": "", "class": "hidden"}'
        fi
        ;;
esac
