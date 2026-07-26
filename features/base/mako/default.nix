{ lib, config, ... }:
let theme = config.features.fluteos.theme.resolved; in
{
  options.features.base.mako = {
    enable = lib.mkEnableOption "Mako notifications";
  };

  config = lib.mkIf config.features.base.mako.enable {
    home-manager.users.${config.features.base.system.user.name} = { pkgs, ... }: {
      services.mako = {
        enable = true;
        settings = {
          background-color = theme.colors.bg;
          text-color = theme.colors.fg;
          border-color = theme.colors.accent;
          border-radius = theme.uiConstants.borderRadius.normal;
          border-size = theme.uiConstants.borderWidth.normal;
          default-timeout = 5000;
          font = "${theme.fonts.mono} ${toString theme.fonts.size.small}";
        };
      };
      systemd.user.services.mako = {
        Unit = {
          Description = "Mako notification daemon";
          PartOf = [ "graphical-session.target" ];
          After = [ "graphical-session.target" ];
        };
        Service = {
          Type = "simple";
          ExecCondition = "${pkgs.bash}/bin/bash -c 'test -n \"$WAYLAND_DISPLAY\"'";
          ExecStart = "${pkgs.mako}/bin/mako";
          Restart = "on-failure";
          RestartSec = 1;
        };
        Install.WantedBy = [ "niri-session.target" ];
      };
    };
  };
}
