#!/usr/bin/env bash
set -euo pipefail

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log() { echo -e "${GREEN}[build]${NC} $1"; }
warn() { echo -e "${YELLOW}[build]${NC} $1"; }
error() { echo -e "${RED}[build]${NC} $1"; exit 1; }

# Usage
#
# The image is chosen by ARCHITECTURE, not by host: an installer image is the
# product, the same for everybody, and it offers the bundled host templates at
# install time. It used to be `$0 yoga`, which built the author's laptop.
usage() {
    echo "Usage: $0 [x86|arm]"
    echo ""
    echo "Defaults to this machine's architecture."
    echo ""
    echo "Examples:"
    echo "  $0           # Build for this machine"
    echo "  $0 x86       # Build the x86_64 installer"
    echo "  $0 arm       # Build the aarch64 installer"
    exit 1
}

# Detect current architecture
CURRENT_ARCH=$(uname -m)
[[ "$CURRENT_ARCH" == "arm64" ]] && CURRENT_ARCH="aarch64"

case "${1:-$CURRENT_ARCH}" in
    x86|x86_64|amd64)
        TARGET_ARCH="x86_64"
        ATTR="iso"
        ;;
    arm|arm64|aarch64)
        TARGET_ARCH="aarch64"
        ATTR="iso-arm"
        ;;
    -h|--help)
        usage
        ;;
    *)
        error "Unknown architecture: $1. Use 'x86' or 'arm'."
        ;;
esac
OUTPUT_NAME="fluteos-${TARGET_ARCH}.iso"

# Check architecture compatibility
if [[ "$CURRENT_ARCH" != "$TARGET_ARCH" ]]; then
    # Check for emulation (Rosetta/QEMU)
    if [[ "$CURRENT_ARCH" == "x86_64" ]] && [[ -f /proc/sys/fs/binfmt_misc/rosetta || -d /mnt/machine ]]; then
        warn "Running under Rosetta emulation. Building $TARGET_ARCH on emulated x86_64."
    else
        error "Cannot build the $TARGET_ARCH image on $CURRENT_ARCH. Use a matching architecture or emulation."
    fi
fi

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Check if nix is installed
if ! command -v nix &> /dev/null; then
    warn "Nix not found. Installing..."

    # Install dependencies
    if command -v apt-get &> /dev/null; then
        sudo apt-get update && sudo apt-get install -y xz-utils curl
    elif command -v dnf &> /dev/null; then
        sudo dnf install -y xz curl
    elif command -v pacman &> /dev/null; then
        sudo pacman -Sy --noconfirm xz curl
    fi

    # Configure nix BEFORE install (needed for seccomp-restricted environments)
    mkdir -p ~/.config/nix
    cat > ~/.config/nix/nix.conf << 'EOF'
experimental-features = nix-command flakes
sandbox = false
filter-syscalls = false
EOF

    # Set env var for installer (seccomp disabled for containers/VMs)
    export NIX_CONFIG="sandbox = false
filter-syscalls = false"

    # Single-user install (simpler, no daemon needed)
    curl -L https://nixos.org/nix/install | sh -s -- --no-daemon --yes

    # Source nix profile
    . ~/.nix-profile/etc/profile.d/nix.sh
    log "Nix installed and ready."
fi

# Create swap if low memory
if ! swapon --show | grep -q /swapfile; then
    TOTAL_MEM=$(free -g | awk '/^Mem:/{print $2}')
    if [[ "$TOTAL_MEM" -lt 8 ]]; then
        warn "Low memory ($TOTAL_MEM GB). Creating swap..."
        sudo fallocate -l 4G /swapfile 2>/dev/null || sudo dd if=/dev/zero of=/swapfile bs=1M count=4096
        sudo chmod 600 /swapfile
        sudo mkswap /swapfile
        sudo swapon /swapfile
        log "Swap enabled"
    fi
fi

# Sandbox options for emulation
SANDBOX_OPT=""
if [[ "$CURRENT_ARCH" == "x86_64" ]] && [[ -f /proc/sys/fs/binfmt_misc/rosetta || -d /mnt/machine ]]; then
    SANDBOX_OPT="--option sandbox false --option filter-syscalls false"
fi

log "Building the $TARGET_ARCH installer image..."
# `path:` and not `.#`, for the same reason build.sh gives: `.#` builds the last
# COMMIT, so editing iso/ and re-running silently produced the previous image —
# and `warn-dirty = false` suppressed the only hint that had happened.
nix build "path:$SCRIPT_DIR#nixosConfigurations.${ATTR}.config.system.build.isoImage" \
  --extra-experimental-features "nix-command flakes" \
  $SANDBOX_OPT \
  -j 2

# Copy ISO. Globbed into an array first: `readlink -f result/iso/*.iso` with more
# than one match prints several lines, and the `cp` below then fails with a
# baffling "No such file" after a very long build.
shopt -s nullglob
ISO_CANDIDATES=(result/iso/*.iso)
shopt -u nullglob
if [[ ${#ISO_CANDIDATES[@]} -ne 1 ]]; then
    error "expected exactly one .iso under result/iso, found ${#ISO_CANDIDATES[@]}"
fi
ISO_PATH=$(readlink -f "${ISO_CANDIDATES[0]}")

log "Copying ISO to $SCRIPT_DIR/$OUTPUT_NAME..."
rm -f "$SCRIPT_DIR/$OUTPUT_NAME"
cp "$ISO_PATH" "$SCRIPT_DIR/$OUTPUT_NAME"

# Cleanup
rm -f result

log "Done! ISO saved as: $OUTPUT_NAME"
ls -lh "$SCRIPT_DIR/$OUTPUT_NAME"
