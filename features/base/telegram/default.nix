{ lib, config, ... }:
{
  options.features.base.telegram = {
    enable = lib.mkEnableOption "Telegram messenger";
  };

  config = lib.mkIf config.features.base.telegram.enable {
    home-manager.users.${config.features.base.system.user.name} = { pkgs, ... }: {
      home.packages = [ pkgs.telegram-desktop ];
    };
  };
}
