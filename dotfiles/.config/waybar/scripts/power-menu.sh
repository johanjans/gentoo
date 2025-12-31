#!/usr/bin/env bash
#
# Launch a power menu
#
# Requirements:
# 	- fzf
#
# Author: Jesse Mirabel <sejjymvm@gmail.com>
# Created: August 19, 2025
# License: MIT

fcconf=()
# Get fzf color config
# shellcheck disable=SC1090,SC2154
. ~/.config/waybar/scripts/_fzf_colorizer.sh 2> /dev/null || true
# If the file is missing, fzf will fall back to its default colors

confirm() {
	local action="$1"
	local opts=(
		'--border=sharp'
		"--border-label= Confirm $action? "
		'--height=~100%'
		'--highlight-line'
		'--no-input'
		'--pointer='
		'--reverse'
		"${fcconf[@]}"
	)

	local answer
	answer=$(printf 'Yes\nNo\n' | fzf "${opts[@]}")
	[[ $answer == 'Yes' ]]
}

main() {
	local list=(
		'Reboot'
		'Shutdown'
		'Logout'
		'Suspend'
	)
	local opts=(
		'--border=sharp'
		'--border-label= Power Menu '
		'--height=~100%'
		'--highlight-line'
		'--no-input'
		'--pointer='
		'--reverse'
		"${fcconf[@]}"
	)

	local selected
	selected=$(printf '%s\n' "${list[@]}" | fzf "${opts[@]}")
	case $selected in
		'Shutdown') confirm 'Shutdown' && loginctl poweroff ;;
		'Reboot') confirm 'Reboot' && loginctl reboot ;;
		'Logout') confirm 'Logout' && hyprctl dispatch exit ;;
		'Suspend') loginctl suspend ;;
		*) exit 1 ;;
	esac
}

main
