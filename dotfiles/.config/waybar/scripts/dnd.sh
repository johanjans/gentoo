#!/bin/bash

# Do Not Disturb toggle for mako notification daemon

get_status() {
    if makoctl mode | grep -q "do-not-disturb"; then
        echo '{"text": "󰂛", "tooltip": "toggle all notifications on/off", "class": "active"}'
    else
        echo '{"text": "󰂚", "tooltip": "toggle all notifications on/off", "class": "inactive"}'
    fi
}

toggle() {
    makoctl mode -t do-not-disturb
    # Dismiss all visible notifications when enabling DND
    if makoctl mode | grep -q "do-not-disturb"; then
        makoctl dismiss -a
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
