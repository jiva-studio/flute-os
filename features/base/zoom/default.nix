{ lib, config, ... }:
{
  options.features.base.zoom = {
    enable = lib.mkEnableOption "Zoom configuration";
  };

  config = lib.mkIf config.features.base.zoom.enable {
    home-manager.users.${config.features.base.system.user.name} = {
      xdg.configFile."zoomus.conf" = {
        force = true;
        text = "[General]\nenableWaylandShare=true\n";
      };
    };
  };
}
