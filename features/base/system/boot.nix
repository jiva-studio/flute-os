{ lib, config, ... }:
{
  config = lib.mkIf config.features.base.system.enable {
    # mkDefault, not a plain assignment: nixosModules.fluteos is meant to be
    # imported by configurations FluteOS knows nothing about, and a consumer on
    # GRUB, lanzaboote or a BIOS machine would otherwise hit a definition
    # conflict and have to reach for mkForce to boot their own machine.
    # systemd-boot is the right DEFAULT, not a requirement.
    boot.loader.systemd-boot.enable = lib.mkDefault true;
    boot.loader.systemd-boot.configurationLimit = lib.mkDefault 10;
    boot.loader.systemd-boot.consoleMode = lib.mkDefault "max";
    boot.loader.efi.canTouchEfiVariables = lib.mkDefault true;
    boot.kernelParams = [ "quiet" "loglevel=3" ];
    boot.initrd.verbose = false;
    boot.consoleLogLevel = 0;
  };
}
