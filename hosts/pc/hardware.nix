# Generic x86_64 hardware.
#
# Placeholder that boots on ordinary UEFI machines. `flute-install` replaces
# this file with `nixos-generate-config --show-hardware-config` output for the
# machine it installs to, so nothing here needs to be right for your laptop —
# it only needs to evaluate, and to be enough for the first boot.
{ lib, modulesPath, ... }:

{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  # The usual suspects for reaching a root filesystem: NVMe, SATA/AHCI, USB.
  boot.initrd.availableKernelModules = [
    "xhci_pci"
    "ahci"
    "nvme"
    "usb_storage"
    "usbhid"
    "sd_mod"
    "sr_mod"
    "rtsx_pci_sdmmc"
  ];
  boot.initrd.kernelModules = [ ];
  # Left empty on purpose: naming kvm-intel and kvm-amd together makes one of
  # them fail to load on every boot. The installer fills in the right one.
  boot.kernelModules = [ ];
  boot.extraModulePackages = [ ];

  hardware.enableRedistributableFirmware = true;
  # Both vendors, because this template does not know which CPU it will land on.
  hardware.cpu.intel.updateMicrocode = lib.mkDefault true;
  hardware.cpu.amd.updateMicrocode = lib.mkDefault true;
}
