#!/bin/bash
# Run uxplay and exit cleanly if the window is closed

stdbuf -oL uxplay -p 7000 -n uxp_gentoo -nh -pw 6666 -as 0 -nc -s 2732x2048@60 -vsync no -avdec -nohold -vs waylandsink -h265 2>&1 |
while IFS= read -r line; do
    echo "$line"
    if [[ "$line" == *"Output window was closed"* ]]; then
        pkill -P $$ uxplay 2>/dev/null
        pkill uxplay 2>/dev/null
        exit 0
    fi
done
