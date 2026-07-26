# Disk layout for the generic x86_64 template.
#
# GPT + UEFI, the simplest thing that works everywhere:
#   512M  ESP   (FAT32, /boot)
#   rest  root  (ext4, /)
#
# No swap partition — a template cannot guess how much RAM the machine has, and
# a swapfile added later is easier than a partition resized later.
#
# `disk` is supplied by the installer: flute-install passes the device the user
# named, so the default below only applies to a manual invocation:
#   disko --mode destroy,format,mount --arg disk '"/dev/nvme0n1"' hosts/pc/disko.nix
#
# Used by: flake.nix (hostModules), iso/install-script.nix
{ disk ? "/dev/sda", ... }:

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
