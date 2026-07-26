# Live host — aarch64 (ARM) configuration.
#
# Distributable FluteOS template: builds on a clean clone WITHOUT a
# personal/ directory. Anyone can use this as the base for their own ARM
# live ISO. Personal data (companies, NAS devices, WiFi PSKs, identity)
# is NOT referenced here.
{ config, pkgs, ... }:

{
  imports = [
    ./hardware.nix
  ];

  # FluteOS itself, in two bundles instead of thirty repeated lines.
  features.profiles.desktop = true;
  features.profiles.dev = true;

  # === Base features ===
  features.base.system.enable = true;
  features.base.system.hostname = "live";

  features.base.wifi.enable = true;
  features.base.ssh.enable = true;

  features.base.niri = {
    enable = true;
    modKey = "Alt";
  };

  features.base.obsidian.enable = true;
  features.base.firefox.enable = true;
  features.base.yazi.enable = true;
  features.base.zathura.enable = true;
  features.base.foliate.enable = true;
  features.base.mpd.enable = true;

  # === FluteOS features ===
  features.fluteos.weather.enable = true;

  # === Host-specific ===

  # ARM packages
  home-manager.users.${config.features.base.system.user.name} = { pkgs, ... }: {
    home.packages = [ pkgs.chromium ];
  };
}
