#!/usr/bin/env bash
#
# Connect to eduroam (Jönköping University)
#
# Creates the connection profile if it doesn't exist, then connects.
# Uses PEAP/MSCHAPv2 authentication as required by JU.
#

set -euo pipefail

IDENTITY="janjoh@ju.se"
CON_NAME="eduroam"
SSID="eduroam"

connection_exists() {
	nmcli connection show "$CON_NAME" &>/dev/null
}

create_connection() {
	echo "Creating eduroam connection profile..."
	nmcli connection add type wifi \
		con-name "$CON_NAME" \
		ssid "$SSID" \
		wifi-sec.key-mgmt wpa-eap \
		802-1x.eap peap \
		802-1x.phase2-auth mschapv2 \
		802-1x.identity "$IDENTITY" \
		802-1x.system-ca-certs yes
}

connect() {
	echo "Connecting to eduroam..."
	nmcli --ask connection up "$CON_NAME"
}

main() {
	if ! connection_exists; then
		create_connection
	fi
	connect
}

main
