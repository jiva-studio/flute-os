# Live ISO Session Configuration
# User setup and auto-login for the live environment
#
# Features:
# - Auto-login to Niri desktop (no password prompt)
# - The configuration's own primary user, with a throwaway live password
# - Passwordless sudo for installation tasks
# - Welcome message with install instructions
#
# Used by: default.nix
{ pkgs, lib, config, ... }:

let
  # Whoever the configuration says the primary user is — never a name spelled
  # out here. A hardcoded login would put the distro author's account on every
  # downloader's live image.
  user = config.features.base.system.user.name;
in
{
  # Live system user with full privileges
  users.users.${user} = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" "video" "audio" "input" "uinput" ];
    # Throwaway: the live session is ephemeral, and flute-install tells the
    # user to change it after the first boot of the installed system.
    initialPassword = lib.mkForce "qwerty";
  };

  # Allow passwordless sudo in live session (for flute-install)
  security.sudo.wheelNeedsPassword = false;

  # Auto-login directly to Niri (no password prompt for live session)
  services.greetd = {
    enable = true;
    settings = lib.mkForce {
      terminal = {
        vt = 1;
      };
      default_session = {
        command = "${pkgs.bash}/bin/bash -l -c niri-session";
        inherit user;
      };
    };
  };

  # Welcome message displayed on TTY login
  environment.etc."issue".text = ''

    _____ _       _          ___  ____
   |  ___| |_   _| |_ ___   / _ \/ ___|
   | |_  | | | | | __/ _ \ | | | \___ \
   |  _| | | |_| | ||  __/ | |_| |___) |
   |_|   |_|\__,_|\__\___|  \___/|____/

      Welcome to Flute OS Live System!

    To install to disk, run:
      sudo flute-install /dev/sdX

  '';
}
