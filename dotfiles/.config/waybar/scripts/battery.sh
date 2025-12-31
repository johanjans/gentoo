#!/usr/bin/env bash
#
# Custom battery module for waybar
# Shows battery % with tooltip containing system stats

# Battery info
battery_path="/sys/class/power_supply/BAT0"
if [[ ! -d "$battery_path" ]]; then
    battery_path="/sys/class/power_supply/BAT1"
fi

if [[ -d "$battery_path" ]]; then
    capacity=$(cat "$battery_path/capacity" 2>/dev/null || echo "0")
    status=$(cat "$battery_path/status" 2>/dev/null || echo "Unknown")
else
    capacity=0
    status="Unknown"
fi

# Time to empty/full
time_info=""
if command -v upower &>/dev/null; then
    battery_device=$(upower -e | grep BAT | head -1)
    if [[ -n "$battery_device" ]]; then
        if [[ "$status" == "Discharging" ]]; then
            time_info=$(upower -i "$battery_device" | grep "time to empty" | awk '{print $4, $5}')
        elif [[ "$status" == "Charging" ]]; then
            time_info=$(upower -i "$battery_device" | grep "time to full" | awk '{print $4, $5}')
        fi
    fi
fi

# CPU usage (delta between two samples)
read cpu1 <<< $(awk '/^cpu / {print $2+$3+$4+$5+$6+$7+$8+$9+$10+$11, $5}' /proc/stat)
sleep 0.2
read cpu2 <<< $(awk '/^cpu / {print $2+$3+$4+$5+$6+$7+$8+$9+$10+$11, $5}' /proc/stat)
total1=$(echo "$cpu1" | cut -d' ' -f1)
idle1=$(echo "$cpu1" | cut -d' ' -f2)
total2=$(echo "$cpu2" | cut -d' ' -f1)
idle2=$(echo "$cpu2" | cut -d' ' -f2)
total_delta=$((total2 - total1))
idle_delta=$((idle2 - idle1))
if (( total_delta > 0 )); then
    cpu=$(( 100 * (total_delta - idle_delta) / total_delta ))
else
    cpu=0
fi

# Temperature
temp=$(cat /sys/class/thermal/thermal_zone1/temp 2>/dev/null)
temp=$((temp / 1000))

# Swap
read -r swap_total swap_free <<< $(awk '/SwapTotal/ {total=$2} /SwapFree/ {free=$2} END {print total, free}' /proc/meminfo)
swap_used=$(( (swap_total - swap_free) / 1024 ))
swap_total_mb=$(( swap_total / 1024 ))
if (( swap_total > 0 )); then
    swap_percent=$(( (swap_total - swap_free) * 100 / swap_total ))
else
    swap_percent=0
fi

# Memory
read -r mem_total mem_avail <<< $(awk '/MemTotal/ {total=$2} /MemAvailable/ {avail=$2} END {print total, avail}' /proc/meminfo)
mem_used=$(( (mem_total - mem_avail) / 1024 ))
mem_total_mb=$(( mem_total / 1024 ))
mem_percent=$(( (mem_total - mem_avail) * 100 / mem_total ))

# Disk usage
read -r disk_used disk_total disk_percent <<< $(df -h / | awk 'NR==2 {gsub(/%/,"",$5); print $3, $2, $5}')

# GPU usage
gpu_usage="N/A"
if command -v nvidia-smi &>/dev/null; then
    gpu_usage=$(nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits 2>/dev/null | head -1)
    gpu_usage="${gpu_usage}%"
elif [[ -f /sys/class/drm/card0/device/gpu_busy_percent ]]; then
    gpu_usage=$(cat /sys/class/drm/card0/device/gpu_busy_percent 2>/dev/null)
    gpu_usage="${gpu_usage}%"
fi

# Battery icon based on capacity and status
if [[ "$status" == "Charging" ]]; then
    icon="󰉁"
else
    if (( capacity >= 95 )); then icon="󰁹"
    elif (( capacity >= 85 )); then icon="󰂂"
    elif (( capacity >= 75 )); then icon="󰂁"
    elif (( capacity >= 65 )); then icon="󰂀"
    elif (( capacity >= 55 )); then icon="󰁿"
    elif (( capacity >= 45 )); then icon="󰁾"
    elif (( capacity >= 35 )); then icon="󰁽"
    elif (( capacity >= 25 )); then icon="󰁼"
    elif (( capacity >= 15 )); then icon="󰁻"
    else icon="󰂎"
    fi
fi

# Build tooltip with battery info first, then system stats
tooltip="󰁹 Battery: ${capacity}% (${status})"
if [[ -n "$time_info" ]]; then
    tooltip="${tooltip}\n󱧥 Time: ${time_info}"
fi
tooltip="${tooltip}\n\n󰍛 CPU: ${cpu}%\n󰔏 Temperature: ${temp}°C\n󰢮 GPU: ${gpu_usage}\n󰯍 Swap: ${swap_used}/${swap_total_mb} MB (${swap_percent}%)\n󰘚 Memory: ${mem_used}/${mem_total_mb} MB (${mem_percent}%)\n󰋊 Disk: ${disk_used}/${disk_total} (${disk_percent}%)"

# Determine class based on battery level
class=""
if (( capacity <= 10 )); then
    class="critical"
elif (( capacity <= 20 )); then
    class="warning"
fi

# Output JSON
printf '{"text": "%s %s%%", "tooltip": "%s", "class": "%s"}\n' "$icon" "$capacity" "$tooltip" "$class"
