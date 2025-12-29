#!/usr/bin/env bash
#
# Combined system stats module for waybar
# Shows CPU % with tooltip containing temp, RAM, disk, and GPU usage

# CPU usage
cpu=$(awk '/^cpu / {usage=100-($5*100/($2+$3+$4+$5+$6+$7+$8))} END {printf "%.0f", usage}' /proc/stat)

# Temperature (thermal zone 1)
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

# Disk usage (root partition)
read -r disk_used disk_total disk_percent <<< $(df -h / | awk 'NR==2 {gsub(/%/,"",$5); print $3, $2, $5}')

# GPU usage (NVIDIA or AMD)
gpu_usage="N/A"
if command -v nvidia-smi &>/dev/null; then
    gpu_usage=$(nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits 2>/dev/null | head -1)
    gpu_usage="${gpu_usage}%"
elif [[ -f /sys/class/drm/card0/device/gpu_busy_percent ]]; then
    gpu_usage=$(cat /sys/class/drm/card0/device/gpu_busy_percent 2>/dev/null)
    gpu_usage="${gpu_usage}%"
fi

# Build tooltip
tooltip="󰍛 CPU: ${cpu}%\n󰔏 Temperature: ${temp}°C\n󰢮 GPU: ${gpu_usage}\n󰯍 Swap: ${swap_used}/${swap_total_mb} MB (${swap_percent}%)\n󰘚 Memory: ${mem_used}/${mem_total_mb} MB (${mem_percent}%)\n󰋊 Disk: ${disk_used}/${disk_total} (${disk_percent}%)"

# Determine class based on CPU usage
class=""
if (( cpu >= 90 )); then
    class="critical"
elif (( cpu >= 75 )); then
    class="warning"
fi

# Output JSON
printf '{"text": "󰍛 %s%%", "tooltip": "%s", "class": "%s"}\n' "$cpu" "$tooltip" "$class"
