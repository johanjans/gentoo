#!/bin/bash
#
# Interactive Gentoo system update
# Runs sync, update, and cleanup in a single doas session
#

GRN='\033[1;32m'
BLU='\033[1;34m'
YEL='\033[1;33m'
RED='\033[1;31m'
RST='\033[0m'

echo -e "${BLU}Starting Gentoo system update...${RST}\n"

# Run all privileged operations in a single doas session
doas bash -c '
	set -e

	echo -e "\n\033[1;34m[1/4] Syncing Portage tree...\033[0m"
	emerge --sync

	echo -e "\n\033[1;34m[2/4] Checking for Portage update...\033[0m"
	if emerge -pv sys-apps/portage 2>/dev/null | grep -q "\[ebuild[^]]*U[^]]*\]"; then
		echo -e "\033[1;33mPortage update available, updating first...\033[0m"
		emerge --oneshot sys-apps/portage
	else
		echo "Portage is up to date."
	fi

	echo -e "\n\033[1;34m[3/4] Updating @world...\033[0m"
	emerge -avuDN @world

	echo -e "\n\033[1;33m[4/4] Cleaning up...\033[0m"
	emerge --depclean -a

	echo -e "\n\033[1;32mUpdate complete!\033[0m"
'

# Check exit status
if [[ $? -eq 0 ]]; then
	notify-send 'Update Complete' 'System has been updated successfully' -i 'package-install'
else
	notify-send 'Update Failed' 'Check terminal for details' -i 'dialog-error'
fi

# Signal waybar to refresh
pkill -RTMIN+1 waybar 2>/dev/null

# Check if dispatch-conf is needed
CONFIG_FILES=$(find /etc -name "._cfg*" 2>/dev/null | wc -l)
if [[ $CONFIG_FILES -gt 0 ]]; then
	echo -e "\n${YEL}==================================================${RST}"
	echo -e "${YEL}  REMINDER: $CONFIG_FILES config file(s) need merging${RST}"
	echo -e "${YEL}  Run 'doas dispatch-conf' to review changes${RST}"
	echo -e "${YEL}==================================================${RST}"
	notify-send 'Config Files Need Merging' "Run dispatch-conf to merge $CONFIG_FILES file(s)" -i 'dialog-warning'
fi

echo -e "\n${GRN}Done!${RST}"
