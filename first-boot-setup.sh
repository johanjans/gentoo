#!/bin/bash

# Initial setup
# nmcli device wifi connect uplink --ask
# nmcli device wifi set wlp0s20f3 autoconnect yes
# emerge @world

# Enable GURU
mkdir /etc/portage/repos.conf/
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
echo "media-video/obs-studio ~amd64" >> /etc/portage/package.accept_keywords/hyprland

# Dependencies often pulled in by the above
echo "gui-libs/hyprutils ~amd64" >> /etc/portage/package.accept_keywords/hyprland
echo "gui-libs/hyprlang ~amd64" >> /etc/portage/package.accept_keywords/hyprland
echo "gui-libs/hyprcursor ~amd64" >> /etc/portage/package.accept_keywords/hyprland
echo "gui-libs/aquamarine ~amd64" >> /etc/portage/package.accept_keywords/hyprland
echo "dev-libs/hyprland-protocols ~amd64" >> /etc/portage/package.accept_keywords/hyprland
echo "dev-cpp/sdbus-c++ ~amd64" >> /etc/portage/package.accept_keywords/hyprland
echo "dev-util/hyprwayland-scanner ~amd64" >> /etc/portage/package.accept_keywords/hyprland

# Unmask GURU specific packages
echo "gui-apps/awww ~amd64" >> /etc/portage/package.accept_keywords/guru-packages
echo "gui-apps/hyprshot ~amd64" >> /etc/portage/package.accept_keywords/guru-packages
echo "sys-auth/hyprpolkitagent ~amd64" >> /etc/portage/package.accept_keywords/guru-packages
echo "app-misc/brightnessctl ~amd64" >> /etc/portage/package.accept_keywords/guru-packages
echo "gui-wm/hyprland-contrib ~amd64" >> /etc/portage/package.accept_keywords/guru-packages
echo "net-im/mattermost-desktop-bin ~amd64" >> /etc/portage/package.accept_keywords/guru-packages

# USE flag settings for general software
echo "media-video/obs-studio pipewire" >> /etc/portage/package.use/obs-studio
echo "media-video/pipewire dbus" >> /etc/portage/package.use/pipewire
echo "gui-apps/waybar network pulseaudio tray mpris wifi experimental" >> /etc/portage/package.use/waybar
echo "dev-libs/libdbusmenu gtk3" >> /etc/portage/package.use/libdbusmenu

# Install hyprland
emerge --ask --verbose \
    gui-wm/hyprland \
    gui-apps/hyprlock \
    gui-apps/hypridle \
    gui-apps/hyprpicker \
    gui-libs/xdg-desktop-portal-hyprland \
    sys-auth/hyprpolkitagent \
    gui-apps/awww \
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
    app-misc/brightnessctl\
    gui-wm/hyprland-contrib\
    app-shells/fzf\
    media-sound/pavucontrol\
    gui-libs/xdg-desktop-portal-wlr

# USE flag settings for general software
echo "app-dicts/myspell-en l10n_en-US" >> /etc/portage/package.use/myspell-en
echo "media-libs/babl introspection" >> /etc/portage/package.use/babl
echo "media-libs/gegl introspection" >> /etc/portage/package.use/gegl
echo "sys-libs/zlib minizip" >> /etc/portage/package.use/zlib
echo "media-plugins/alsa-plugins pulseaudio" >> /etc/portage/package.use/alsa-plugins

# install general software
emerge --ask --verbose\
    app-editors/neovim\
    google-chrome\
    net-im/mattermost-desktop-bin\
    gimp\
    texstudio\
    texlive\
    inkscape\
    vscode\

# install some AI-stuff
curl -fsSL https://claude.ai/install.sh | bash
