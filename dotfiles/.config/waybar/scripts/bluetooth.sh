#!/usr/bin/env bash
#
# Scan, select, pair, and connect to Bluetooth devices
#
# Requirements:
# 	- bluetoothctl (bluez-utils)
# 	- fzf
# 	- notify-send (libnotify)
#
# Author: Jesse Mirabel <sejjymvm@gmail.com>
# Created: August 19, 2025
# License: MIT

fcconf=()
# Get fzf color config
# shellcheck disable=SC1090,SC2154
. ~/.config/waybar/scripts/_fzf_colorizer.sh 2> /dev/null || true
# If the file is missing, fzf will fall back to its default colors

RED='\033[1;31m'
RST='\033[0m'

TIMEOUT=5

ensure-on() {
	local status
	status=$(bluetoothctl show | awk '/PowerState/ {print $2}')

	case $status in
		'off') bluetoothctl power on > /dev/null ;;
		'off-blocked')
			rfkill unblock bluetooth

			local i new_status
			for ((i = 1; i <= TIMEOUT; i++)); do
				printf '\rUnblocking Bluetooth... (%d/%d)' $i $TIMEOUT

				new_status=$(bluetoothctl show | awk '/PowerState/ {print $2}')
				if [[ $new_status == 'on' ]]; then
					break
				fi
				sleep 1
			done

			# Bluetooth could be hard blocked
			if [[ $new_status != 'on' ]]; then
				notify-send 'Bluetooth' 'Failed to unblock' -i 'package-purge'
				return 1
			fi
			;;
		*) return 0 ;;
	esac

	notify-send 'Bluetooth On' -i 'network-bluetooth-activated' -h string:x-canonical-private-synchronous:bluetooth
}

get-device-list() {
	bluetoothctl --timeout $TIMEOUT scan on > /dev/null &

	local i num
	for ((i = 1; i <= TIMEOUT; i++)); do
		printf '\rScanning for devices... (%d/%d)' $i $TIMEOUT
		printf '\n%bPress [q] to stop%b\n\n' "$RED" "$RST"

		num=$(bluetoothctl devices | grep -c 'Device')
		printf '\rDevices: %s' "$num"
		printf '\033[3A'

		read -rs -n 1 -t 1
		if [[ $REPLY == [Qq] ]]; then
			break
		fi
	done
	printf '\n%bScanning stopped.%b\n\n' "$RED" "$RST"

	list=$(bluetoothctl devices | sed 's/^Device //')

	if [[ -z $list ]]; then
		notify-send 'Bluetooth' 'No devices found' -i 'package-broken'
		return 1
	fi
}

select-device() {
	local header
	header=$(printf '%-17s %s' 'Address' 'Name')
	local opts=(
		'--border=sharp'
		'--border-label= Connect to Device '
		'--ghost=Search'
		"--header=$header"
		'--height=~100%'
		'--highlight-line'
		'--info=inline-right'
		'--pointer='
		'--reverse'
		"${fcconf[@]}"
	)

	address=$(fzf "${opts[@]}" <<< "$list" | awk '{print $1}')
	if [[ -z $address ]]; then
		return 1
	fi

	local connected
	connected=$(bluetoothctl info "$address" | awk '/Connected/ {print $2}')
	if [[ $connected == 'yes' ]]; then
		notify-send 'Bluetooth' 'Already connected to this device' \
			-i 'package-install'
		return 1
	fi
}

pair-and-connect() {
	# Check if already paired - if so, just connect
	local paired
	paired=$(bluetoothctl info "$address" 2>/dev/null | awk '/Paired/ {print $2}')

	if [[ $paired == 'yes' ]]; then
		printf 'Already paired, connecting...'
	else
		printf 'Pairing...'
		# Enable pairable mode and use agent for proper bonding
		bluetoothctl pairable on > /dev/null
		if ! timeout $((TIMEOUT * 2)) bluetoothctl --agent=NoInputNoOutput pair "$address" > /dev/null 2>&1; then
			notify-send 'Bluetooth' 'Failed to pair' -i 'package-purge'
			return 1
		fi
	fi

	printf '\nTrusting...'
	bluetoothctl trust "$address" > /dev/null

	printf '\nConnecting...'
	if ! timeout $TIMEOUT bluetoothctl connect "$address" > /dev/null; then
		notify-send 'Bluetooth' 'Failed to connect' -i 'package-purge'
		return 1
	fi

	notify-send 'Bluetooth' 'Successfully connected' -i 'package-install'
}

get-known-devices() {
	local connected paired addr
	declare -A connected_map

	# Get connected devices
	while read -r addr _; do
		[[ -n $addr ]] && connected_map[$addr]=1
	done < <(bluetoothctl devices Connected | sed 's/^Device //')

	# Build list with status indicators
	list=""
	while read -r line; do
		[[ -z $line ]] && continue
		addr=${line%% *}
		name=${line#* }
		if [[ -n ${connected_map[$addr]} ]]; then
			list+=$(printf '%-17s   %-10s %s\n' "$addr" "connected" "$name")
		else
			list+=$(printf '%-17s   %-10s %s\n' "$addr" "paired" "$name")
		fi
	done < <(bluetoothctl devices Paired | sed 's/^Device //')

	list=${list%$'\n'}  # Remove trailing newline

	if [[ -z $list ]]; then
		notify-send 'Bluetooth' 'No known devices' -i 'network-bluetooth'
		return 1
	fi
}

select-known-device() {
	local header
	header=$(printf '%-17s   %-10s %s\n%-17s   %-10s %s' 'Address' 'Status' 'Name' 'Click: disconnect' '' 'Right-click: forget')
	local opts=(
		'--border=sharp'
		'--border-label= Manage Devices '
		'--ghost=Search'
		"--header=$header"
		'--height=~100%'
		'--highlight-line'
		'--info=inline-right'
		'--pointer='
		'--reverse'
		'--bind=right-click:execute-silent(bluetoothctl disconnect {1} 2>/dev/null; bluetoothctl remove {1})+abort'
		"${fcconf[@]}"
	)

	address=$(fzf "${opts[@]}" <<< "$list" | awk '{print $1}')
	if [[ -z $address ]]; then
		return 1
	fi
}

disconnect-device() {
	local name
	name=$(bluetoothctl info "$address" | awk -F': ' '/Name/ {print $2}')

	printf 'Disconnecting %s...\n' "$name"
	if ! timeout $TIMEOUT bluetoothctl disconnect "$address" > /dev/null; then
		notify-send 'Bluetooth' "Failed to disconnect $name" -i 'package-purge'
		return 1
	fi
	notify-send 'Bluetooth' "Disconnected $name" -i 'network-bluetooth'
}

connect-mode() {
	tput civis
	ensure-on || exit 1
	get-device-list || exit 1
	tput cnorm
	select-device || exit 1
	pair-and-connect || exit 1
}

disconnect-mode() {
	get-known-devices || exit 1
	select-known-device || exit 1
	disconnect-device || exit 1
}

main() {
	case $1 in
		'disconnect') disconnect-mode ;;
		*) connect-mode ;;
	esac
}

main "$@"
