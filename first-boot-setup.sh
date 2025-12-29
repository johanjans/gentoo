#!/bin/bash

# Initial setup
# nmcli device wifi connect uplink --ask
# nmcli device wifi set wlp0s20f3 autoconnect yes
# emerge @world

# Enable GURU
cat > /etc/portage/repos.conf/guru.conf << 'EOF'
[guru]
location = /var/db/repos/guru
sync-type = git
sync-uri = https://github.com/gentoo-mirror/guru.git
EOF
emerge --sync guru
mkdir -p /etc/portage/package.accept_keywords

# Create a file for Hyprland ecosystem
echo "gui-wm/hyprland ~amd64" >> /etc/portage/package.accept_keywords/hyprland
echo "gui-libs/xdg-desktop-portal-hyprland ~amd64" >> /etc/portage/package.accept_keywords/hyprland
echo "gui-apps/hyprlock ~amd64" >> /etc/portage/package.accept_keywords/hyprland
echo "gui-apps/hypridle ~amd64" >> /etc/portage/package.accept_keywords/hyprland
echo "gui-apps/hyprpicker ~amd64" >> /etc/portage/package.accept_keywords/hyprland

# Dependencies often pulled in by the above
echo "gui-libs/hyprutils ~amd64" >> /etc/portage/package.accept_keywords/hyprland
echo "gui-libs/hyprlang ~amd64" >> /etc/portage/package.accept_keywords/hyprland
echo "gui-libs/hyprcursor ~amd64" >> /etc/portage/package.accept_keywords/hyprland
echo "gui-libs/aquamarine ~amd64" >> /etc/portage/package.accept_keywords/hyprland
echo "dev-libs/hyprland-protocols ~amd64" >> /etc/portage/package.accept_keywords/hyprland

# Unmask GURU specific packages
echo "gui-apps/swww ~amd64" >> /etc/portage/package.accept_keywords/guru-packages
echo "gui-apps/hyprshot ~amd64" >> /etc/portage/package.accept_keywords/guru-packages
echo "sys-auth/hyprpolkitagent ~amd64" >> /etc/portage/package.accept_keywords/guru-packages

# Install things
emerge --ask --verbose \
    gui-wm/hyprland \
    gui-apps/hyprlock \
    gui-apps/hypridle \
    gui-apps/hyprpicker \
    gui-libs/xdg-desktop-portal-hyprland \
    sys-auth/hyprpolkitagent \
    gui-apps/swww \
    gui-apps/hyprshot \
    media-sound/playerctl \
    x11-terms/kitty \
    gui-apps/waybar \
    gui-apps/mako \
    gui-apps/wofi \
    media-fonts/symbols-nerd-font \
    media-fonts/noto \
    app-misc/fastfetch \
    x11-libs/libnotify \
    gui-apps/grim \
    gui-apps/slurp \
    app-misc/brightnessctl