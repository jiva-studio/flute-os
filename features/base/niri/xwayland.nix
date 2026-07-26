# XWayland support for niri via xwayland-satellite.
# niri is a pure Wayland compositor; X11/xcb apps (e.g. MuseScore 4, which
# forces QT_QPA_PLATFORM=xcb internally) need an X server to connect to.
{ lib, config, pkgs, ... }:

{
  config = lib.mkIf config.features.base.niri.enable {
    environment.systemPackages = [ pkgs.xwayland-satellite ];

    environment.sessionVariables.DISPLAY = ":0";

    home-manager.users.${config.features.base.system.user.name} = { ... }: {
      systemd.user.services.xwayland-satellite = {
        Unit = {
          Description = "XWayland outside, the way it was meant to be";
          BindsTo = [ "graphical-session.target" ];
          PartOf = [ "graphical-session.target" ];
          After = [ "graphical-session.target" ];
          Requisite = [ "graphical-session.target" ];
        };
        Service = {
          Type = "notify";
          NotifyAccess = "all";
          ExecStart = "${pkgs.xwayland-satellite}/bin/xwayland-satellite :0";
          Restart = "on-failure";
        };
        Install.WantedBy = [ "graphical-session.target" ];
      };
    };
  };
}
