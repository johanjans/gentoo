# /etc/skel/.bash_profile

# This file is sourced by bash for login shells.  The following line
# runs your .bashrc and is recommended by the bash info pages.
if [[ -f ~/.bashrc ]]; then
  . ~/.bashrc
fi

# Auto-start Hyprland on tty1 with smooth Plymouth transition
if [[ -z "$WAYLAND_DISPLAY" && "$XDG_VTNR" == "1" ]]; then
  # Clear screen and hide cursor to prevent any flash
  printf '\033[2J\033[H\033[?25l'
  if plymouth --ping 2>/dev/null; then
    plymouth quit --retain-splash
  fi
  exec dbus-run-session Hyprland &>~/.hyprland.log
fi
