{ lib, config, pkgs, ... }:
{
  options.features.base.iphone = {
    enable = lib.mkEnableOption "iPhone support";
  };

  config = lib.mkIf config.features.base.iphone.enable {
    services.usbmuxd.enable = true;
    environment.systemPackages = with pkgs; [ libimobiledevice ifuse ];
  };
}
