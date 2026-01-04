#!/bin/bash

# Claude Code module for Waybar with usage stats

CREDS_FILE="$HOME/.claude/.credentials.json"
CLAUDE_DIR="/home/johan/claude"

launch_claude() {
    mkdir -p "$CLAUDE_DIR"
    cd "$CLAUDE_DIR" && kitty --class floating-claude -o 'map ctrl+v' -e claude
}

# Handle launch action
if [[ "$1" == "launch" ]]; then
    launch_claude
    exit 0
fi

get_usage() {
    if [[ ! -f "$CREDS_FILE" ]]; then
        echo '{"text": "󰧑", "tooltip": "Claude Code CLI\n\nNot logged in", "class": "claude"}'
        return
    fi

    # Get subscription type
    local plan=$(python3 -c "import json; print(json.load(open('$CREDS_FILE')).get('claudeAiOauth', {}).get('subscriptionType', 'unknown'))" 2>/dev/null)

    # Get access token and fetch usage
    local token=$(python3 -c "import json; print(json.load(open('$CREDS_FILE'))['claudeAiOauth']['accessToken'])" 2>/dev/null)

    if [[ -z "$token" ]]; then
        echo '{"text": "󰧑", "tooltip": "Claude Code CLI\n\nNo token found", "class": "claude"}'
        return
    fi

    local usage=$(curl -s --max-time 5 \
        -H "Accept: application/json" \
        -H "Authorization: Bearer $token" \
        -H "anthropic-beta: oauth-2025-04-20" \
        "https://api.anthropic.com/api/oauth/usage" 2>/dev/null)

    if [[ -z "$usage" ]] || echo "$usage" | grep -q '"error"'; then
        echo '{"text": "󰧑", "tooltip": "Claude Code CLI\n\nCould not fetch usage", "class": "claude"}'
        return
    fi

    # Parse usage data
    local five_hour=$(echo "$usage" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('five_hour',{}).get('utilization', 0))" 2>/dev/null)
    local five_hour_reset=$(echo "$usage" | python3 -c "import sys,json; from datetime import datetime; d=json.load(sys.stdin); t=d.get('five_hour',{}).get('resets_at'); print(datetime.fromisoformat(t.replace('Z','+00:00')).astimezone().strftime('%H:%M') if t else 'N/A')" 2>/dev/null)

    local seven_day=$(echo "$usage" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('seven_day',{}).get('utilization', 0))" 2>/dev/null)
    local seven_day_reset=$(echo "$usage" | python3 -c "import sys,json; from datetime import datetime; d=json.load(sys.stdin); t=d.get('seven_day',{}).get('resets_at'); print(datetime.fromisoformat(t.replace('Z','+00:00')).astimezone().strftime('%a %d %b') if t else 'N/A')" 2>/dev/null)

    # Format plan name
    local plan_display="${plan^}"  # Capitalize first letter

    # Build tooltip
    local tooltip="󰧑 Claude Code CLI\\n\\n"
    tooltip+="📋 Plan: ${plan_display}\\n"
    tooltip+="⏱️ 5-hour: ${five_hour}% (resets ${five_hour_reset})\\n"
    tooltip+="📅 7-day: ${seven_day}% (resets ${seven_day_reset})\\n\\n"
    tooltip+="🖱️ Click to open Claude\\n"
    tooltip+="⚙️ Right-click for settings"

    # Determine class based on usage
    local class="claude"
    local five_int=${five_hour%.*}
    if [[ "$five_int" -ge 80 ]]; then
        class="claude-high"
    elif [[ "$five_int" -ge 50 ]]; then
        class="claude-medium"
    fi

    echo "{\"text\": \"󰧑\", \"tooltip\": \"${tooltip}\", \"class\": \"${class}\"}"
}

get_usage
