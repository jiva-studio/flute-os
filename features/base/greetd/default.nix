{ lib, config, pkgs, ... }:
{
  options.features.base.greetd = {
    enable = lib.mkEnableOption "Display manager (Ly)";
  };

  config = lib.mkIf config.features.base.greetd.enable {
    services.displayManager.sessionPackages = [ pkgs.niri ];
    services.displayManager.ly = {
      enable = true;
      settings = {
        animate = true;
        animation = "matrix";
        save = true;
      };
    };
  };
}
