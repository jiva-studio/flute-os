# Niri startup commands
{ pkgs, config }:

''
  // Start niri session target (imports environment and activates GUI services)
  // Using --wait to block until oneshot service completes (prevents race condition)
  spawn-at-startup "${pkgs.bash}/bin/bash" "-c" "${pkgs.systemd}/bin/systemctl --user start --wait niri-session-env"

  // mako now managed by systemd service
  // wallpaper rotation managed by systemd: fluteos-wallpaper.service
  // waybar managed by systemd: waybar.service
  spawn-at-startup "blueman-applet"
  // PTT managed by systemd: fluteos-ptt.service and ptt-voxinput.service
''
