#!/bin/bash

# Time-based blue light filter for hyprsunset
# Adjusts color temperature based on time of day

get_temperature() {
    local hour=$(date +%H)
    hour=$((10#$hour))  # Force base-10 interpretation

    if (( hour >= 6 && hour < 18 )); then
        echo 6500  # Daylight
    elif (( hour >= 18 && hour < 20 )); then
        echo 5000  # Sunset
    elif (( hour >= 20 && hour < 22 )); then
        echo 4000  # Evening
    else
        echo 3500  # Night
    fi
}

set_temperature() {
    local temp=$(get_temperature)
    pkill hyprsunset 2>/dev/null
    hyprsunset -t "$temp" &
    disown
}

# Run once if called directly, or loop if called with --daemon
case "$1" in
    --daemon)
        while true; do
            set_temperature
            sleep 900  # Check every 15 minutes
        done
        ;;
    --get-temp)
        get_temperature
        ;;
    *)
        set_temperature
        ;;
esac
