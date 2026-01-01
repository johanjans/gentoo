#!/bin/bash

# Do Not Disturb toggle for mako notification daemon

get_status() {
    if makoctl mode | grep -q "do-not-disturb"; then
        echo '{"text": "󰂛", "tooltip": "🔕 Notifications: OFF\n\n  Click to enable", "class": "active"}'
    else
        echo '{"text": "󰂚", "tooltip": "🔔 Notifications: ON\n\n  Click to disable", "class": "inactive"}'
    fi
}

toggle() {
    if makoctl mode | grep -q "do-not-disturb"; then
        # Currently DND, will disable it
        makoctl mode -t do-not-disturb
        pkill -RTMIN+2 waybar
        notify-send "🔔 Notifications" "Enabled - You will receive alerts"
    else
        # Currently normal, will enable DND
        makoctl mode -t do-not-disturb
        makoctl dismiss -a
        pkill -RTMIN+2 waybar
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
