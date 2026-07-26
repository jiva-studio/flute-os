# Disk Partitioning Configuration for aarch64 (live/VM)
# Declarative disk layout using disko
#
# Layout:
# - 512MB EFI boot partition (FAT32, /boot)
# - Remaining space for root partition (ext4, /)
#
# Note: Same layout as yoga, but for aarch64 architecture
#
# Usage:
# - Called by iso/install-script.nix during installation
# - Can be used with: disko --mode destroy,format,mount --arg disk '"/dev/vda"' ./hosts/live/disko.nix
#
# Used by: flake.nix (mkSystem helper), iso/install-script.nix
{ lib, disk ? "/dev/sda", ... }:

{
  disko.devices = {
    disk = {
      main = {
        type = "disk";
        device = disk;
        content = {
          type = "gpt";
          partitions = {
            ESP = {
              size = "512M";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
                mountOptions = [ "umask=0077" ];
              };
            };
            root = {
              size = "100%";
              content = {
                type = "filesystem";
                format = "ext4";
                mountpoint = "/";
              };
            };
          };
        };
      };
    };
  };
}
