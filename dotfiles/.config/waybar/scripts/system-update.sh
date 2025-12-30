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
	is_online=true
	update_count=0
	update_packages=""

	# Sync portage tree quietly and check for updates
	if ! emerge --sync -q &>/dev/null; then
		# If sync fails, try to use cached data
		:
	fi

	# Use emerge -puDN @world to check for updates
	local output
	output=$(emerge -puDN @world 2>/dev/null | grep -E "^\[ebuild" | sed 's/\[ebuild[^]]*\] //' | cut -d' ' -f1)

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
	sudo emerge --sync

	printf '\n%bUpdating @world...%b\n' "$BLU" "$RST"
	sudo emerge -avuDN @world

	printf '\n%bCleaning up...%b\n' "$YEL" "$RST"
	sudo emerge --depclean -a

	notify-send 'Update Complete' -i 'package-install'
	printf '\n%bUpdate Complete!%b\n' "$GRN" "$RST"
	read -rs -n 1 -p 'Press any key to exit...'
}

display-module() {
	if [[ $is_online == false ]]; then
		echo "{ \"text\": \"󰣨\", \"tooltip\": \"Cannot fetch updates\", \"class\": \"offline\" }"
		return 0
	fi

	if ((update_count == 0)); then
		echo "{ \"text\": \"󰣨\", \"tooltip\": \"No updates available\\n\\n<i>Middle-click for Gentoo news</i>\", \"class\": \"updated\" }"
		return 0
	fi

	local tooltip="<b>$update_count updates available</b>\\n"
	tooltip+="<i>Middle-click for Gentoo news</i>\\n\\n"
	tooltip+="<b>Packages</b>:\\n"
	tooltip+="$(format-package-list "$update_packages")"

	# Escape double quotes for JSON
	tooltip="${tooltip//\"/\\\"}"

	echo "{ \"text\": \"󰣨\", \"tooltip\": \"$tooltip\", \"class\": \"updates-available\" }"
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
