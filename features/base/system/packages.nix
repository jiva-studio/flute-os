{ lib, config, pkgs, ... }:
{
  config = lib.mkIf config.features.base.system.enable {
    environment.systemPackages = with pkgs; [
      git git-crypt htop tmux curl wget unzip file tree
    ];
  };
}
