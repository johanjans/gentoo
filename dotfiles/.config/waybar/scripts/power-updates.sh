#!/bin/bash
#
# Waybar module for power button with update indicator
# Reads from /var/cache/gentoo-updates (populated by postsync.d hook)
#

CACHE_FILE="/var/cache/gentoo-updates"

shortcuts_header() {
	cat <<'SHORTCUTS'
🖱️ LMB Power Menu  MMB Gentoo News  RMB Update

🚀 <b>APPS</b>
  Super + Q  Terminal (kitty)
  Super + E  File Manager (pcmanfm-qt)
  Super + R  App Launcher (wofi)
  Super + B  Browser (Chrome)
  Super + L  Lock Screen

🪟 <b>WINDOWS</b>
  Super + C       Close Window
  Super + V       Toggle Float
  Super + F       Fullscreen
  Super + P       Pseudo-tile
  Super + J       Toggle Split
  Super + K       Swap Windows
  Super + Arrows  Move Focus
  Alt + Tab       Cycle Windows

🖥️ <b>WORKSPACES</b>
  Super + 1-0        Switch WS
  Super + Shift 1-0  Move to WS
  Super + S          Special WS
  Super + Shift S    Move to Special
  Super + Scroll     Prev/Next WS

🖱️ <b>MOUSE (+ Super)</b>
  LMB  Move Window
  RMB  Resize Window

👆 <b>GESTURES</b>
  3-finger Swipe  Switch WS

📸 <b>SCREENSHOT</b>
  Print        Copy to Clipboard
  Shift Print  Save to ~/Pictures

📋 <b>CLIPBOARD</b>
  Super Ctrl V  Clipboard History
SHORTCUTS
}

display_module() {
	local header
	header=$(shortcuts_header | sed ':a;N;$!ba;s/\n/\\n/g')

	# Check for config files needing dispatch-conf
	local config_files config_warning=""
	config_files=$(find /etc -name "._cfg*" 2>/dev/null | wc -l)
	if ((config_files > 0)); then
		config_warning="\\n⚠️ <b>$config_files config file(s) need merging</b> (dispatch-conf)"
	fi

	# Check if cache exists
	if [[ ! -f "$CACHE_FILE" ]]; then
		echo "{ \"text\": \"⏻\", \"tooltip\": \"No sync data$config_warning\\n\\n$header\", \"class\": \"no-cache\" }"
		return 0
	fi

	# Parse cache header
	local total last_sync
	total=$(grep '^# Total:' "$CACHE_FILE" | cut -d' ' -f3)
	last_sync=$(grep '^# Last sync:' "$CACHE_FILE" | cut -d' ' -f4-)

	total=${total:-0}

	if ((total == 0)); then
		local tooltip="System up to date\\nLast sync: $last_sync$config_warning\\n\\n$header"
		echo "{ \"text\": \"⏻\", \"tooltip\": \"$tooltip\", \"class\": \"no-updates\" }"
		return 0
	fi

	# Build tooltip with update info
	local tooltip="$total updates available\\nLast sync: $last_sync$config_warning\\n\\n$header"

	# Escape quotes for JSON
	tooltip="${tooltip//\"/\\\"}"

	echo "{ \"text\": \"⏻\", \"tooltip\": \"$tooltip\", \"class\": \"updates-available\" }"
}

display_module
