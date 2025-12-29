#!/usr/bin/env bash
#
# Check for official and AUR package updates and upgrade them. When run with the
# 'module' argument, output the status icon and update counts in JSON format for
# Waybar
#
# Requirements:
# 	- checkupdates (pacman-contrib)
# 	- notify-send (libnotify)
# 	- optional: an AUR helper
#
# Author: Jesse Mirabel <sejjymvm@gmail.com>
# Created: August 16, 2025
# License: MIT

GRN='\033[1;32m'
BLU='\033[1;34m'
RST='\033[0m'

TIMEOUT=10
HELPERS=('aura' 'paru' 'pikaur' 'trizen' 'yay')

# Packages that should be highlighted as dangerous (partial matches)
DANGEROUS_PATTERNS=(
	'wayland'
	'hyprland'
	'linux-zen'
	'linux-lts'
	'linux-hardened'
	'nvidia'
	'mesa'
	'vulkan'
	'xorg'
	'systemd'
	'glibc'
	'gcc'
	'pipewire'
	'wireplumber'
	'mkinitcpio'
	'grub'
)

detect-helper() {
	local h
	for h in "${HELPERS[@]}"; do
		if command -v "$h" > /dev/null; then
			helper=$h
			break
		fi
	done
}

check-updates() {
	is_online=true
	repo=0
	aur=0
	repo_packages=""
	aur_packages=""

	local rout rstat
	rout=$(timeout $TIMEOUT checkupdates)
	rstat=$?
	# 2 means no updates are available
	if ((rstat != 0 && rstat != 2)); then
		is_online=false
		return 1
	fi
	repo=$(grep -cve '^\s*$' <<< "$rout")
	repo_packages="$rout"

	if [[ -z $helper ]]; then
		return 0
	fi

	local aout astat
	aout=$(timeout $TIMEOUT "$helper" -Quaq)
	astat=$?
	# Return only if the exit status is non-zero and there is an error
	# message
	if ((${#aout} > 0 && astat != 0)); then
		is_online=false
		return 1
	fi
	aur=$(grep -cve '^\s*$' <<< "$aout")
	aur_packages="$aout"
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
		# Extract package name (first field before space)
		local pkg_name="${line%% *}"
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
	printf '\n%bUpdating pacman packages...%b\n' "$BLU" "$RST"
	sudo pacman -Syu

	if [[ -n $helper ]]; then
		printf '\n%bUpdating AUR packages...%b\n' "$BLU" "$RST"
		"$helper" -Syu
	fi

	notify-send 'Update Complete' -i 'package-install'
	printf '\n%bUpdate Complete!%b\n' "$GRN" "$RST"
	read -rs -n 1 -p 'Press any key to exit...'
}

display-module() {
	if [[ $is_online == false ]]; then
		echo "{ \"text\": \"󰣇\", \"tooltip\": \"Cannot fetch updates\", \"class\": \"offline\" }"
		return 0
	fi

	local total=$((repo + aur))
	if ((total == 0)); then
		echo "{ \"text\": \"󰣇\", \"tooltip\": \"No updates available\\n\\n<i>Middle-click for Arch news</i>\", \"class\": \"updated\" }"
		return 0
	fi

	local tooltip="<b>$total updates available</b>\\n"
	tooltip+="<i>Middle-click for Arch news</i>\\n\\n"

	if ((repo > 0)); then
		tooltip+="<b>Official ($repo)</b>:\\n"
		tooltip+="$(format-package-list "$repo_packages")\\n"
	fi

	if [[ -n $helper ]] && ((aur > 0)); then
		tooltip+="\\n<b>AUR/$helper ($aur)</b>:\\n"
		tooltip+="$(format-package-list "$aur_packages")"
	fi

	# Escape double quotes for JSON
	tooltip="${tooltip//\"/\\\"}"

	echo "{ \"text\": \"󰣇\", \"tooltip\": \"$tooltip\", \"class\": \"updates-available\" }"
}

main() {
	detect-helper

	case $1 in
		'module')
			check-updates
			display-module
			;;
		*)
			printf '%bChecking for updates...%b' "$BLU" "$RST"
			check-updates
			update-packages
			# use signal to update the module
			pkill -RTMIN+1 waybar
			;;
	esac
}

main "$@"
