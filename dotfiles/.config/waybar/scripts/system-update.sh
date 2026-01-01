#!/usr/bin/env bash
#
# Check for Gentoo package updates and upgrade them. When run with the
# 'module' argument, output the status icon and update counts in JSON format for
# Waybar
#
# Requirements:
# 	- eix (for eix-diff to check updates)
# 	- notify-send (libnotify)
#
# Author: Jesse Mirabel <sejjymvm@gmail.com> (original Arch version)
# Modified for Gentoo
# License: MIT

GRN='\033[1;32m'
BLU='\033[1;34m'
YEL='\033[1;33m'
RST='\033[0m'

# Packages that should be highlighted as dangerous (partial matches)
DANGEROUS_PATTERNS=(
	'wayland'
	'hyprland'
	'gentoo-sources'
	'linux-firmware'
	'nvidia'
	'mesa'
	'vulkan'
	'xorg'
	'openrc'
	'glibc'
	'gcc'
	'pipewire'
	'wireplumber'
	'grub'
	'efibootmgr'
)

check-updates() {
	update_count=0
	update_packages=""

	# Use eix to check for upgradable packages (fast, uses cached database)
	local output
	output=$(eix -u --format '<category>/<name>\n' 2>/dev/null | grep -v '^Found [0-9]* match')

	if [[ -z "$output" ]]; then
		update_count=0
		return 0
	fi

	update_count=$(echo "$output" | grep -cve '^\s*$')
	update_packages="$output"
}

is-dangerous() {
	local pkg="$1"
	local pattern
	for pattern in "${DANGEROUS_PATTERNS[@]}"; do
		if [[ "$pkg" == *"$pattern"* ]]; then
			return 0
		fi
	done
	return 1
}

format-package-list() {
	local packages="$1"
	local formatted=""

	while IFS= read -r line; do
		[[ -z "$line" ]] && continue
		# Extract package name
		local pkg_name="${line##*/}"  # Remove category/
		if is-dangerous "$pkg_name"; then
			formatted+="<span color='#f38ba8'>⚠ $line</span>\\n"
		else
			formatted+="  $line\\n"
		fi
	done <<< "$packages"

	# Remove trailing \n
	formatted="${formatted%\\n}"
	echo "$formatted"
}

update-packages() {
	printf '\n%bSyncing Portage tree...%b\n' "$BLU" "$RST"
	doas eix-sync

	printf '\n%bUpdating @world...%b\n' "$BLU" "$RST"
	doas emerge -avuDN @world

	printf '\n%bCleaning up...%b\n' "$YEL" "$RST"
	doas emerge --depclean -a

	notify-send 'Update Complete' -i 'package-install'
	printf '\n%bUpdate Complete!%b\n' "$GRN" "$RST"
	read -rs -n 1 -p 'Press any key to exit...'
}

shortcuts-header() {
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

count-package-types() {
	selected_count=0
	dependency_count=0

	while IFS= read -r line; do
		[[ -z "$line" ]] && continue
		local pkg_name="${line##*/}"
		if is-dangerous "$pkg_name"; then
			((selected_count++))
		else
			((dependency_count++))
		fi
	done <<< "$update_packages"
}

display-module() {
	local header
	header=$(shortcuts-header | sed ':a;N;$!ba;s/\n/\\n/g')

	if ((update_count == 0)); then
		echo "{ \"text\": \"󰣨\", \"tooltip\": \"$header\" }"
		return 0
	fi

	# Count selected vs dependency packages
	count-package-types

	local tooltip="📦 $update_count updates"
	if ((selected_count > 0)); then
		tooltip+=" (⚠️ $selected_count critical"
		if ((dependency_count > 0)); then
			tooltip+=", $dependency_count deps"
		fi
		tooltip+=")"
	elif ((dependency_count > 0)); then
		tooltip+=" ($dependency_count deps)"
	fi
	tooltip+="\\n\\n"
	tooltip+="$header"

	# Escape double quotes for JSON
	tooltip="${tooltip//\"/\\\"}"

	# Red for critical updates, yellow for deps only
	local class="updates-deps"
	if ((selected_count > 0)); then
		class="updates-critical"
	fi

	echo "{ \"text\": \"󰣨\", \"tooltip\": \"$tooltip\", \"class\": \"$class\" }"
}

main() {
	case $1 in
		'module')
			check-updates
			display-module
			;;
		*)
			printf '%bChecking for updates...%b\n' "$BLU" "$RST"
			check-updates
			update-packages
			# use signal to update the module
			pkill -RTMIN+1 waybar
			;;
	esac
}

main "$@"
