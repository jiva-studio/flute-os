# NixOS Live ISO Configuration
# Bootable installer with Niri desktop and automated installation script
#
# Architecture:
# - default.nix: Main ISO config (this file)
# - live-features.nix: the live system's OWN feature set (not a host's)
# - live-session.nix: User setup and auto-login
# - install-script.nix: Automated installer (flute-install command)
#
# Build commands:
#   nix build .#iso      # x86_64 ISO
#   nix build .#iso-arm  # aarch64 ISO
#
# ISO features:
# - Niri tiling window manager
# - Auto-login (no password prompt)
# - One-command installation: sudo flute-install /dev/sdX
# - NetworkManager for WiFi setup
# - Flake configuration bundled at /iso/flute
#
# Used by: flake.nix (mkISO helper)
{ pkgs, lib, config, installTarget, ... }:

let
  # The host `flute-install` offers by default. A *template* from hosts/, never
  # a real machine — the image carries no private configuration to install.
  installScript = import ./install-script.nix {
    inherit pkgs installTarget;
  };

  # What the image is allowed to carry.
  #
  # `../.` would bundle the entire working tree — including personal/, whose
  # git-crypt files are DECRYPTED on whatever machine ran the build. An image
  # handed to anyone else would ship the builder's SSH private keys, API tokens
  # and signing certificates. So: the OS tree only, with a credential-shaped
  # denylist behind it in case something new lands outside personal/.
  #
  # This governs the SOURCE copied to /iso/flute. The system the image boots is
  # kept clean separately, by mkISO composing osModules instead of
  # commonModules — a denylist here cannot help with what the closure contains.
  #
  # A private configuration is supplied on the target instead, as the two-repo
  # layout in README.md describes.
  flakeRoot = ../.;
  bundledFlake = lib.cleanSourceWith {
    name = "fluteos-flake";
    src = lib.cleanSource flakeRoot;
    filter = path: _type:
      let
        rel = lib.removePrefix (toString flakeRoot + "/") (toString path);
        base = baseNameOf path;
      in
      rel != "personal"
      && !(lib.hasPrefix "personal/" rel)
      && !(lib.hasSuffix ".secret" base)
      && !(lib.hasSuffix ".key" base)
      && !(lib.hasPrefix "id_ed25519" base)
      && base != "result"
      && base != "~"
      # Build-host clutter, not part of the OS: agent settings, CI, tool caches.
      && base != ".claude"
      && base != ".github"
      && base != ".ruff_cache"
      && base != "__pycache__";
  };
in
{
  imports = [
    # The live system's own feature set — deliberately not a host's.
    ./live-features.nix
    ./live-session.nix
  ];

  # Disable man cache (fails in emulated builds for aarch64)
  documentation.man.cache.enable = false;

  # features.base.system and nixpkgs' installer base each supply a mkDefault
  # stateVersion, which is a conflict rather than an override. A live image keeps
  # no state across boots, so nixpkgs' current release is the right answer; the
  # value a host declares applies to the system flute-install writes to disk.
  system.stateVersion = lib.mkForce config.system.nixos.release;

  # ISO image settings
  isoImage = {
    # Fast compression (lz4 without -Xhc)
    # Trade-off: larger ISO (~1.5GB), but fastest possible build
    squashfsCompression = "lz4";

    # Copy the OS flake to the ISO at /iso/flute (no personal/, no credentials).
    # Used by flute-install script to copy config to target disk
    contents = [
      {
        source = bundledFlake;
        target = "/flute";
      }
    ];
  };

  # ISO filename: fluteos-<version>-<arch>.iso
  image.baseName = lib.mkForce "fluteos";

  # Enable fontconfig for proper font rendering in Niri
  fonts.fontconfig.enable = true;
  fonts.packages = with pkgs; [
    nerd-fonts.jetbrains-mono  # For terminal icons
    jetbrains-mono             # Monospace font
  ];

  # Enable fish shell (user's default shell)
  programs.fish.enable = true;

  # Packages available in live environment
  environment.systemPackages = with pkgs; [
    # Installation
    installScript  # sudo flute-install /dev/sdX
    disko          # Disk partitioning
    parted         # Manual partitioning (if needed)

    # Utilities
    neovim         # Text editor
    git            # Version control
    htop           # System monitor
  ];

  # Enable polkit for privilege escalation (needed by some GUI tools)
  security.polkit.enable = true;

  # Networking in live session. The host name comes from
  # features.base.system.hostname in ./live-features.nix.
  networking.networkmanager.enable = true;  # WiFi setup via nmtui or the bar
}
