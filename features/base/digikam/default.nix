{ lib, config, ... }:
{
  options.features.base.digikam = {
    enable = lib.mkEnableOption "DigiKam photo management";
  };

  config = lib.mkIf config.features.base.digikam.enable {
    home-manager.users.${config.features.base.system.user.name} = { pkgs, ... }: {
      home.packages = [ pkgs.digikam ];
      home.file."Photos/.digikam/.keep".text = "";
    };
  };
}
