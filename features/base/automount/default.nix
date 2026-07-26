{ lib, config, pkgs, ... }:
{
  options.features.base.automount = {
    enable = lib.mkEnableOption "Automount removable media via udisks2 + udiskie";
  };

  config = lib.mkIf config.features.base.automount.enable {
    services.udisks2.enable = true;

    environment.systemPackages = with pkgs; [ exfatprogs ntfs3g ];

    home-manager.users.${config.features.base.system.user.name} = {
      services.udiskie = {
        enable = true;
        automount = true;
        notify = true;
        tray = "never";
      };
    };
  };
}
