#!/bin/bash

# Custom mpris module with lowercase output

get_icon() {
    player="$1"
    case "$player" in
        spotify) echo "󰓇" ;;
        firefox*) echo "󰈹" ;;
        chromium*|*chrome*) echo "󰊯" ;;
        vlc) echo "󰕼" ;;
        mpv) echo "󰐌" ;;
        *) echo "󰎈" ;;
    esac
}

status=$(playerctl status 2>/dev/null)
if [ -z "$status" ] || [ "$status" = "Stopped" ]; then
    echo '{"text": "", "class": "stopped"}'
    exit 0
fi

player=$(playerctl metadata --format '{{playerName}}' 2>/dev/null)
artist=$(playerctl metadata artist 2>/dev/null)
title=$(playerctl metadata title 2>/dev/null)
album=$(playerctl metadata album 2>/dev/null)

# Get icon based on player
icon=$(get_icon "$player")
if [ "$status" = "Paused" ]; then
    icon="󰏤"
fi

# Build display text
# YouTube Music has album info, regular YouTube doesn't
if [ -n "$album" ]; then
    # YouTube Music or Spotify - has proper metadata
    if [ -n "$artist" ] && [ -n "$title" ]; then
        display="$artist - $title"
    elif [ -n "$title" ]; then
        display="$title"
    else
        display="$player"
    fi
else
    # Regular YouTube or other - title often contains "Artist - Title"
    # Just use the title as-is
    if [ -n "$title" ]; then
        display="$title"
    elif [ -n "$artist" ]; then
        display="$artist"
    else
        display="$player"
    fi
fi

# Lowercase the display text
display=$(echo "$display" | tr '[:upper:]' '[:lower:]')

# Truncate if too long (like dynamic-len: 40)
if [ ${#display} -gt 40 ]; then
    display="${display:0:37}..."
fi

text="$icon $display"
tooltip="$player: $artist - $title"
class=$(echo "$status" | tr '[:upper:]' '[:lower:]')

printf '{"text": "%s", "tooltip": "%s", "class": "%s"}\n' "$text" "$tooltip" "$class"
