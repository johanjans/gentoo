#!/bin/bash

# UxPlay AirPlay server module for Waybar

UXPLAY_SCRIPT="$HOME/.config/waybar/scripts/start_uxplay.sh"

# Extract settings from the script
get_settings() {
    if [[ -f "$UXPLAY_SCRIPT" ]]; then
        local cmd=$(grep -E "^stdbuf.*uxplay" "$UXPLAY_SCRIPT" | head -1)

        local port=$(echo "$cmd" | grep -oP '(?<=-p )\d+' || echo "7000")
        local name=$(echo "$cmd" | grep -oP '(?<=-n )\S+' || echo "uxplay")
        local res=$(echo "$cmd" | grep -oP '(?<=-s )\S+' || echo "1920x1080")
        local h265=$(echo "$cmd" | grep -q '\-h265' && echo "Yes" || echo "No")
        local audio=$(echo "$cmd" | grep -q '\-as 0' && echo "Off" || echo "On")
        local sink=$(echo "$cmd" | grep -oP '(?<=-vs )\S+' || echo "auto")

        echo "  📛 Name: $name"
        echo "  🔌 Port: $port"
        echo "  📺 Resolution: $res"
        echo "  🎬 H.265/4K: $h265"
        echo "  🔊 Audio: $audio"
        echo "  🖥️ Sink: $sink"
    else
        echo "  Script not found"
    fi
}

is_running() {
    pgrep -x uxplay >/dev/null
}

get_status() {
    local settings=$(get_settings | sed ':a;N;$!ba;s/\n/\\n/g')
    if is_running; then
        local pid=$(pgrep -x uxplay)
        echo "{\"text\": \"󰐌\", \"tooltip\": \"🟢 AirPlay: Running (PID $pid)\\n\\n$settings\", \"class\": \"running\"}"
    else
        echo "{\"text\": \"󱜠\", \"tooltip\": \"⚫ AirPlay: Stopped\\n\\n$settings\\n\\n  🖱️ LMB: Start server\\n  🖱️ RMB: Edit config\", \"class\": \"stopped\"}"
    fi
}

toggle() {
    if is_running; then
        pkill uxplay
        notify-send "󱜠 AirPlay" "Server stopped"
    else
        if [[ -f "$UXPLAY_SCRIPT" ]]; then
            bash "$UXPLAY_SCRIPT" &
            disown
            sleep 1
            if is_running; then
                notify-send "󰐌 AirPlay" "Server started\n\nConnect from your iPad"
            else
                notify-send "󱜠 AirPlay" "Failed to start server" -u critical
            fi
        else
            notify-send "󱜠 AirPlay" "Script not found: $UXPLAY_SCRIPT" -u critical
        fi
    fi
    pkill -RTMIN+5 waybar
}

edit_config() {
    kitty --class floating-editor -e "${EDITOR:-nano}" "$UXPLAY_SCRIPT"
}

case "$1" in
    toggle)
        toggle
        ;;
    edit)
        edit_config
        ;;
    *)
        get_status
        ;;
esac
