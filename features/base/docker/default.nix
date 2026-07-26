{ lib, config, pkgs, ... }:
{
  options.features.base.docker = {
    enable = lib.mkEnableOption "Docker";
  };

  config = lib.mkIf config.features.base.docker.enable {
    virtualisation.docker = {
      enable = true;
      enableOnBoot = false;
    };
    environment.systemPackages = with pkgs; [ docker-compose ];
  };
}
