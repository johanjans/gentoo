#!/usr/bin/env bash
#
# Network status module for waybar
# Shows WiFi status with ethernet info in tooltip
#

get_wifi_info() {
	local wifi_interface
	wifi_interface=$(nmcli -t -f DEVICE,TYPE device status | grep ':wifi$' | head -1 | cut -d: -f1)

	if [[ -z $wifi_interface ]]; then
		echo "disabled"
		return
	fi

	local status
	status=$(nmcli -t -f DEVICE,STATE device status | grep "^${wifi_interface}:" | cut -d: -f2)

	if [[ $status != "connected" ]]; then
		echo "disconnected"
		return
	fi

	# Get WiFi details
	local essid signal ipaddr cidr
	essid=$(nmcli -t -f active,ssid dev wifi | grep '^yes:' | cut -d: -f2)
	signal=$(nmcli -t -f active,signal dev wifi | grep '^yes:' | cut -d: -f2)
	ipaddr=$(nmcli -t -f IP4.ADDRESS dev show "$wifi_interface" | head -1 | cut -d: -f2 | cut -d/ -f1)
	cidr=$(nmcli -t -f IP4.ADDRESS dev show "$wifi_interface" | head -1 | cut -d: -f2 | cut -d/ -f2)

	echo "connected|$essid|$signal|$ipaddr|$cidr"
}

get_ethernet_info() {
	local eth_lines
	eth_lines=$(nmcli -t -f DEVICE,TYPE,STATE device status | grep ':ethernet:')

	if [[ -z $eth_lines ]]; then
		return
	fi

	local result=""
	local has_connected=false
	while IFS= read -r line; do
		local device state ipaddr
		device=$(echo "$line" | cut -d: -f1)
		state=$(echo "$line" | cut -d: -f3)

		if [[ $state == "connected" ]]; then
			ipaddr=$(nmcli -t -f IP4.ADDRESS dev show "$device" | head -1 | cut -d: -f2)
			result+="🔌 $device ✅\\n🏠 $ipaddr\\n\\n"
			has_connected=true
		elif [[ $state == "disconnected" ]]; then
			result+="🔌 $device ❌\\n\\n"
		fi
		# Skip unavailable interfaces
	done <<< "$eth_lines"

	if [[ $has_connected == true ]] || [[ -n $result ]]; then
		echo "$result"
	fi
}

get_signal_icon() {
	local signal=$1
	if [[ $signal -ge 80 ]]; then
		echo "󰤨"
	elif [[ $signal -ge 60 ]]; then
		echo "󰤥"
	elif [[ $signal -ge 40 ]]; then
		echo "󰤢"
	else
		echo "󰤟"
	fi
}

main() {
	local wifi_info eth_info
	wifi_info=$(get_wifi_info)
	eth_info=$(get_ethernet_info)

	local text tooltip class

	# Build WiFi part of tooltip
	case $wifi_info in
		disabled)
			text="󰤮"
			tooltip="WiFi Disabled"
			class="disabled"
			;;
		disconnected)
			text="󰤯"
			tooltip="🌐 WiFi ❌"
			class="disconnected"
			;;
		connected*)
			IFS='|' read -r _ essid signal ipaddr cidr <<< "$wifi_info"
			local icon
			icon=$(get_signal_icon "$signal")
			text="$icon $essid"
			tooltip="🌐 $essid ✅\n🏠 $ipaddr/$cidr\n📊 $signal%"
			class="connected"
			;;
	esac

	# Add ethernet info to tooltip if available
	if [[ -n $eth_info ]]; then
		# Trim trailing newlines
		eth_info="${eth_info%\\n\\n}"
		tooltip+="\n\n${eth_info}"
	fi

	# Output JSON for waybar
	printf '{"text": "%s", "tooltip": "%s", "class": "%s"}\n' "$text" "$tooltip" "$class"
}

main
