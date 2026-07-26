# pc — the distributable x86_64 template.
#
# FluteOS shipped no x86_64 host at all: `hosts/` held only `live` (aarch64),
# and the x86_64 outputs resolved to `personal/hosts/yoga`. So a clean clone
# could not evaluate `nixosConfigurations.yoga`, could not build the default
# x86_64 package, and the installer image had nothing installable on it. This
# is the host that fills that hole.
#
# It is a STARTING POINT, not a machine: generic UEFI hardware, a plain disk
# layout, and the features that make FluteOS recognisably itself. Copy it,
# rename it, and change what is actually different about your machine —
# `hardware.nix` is overwritten by the installer with what it detects.
#
# Concerns split across:
#   hardware.nix — kernel modules and microcode (regenerated on install)
#   disko.nix    — disk layout
{ ... }:
{
  imports = [
    ./hardware.nix
  ];

  features.base.system.enable = true;
  features.base.system.hostname = "pc";

  # FluteOS itself. Locale, timezone and keyboard are deliberately left at the
  # product's neutral defaults (UTC / en_US / us) — those are yours to state.
  features.profiles.desktop = true;
  features.profiles.dev = true;

  # === Base features ===
  features.base.wifi.enable = true;
  features.base.ssh.enable = true;
  features.base.bluetooth.enable = true;

  # Applications are taste, so a template picks the smallest useful set and
  # leaves the rest to you: a browser, a file manager, a PDF reader.
  features.base.firefox.enable = true;
  features.base.yazi.enable = true;
  features.base.zathura.enable = true;

  # === FluteOS features ===
  features.fluteos.weather.enable = true;
}
