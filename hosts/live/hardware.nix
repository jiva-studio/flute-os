# ARM hardware configuration
# This file will be auto-generated during installation.
# Run: sudo nixos-generate-config --show-hardware-config > hardware.nix
#
# For now, this is a minimal placeholder for ARM/aarch64.

{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  # Kernel modules for ARM (adjust for your hardware)
  boot.initrd.availableKernelModules = [ "xhci_pci" "nvme" "usb_storage" "sd_mod" ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ ];
  boot.extraModulePackages = [ ];

  # Enable firmware
  hardware.enableRedistributableFirmware = true;
}
