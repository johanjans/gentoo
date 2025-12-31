#!/bin/bash

# Fade hyprsunset temperature gradually
# Usage: hyprsunset-fade.sh <target_temp> [duration_ms] [steps]

TARGET=${1:-6500}
DURATION=${2:-1000}
STEPS=${3:-20}

# Get current temperature from running hyprsunset, default to 6500
CURRENT=$(pgrep -a hyprsunset | grep -oP '(?<=-t )\d+' | head -1)
CURRENT=${CURRENT:-6500}

if [ "$CURRENT" -eq "$TARGET" ]; then
    exit 0
fi

STEP_DELAY=$((DURATION / STEPS))
TEMP_STEP=$(( (TARGET - CURRENT) / STEPS ))

for ((i = 1; i <= STEPS; i++)); do
    if [ $i -eq $STEPS ]; then
        TEMP=$TARGET
    else
        TEMP=$((CURRENT + TEMP_STEP * i))
    fi
    pkill hyprsunset 2>/dev/null
    hyprsunset -t "$TEMP" &
    disown
    sleep "$(echo "scale=3; $STEP_DELAY / 1000" | bc)"
done
