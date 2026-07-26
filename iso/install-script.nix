# Flute Install Script
# Automated NixOS installation script for live ISO
#
# Usage: sudo flute-install /dev/sdX [host]
#
# What it does:
# 1. Resolves the host to install and checks it declares a disk layout
# 2. Partitions and mounts with disko (GPT + UEFI)
# 3. Copies the flake to /mnt/etc/nixos
# 4. Generates hardware.nix for the detected machine
# 5. Runs nixos-install
#
# Disk layout comes from the chosen host's disko.nix, not from here.
#
# Used by: default.nix
#
# `installTarget` is the template this image offers by default. It names a
# directory under hosts/, never a real machine and never an account: the image
# carries no private configuration, so it cannot know who will run it.
{ pkgs, installTarget, ... }:

pkgs.writeShellScriptBin "flute-install" ''
  #!/usr/bin/env bash
  set -euo pipefail

  # Colors
  RED='\033[0;31m'
  GREEN='\033[0;32m'
  YELLOW='\033[1;33m'
  NC='\033[0m' # No Color

  log() { echo -e "''${GREEN}[flute]''${NC} $1"; }
  warn() { echo -e "''${YELLOW}[flute]''${NC} $1"; }
  error() { echo -e "''${RED}[flute]''${NC} $1"; exit 1; }

  # Check if running as root
  if [[ $EUID -ne 0 ]]; then
    error "This script must be run as root (use sudo)"
  fi

  # Check arguments
  if [[ $# -lt 1 ]]; then
    echo "Usage: flute-install <disk> [host]"
    echo ""
    echo "host defaults to '${installTarget}' — the template bundled on this image."
    echo ""
    echo "Examples:"
    echo "  flute-install /dev/sda       # SATA/USB disk"
    echo "  flute-install /dev/nvme0n1   # NVMe SSD"
    echo "  flute-install /dev/vda       # VirtIO (VM)"
    echo "  flute-install /dev/mmcblk0   # SD card/eMMC"
    echo ""
    echo "Available disks:"
    lsblk -d -o NAME,SIZE,TYPE,MODEL | head -1
    lsblk -d -o NAME,SIZE,TYPE,MODEL | grep -E "disk|nvme|mmc"
    exit 1
  fi

  DISK="$1"

  # Verify disk exists
  if [[ ! -b "$DISK" ]]; then
    error "Disk $DISK does not exist"
  fi

  # --- Everything that can fail happens BEFORE the point of no return. ---
  #
  # The "this will erase all data" prompt used to come first, so a user could
  # type `yes` and only then be told the host does not exist. Nothing was
  # destroyed, but it teaches you to confirm a wipe that was never validated.

  # Find the flake directory (should be on ISO)
  FLAKE_DIR="/iso/flute"
  if [[ ! -d "$FLAKE_DIR" ]]; then
    # Fallback: check if we're in the flake dir
    if [[ -f "./flake.nix" ]]; then
      FLAKE_DIR="$(pwd)"
    else
      error "Cannot find flake directory. Make sure /iso/flute exists or run from flake directory"
    fi
  fi

  log "Using flake from: $FLAKE_DIR"

  # Locate the host directory the same way flake.nix's resolveHostDir does:
  # a private overlay's copy wins over the distributed template.
  # An explicit second argument overrides the template this image offers.
  HOST="''${2:-${installTarget}}"
  if [[ -d "$FLAKE_DIR/personal/hosts/$HOST" ]]; then
    HOST_DIR="$FLAKE_DIR/personal/hosts/$HOST"
  elif [[ -d "$FLAKE_DIR/hosts/$HOST" ]]; then
    HOST_DIR="$FLAKE_DIR/hosts/$HOST"
  else
    warn "No host directory for '$HOST' under $FLAKE_DIR."
    warn "The image carries FluteOS only — no private configuration, by design."
    echo ""
    echo "Hosts bundled on this image:"
    ls "$FLAKE_DIR/hosts" 2>/dev/null | sed 's/^/  /' || echo "  (none)"
    echo ""
    echo "Pick one of those:"
    echo "  flute-install $DISK <host>"
    echo ""
    echo "To install your own configuration instead, install a bundled host"
    echo "first and add your private repository afterwards — /iso/flute is a"
    echo "read-only squashfs and cannot be edited here."
    exit 1
  fi
  log "Installing host '$HOST' from $HOST_DIR"

  if [[ ! -f "$HOST_DIR/disko.nix" ]]; then
    error "$HOST_DIR/disko.nix is missing — this host does not declare its own partitioning"
  fi

  # --- Point of no return. ---
  echo ""
  warn "WARNING: This will ERASE ALL DATA on $DISK"
  echo ""
  lsblk "$DISK"
  echo ""
  read -p "Are you sure you want to continue? (yes/no): " confirm
  if [[ "$confirm" != "yes" ]]; then
    log "Aborted"
    exit 0
  fi

  log "Partitioning disk with disko..."
  disko --mode destroy,format,mount --arg disk "\"$DISK\"" "$HOST_DIR/disko.nix"

  log "Disk partitioned and mounted at /mnt"

  # Copy flake to target. The source is a read-only squashfs, so the copy would
  # be read-only too — make it writable, since the whole point is that the user
  # edits their configuration after the first boot.
  log "Copying configuration to /mnt/etc/nixos..."
  mkdir -p /mnt/etc/nixos
  cp -r "$FLAKE_DIR"/* /mnt/etc/nixos/
  chmod -R u+w /mnt/etc/nixos

  # Generate hardware config (--no-filesystems because disko handles that)
  # Written into the copy, at whatever relative path the host dir sits on.
  REL_HOST_DIR="''${HOST_DIR#"$FLAKE_DIR"/}"
  log "Detecting hardware..."
  nixos-generate-config --no-filesystems --show-hardware-config --root /mnt \
    > "/mnt/etc/nixos/$REL_HOST_DIR/hardware.nix"

  # Install NixOS
  log "Installing NixOS (this may take a while)..."
  nixos-install --flake "/mnt/etc/nixos#$HOST" --no-root-passwd

  log "Installation complete!"
  echo ""
  # Ask the configuration that was just installed who its user is, rather than
  # printing a name from build time — the image and the installed system need
  # not agree, and on an image built next to a private overlay they did not.
  TARGET_USER="$(nix eval --raw \
    --extra-experimental-features "nix-command flakes" \
    "/mnt/etc/nixos#nixosConfigurations.$HOST.config.features.base.system.user.name" \
    2>/dev/null || true)"
  if [[ -n "$TARGET_USER" ]]; then
    log "Default login: $TARGET_USER / the initialPassword this configuration sets"
  else
    log "Default login: the user '$HOST' declares, with the initialPassword it sets"
  fi
  log "Change password after first login with: passwd"
  echo ""
  log "Reboot now: reboot"
''
