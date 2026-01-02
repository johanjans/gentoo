#!/usr/bin/env bash
#
# Select and apply monitor profiles for external displays (TVs/projectors)
#
# Requirements:
#   - fzf
#   - jq
#   - hyprctl
#
# Usage:
#   monitor-profile.sh          # Launch fzf selector
#   monitor-profile.sh status   # Waybar JSON output

PRIMARY="eDP-1"

fcconf=()
# Get fzf color config
# shellcheck disable=SC1090,SC2154
. ~/.config/waybar/scripts/_fzf_colorizer.sh 2>/dev/null || true

get_external_monitors() {
    hyprctl monitors -j | jq -r ".[].name" | grep -v "$PRIMARY"
}

get_monitor_info() {
    local monitor="$1"
    hyprctl monitors -j | jq -r ".[] | select(.name == \"$monitor\") | \"\(.width)x\(.height)@\(.refreshRate | floor)Hz scale:\(.scale)\""
}

get_available_modes() {
    local monitor="$1"
    # Standard resolutions and refresh rates only
    local res_pattern="^(3840x2160|2560x1440|1920x1080)@"
    local rate_pattern="@(59|60|100|119|120|144|165|240)\."

    local modes
    modes=$(hyprctl monitors -j | jq -r ".[] | select(.name == \"$monitor\") | .availableModes[]" \
        | grep -E "$res_pattern" \
        | grep -E "$rate_pattern" \
        | sort -t'@' -k1,1 -k2 -rn \
        | uniq)

    # Filter out 59.xx if 60.xx exists for same resolution, same for 119/120
    echo "$modes" | while read -r mode; do
        res="${mode%%@*}"
        rate="${mode#*@}"
        case "$rate" in
            59.*)
                echo "$modes" | grep -q "^${res}@60\." || echo "$mode" ;;
            119.*)
                echo "$modes" | grep -q "^${res}@120\." || echo "$mode" ;;
            *)
                echo "$mode" ;;
        esac
    done
}

get_scale_for_resolution() {
    local width="$1"
    case "$width" in
        3840|4096) echo "2" ;;
        2560)      echo "1.333333" ;;
        *)         echo "1" ;;
    esac
}

apply_profile() {
    local monitor="$1"
    local resolution="$2"
    local scale="$3"

    # Get current position
    local pos
    pos=$(hyprctl monitors -j | jq -r ".[] | select(.name == \"$monitor\") | \"\(.x)x\(.y)\"")

    hyprctl keyword monitor "$monitor,$resolution,$pos,$scale"
}

select_mode() {
    local monitor="$1"
    local opts=(
        '--border=sharp'
        "--border-label= Modes for $monitor "
        '--height=~100%'
        '--highlight-line'
        '--no-input'
        '--pointer='
        '--reverse'
        "${fcconf[@]}"
    )

    get_available_modes "$monitor" | fzf "${opts[@]}"
}

select_monitor() {
    local monitors=("$@")

    if [[ ${#monitors[@]} -eq 1 ]]; then
        echo "${monitors[0]}"
        return
    fi

    local opts=(
        '--border=sharp'
        '--border-label= Select Monitor '
        '--height=~100%'
        '--highlight-line'
        '--no-input'
        '--pointer='
        '--reverse'
        "${fcconf[@]}"
    )

    printf '%s\n' "${monitors[@]}" | fzf "${opts[@]}"
}

main() {
    # Get external monitors
    mapfile -t externals < <(get_external_monitors)

    if [[ ${#externals[@]} -eq 0 ]]; then
        notify-send "Monitor Profile" "No external monitors connected"
        exit 1
    fi

    # Select monitor if multiple
    local monitor
    monitor=$(select_monitor "${externals[@]}")
    [[ -z "$monitor" ]] && exit 1

    # Select mode from available modes
    local selected
    selected=$(select_mode "$monitor")
    [[ -z "$selected" ]] && exit 1

    # Extract width from mode (e.g., "1920x1080@60Hz" -> "1920")
    local width="${selected%%x*}"
    local scale
    scale=$(get_scale_for_resolution "$width")

    # Convert mode format: "1920x1080@60Hz" -> "1920x1080@60"
    local resolution="${selected%Hz}"

    apply_profile "$monitor" "$resolution" "$scale"
    notify-send "Monitor Profile" "$monitor: $selected (scale: $scale)"
}

case "$1" in
    status)
        # Waybar JSON output
        externals=$(get_external_monitors)
        if [[ -n "$externals" ]]; then
            monitor=$(echo "$externals" | head -1)
            info=$(get_monitor_info "$monitor")
            echo "{\"text\": \"󰍹\", \"tooltip\": \"External: $monitor\\n$info\\n\\nClick to change profile\"}"
        else
            echo '{"text": "", "class": "hidden"}'
        fi
        ;;
    *)
        main
        ;;
esac
