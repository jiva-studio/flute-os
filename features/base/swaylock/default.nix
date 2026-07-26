{ lib, config, ... }:
let theme = config.features.fluteos.theme.resolved; in
{
  options.features.base.swaylock = {
    enable = lib.mkEnableOption "Swaylock screen locker";
  };

  config = lib.mkIf config.features.base.swaylock.enable {
    home-manager.users.${config.features.base.system.user.name} = { pkgs, ... }: {
      programs.swaylock = {
        enable = true;
        package = pkgs.swaylock-effects;
        settings = {
          screenshots = true; clock = true; indicator = true;
          indicator-idle-visible = false; indicator-radius = 120; indicator-thickness = 10;
          effect-blur = "10x3"; effect-vignette = "0.3:0.3"; fade-in = 0.2; grace = 2;
          color = theme.palette.base;
          inside-color = theme.palette.surface0; inside-clear-color = theme.palette.surface0;
          inside-ver-color = theme.palette.blue; inside-wrong-color = theme.palette.red;
          line-color = "00000000"; line-clear-color = "00000000";
          line-ver-color = "00000000"; line-wrong-color = "00000000";
          ring-color = theme.palette.overlay0; ring-clear-color = theme.palette.green;
          ring-ver-color = theme.palette.blue; ring-wrong-color = theme.palette.red;
          key-hl-color = theme.palette.green; bs-hl-color = theme.palette.red;
          separator-color = "00000000";
          text-color = theme.palette.text; text-clear-color = theme.palette.text;
          text-ver-color = theme.palette.text; text-wrong-color = theme.palette.text;
          timestr = "%H:%M"; datestr = "%a, %d %b";
          font = theme.fonts.sans; font-size = 20;
        };
      };
    };
  };
}
