#!/bin/bash

PRIMARY="eDP-1"

get_external() {
    hyprctl monitors all -j | jq -r '.[].name' | grep -v "$PRIMARY" | head -1
}

case "$1" in
    mirror)
        mon=$(get_external)
        [[ -n "$mon" ]] && hyprctl keyword monitor "$mon, preferred, auto, 1, mirror, $PRIMARY"
        ;;
    *)
        if [[ -n "$(get_external)" ]]; then
            echo '{"text": "󰍹", "tooltip": "🖥️ Mirror display\n\n  Click to mirror to external"}'
        else
            echo '{"text": "", "class": "hidden"}'
        fi
        ;;
esac
