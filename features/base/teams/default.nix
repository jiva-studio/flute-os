{ lib, config, ... }:
{
  options.features.base.teams = {
    enable = lib.mkEnableOption "Microsoft Teams";
  };

  config = lib.mkIf config.features.base.teams.enable {
    home-manager.users.${config.features.base.system.user.name} = { pkgs, ... }: {
      home.packages = [ pkgs.teams-for-linux ];
    };
  };
}
