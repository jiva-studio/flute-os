#!/usr/bin/env bash
set -euo pipefail

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log() { echo -e "${GREEN}[release]${NC} $1"; }
warn() { echo -e "${YELLOW}[release]${NC} $1"; }
error() { echo -e "${RED}[release]${NC} $1"; exit 1; }

# Usage
#
# The images themselves go to Bunny and never to GitHub: a release asset is
# capped at 2 GB and a FluteOS image is bigger than that. What lands on the
# GitHub release is the small, verifiable part — checksums, the signature over
# them, and the torrent. That split is deliberate: the signature lives on a
# different host than the bytes it signs, so a compromised CDN cannot serve a
# tampered image with a matching signature.
usage() {
    echo "Usage: $0 <version> [options]"
    echo ""
    echo "Options:"
    echo "  --arch x86|arm|both   Which images to publish (default: both)"
    echo "  --skip-build          Use the .iso files already in the tree"
    echo "  --dry-run             Do everything except upload and publish"
    echo ""
    echo "Credentials come from the environment; run it under 1Password:"
    echo "  op run --env-file=.env.op -- $0 25.11"
    exit 1
}

[[ $# -ge 1 ]] || usage
case "$1" in -h|--help) usage ;; esac

VERSION="$1"; shift
ARCHES="both"
SKIP_BUILD=false
DRY_RUN=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --arch) ARCHES="${2:-}"; shift 2 ;;
        --skip-build) SKIP_BUILD=true; shift ;;
        --dry-run) DRY_RUN=true; shift ;;
        -h|--help) usage ;;
        *) error "Unknown option: $1" ;;
    esac
done

# A version is part of every published URL forever, so it is validated here
# rather than discovered later as a typo in a path nobody can delete.
[[ "$VERSION" =~ ^[0-9]{2}\.[0-9]{2}(\.[0-9]+)?$ ]] \
    || error "Version must look like 25.11 or 25.11.1, got: $VERSION"

case "$ARCHES" in
    x86)  TARGETS=(x86_64) ;;
    arm)  TARGETS=(aarch64) ;;
    both) TARGETS=(x86_64 aarch64) ;;
    *) error "--arch must be x86, arm or both" ;;
esac

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Credentials. Checked up front: the build takes an hour, and discovering a
# missing key after it is a bad way to spend an evening.
require_env() {
    for var in "$@"; do
        [[ -n "${!var:-}" && "${!var}" != "TODO" ]] \
            || error "$var is not set. Run under: op run --env-file=.env.op -- $0 ..."
    done
}
require_env BUNNY_STORAGE_KEY BUNNY_STORAGE_ZONE BUNNY_STORAGE_ENDPOINT
$DRY_RUN || require_env BUNNY_API_KEY GITHUB_TOKEN MINISIGN_SECRET_KEY

GITHUB_OWNER="${GITHUB_OWNER:-jiva-studio}"
GITHUB_REPO="${GITHUB_REPO:-flute-os}"
DL_HOST="${DOMAIN:-fluteos-dl.b-cdn.net}"
# The download storage zone holds nothing but releases, so a version is a
# top-level directory in it and the delivered URL needs no extra prefix.
REMOTE_DIR="$VERSION"
BASE_URL="https://$DL_HOST/$VERSION"

# Everything is staged in one directory so the torrent, the checksums and the
# upload all see exactly the same set of files.
STAGE="$SCRIPT_DIR/.release/$VERSION"
rm -rf "$STAGE"; mkdir -p "$STAGE"

# ---------------------------------------------------------------- build

for arch in "${TARGETS[@]}"; do
    iso="fluteos-${arch}.iso"
    if [[ "$SKIP_BUILD" == false ]]; then
        case "$arch" in x86_64) flag=x86 ;; aarch64) flag=arm ;; esac
        log "Building $arch..."
        ./build-iso.sh "$flag"
    fi
    [[ -f "$iso" ]] || error "$iso not found. Build it, or drop --skip-build."
    # Renamed on the way in: the build always writes the same name, and an
    # unversioned file in a versioned directory is how a 25.11 URL ends up
    # serving 25.12 bytes.
    cp "$iso" "$STAGE/fluteos-${VERSION}-${arch}.iso"
    log "Staged fluteos-${VERSION}-${arch}.iso ($(du -h "$STAGE/fluteos-${VERSION}-${arch}.iso" | cut -f1))"
done

# ---------------------------------------------------------------- checksums

cd "$STAGE"
log "Hashing..."
sha256sum ./*.iso | sed 's| \./| |' > SHA256SUMS
cat SHA256SUMS

# ---------------------------------------------------------------- signature

# The key is written unencrypted to a private temp file for the length of one
# signature. minisign asks for a passphrase on a tty and there is no tty in CI,
# so the key stored in 1Password is generated with -W and 1Password itself is
# the thing protecting it.
if $DRY_RUN; then
    warn "dry-run: skipping signature"
else
    log "Signing SHA256SUMS..."
    KEYFILE="$(mktemp)"; chmod 600 "$KEYFILE"
    trap 'rm -f "$KEYFILE"' EXIT
    printf '%s\n' "$MINISIGN_SECRET_KEY" > "$KEYFILE"
    nix run nixpkgs#minisign -- -S -s "$KEYFILE" -m SHA256SUMS \
        -t "FluteOS $VERSION" -c "FluteOS $VERSION"
    rm -f "$KEYFILE"; trap - EXIT
fi

# ---------------------------------------------------------------- torrent

# Web seeds point at the CDN, so the torrent is useful from the first peer
# instead of only once somebody else has the file.
log "Making torrent..."
WEBSEEDS=()
for f in *.iso; do WEBSEEDS+=(-w "$BASE_URL/$f"); done
nix run nixpkgs#mktorrent -- \
    -a "udp://tracker.opentrackr.org:1337/announce" \
    -a "udp://open.demonii.com:1337/announce" \
    "${WEBSEEDS[@]}" \
    -n "fluteos-$VERSION" \
    -o "fluteos-$VERSION.torrent" \
    ./*.iso 2>/dev/null || warn "mktorrent failed; continuing without a torrent"

# ---------------------------------------------------------------- upload

put() {
    local src="$1" dst="$2"
    curl -sS --fail-with-body -X PUT \
        -H "AccessKey: $BUNNY_STORAGE_KEY" \
        -H "Content-Type: application/octet-stream" \
        --data-binary "@$src" \
        "https://$BUNNY_STORAGE_ENDPOINT/$BUNNY_STORAGE_ZONE/$dst" >/dev/null
}

if $DRY_RUN; then
    warn "dry-run: would upload to $BUNNY_STORAGE_ZONE/$REMOTE_DIR/"
    ls -lh
else
    for f in *; do
        log "Uploading $f..."
        put "$f" "$REMOTE_DIR/$f"
    done

    # A pointer file, not a copy of the images: `latest` as a duplicate would
    # double the stored bytes and, worse, make a cached CDN edge serve the
    # previous release under a URL that claims to be current.
    cat > latest.json <<EOF
{
  "version": "$VERSION",
  "images": [
$(for arch in "${TARGETS[@]}"; do
    printf '    {"arch": "%s", "url": "%s/fluteos-%s-%s.iso"},\n' \
        "$arch" "$BASE_URL" "$VERSION" "$arch"
done | sed '$ s/,$//')
  ],
  "checksums": "$BASE_URL/SHA256SUMS",
  "signature": "$BASE_URL/SHA256SUMS.minisig",
  "torrent": "$BASE_URL/fluteos-$VERSION.torrent"
}
EOF
    put latest.json "latest.json"
    log "Uploaded latest.json"

    # latest.json is the one file that must never be stale, so its edge copies
    # are dropped immediately rather than waiting out the cache TTL.
    curl -sS -X POST -H "AccessKey: $BUNNY_API_KEY" \
        "https://api.bunny.net/purge?url=https://$DL_HOST/latest.json&async=false" >/dev/null \
        && log "Purged latest.json from the edge"
fi

# ---------------------------------------------------------------- github

if $DRY_RUN; then
    warn "dry-run: would publish release v$VERSION"
else
    log "Creating GitHub release v$VERSION..."
    NOTES=$(cat <<EOF
Images are served from the CDN — they exceed GitHub's 2 GB asset limit.

| Architecture | Download |
|---|---|
$(for arch in "${TARGETS[@]}"; do
    printf '| %s | [fluteos-%s-%s.iso](%s/fluteos-%s-%s.iso) |\n' \
        "$arch" "$VERSION" "$arch" "$BASE_URL" "$VERSION" "$arch"
done)

Verify before writing to a disk:

\`\`\`
minisign -Vm SHA256SUMS -P <public key from README>
sha256sum -c SHA256SUMS
\`\`\`
EOF
)
    RELEASE=$(curl -sS --fail-with-body -X POST \
        -H "Authorization: Bearer $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github+json" \
        "https://api.github.com/repos/$GITHUB_OWNER/$GITHUB_REPO/releases" \
        -d "$(jq -n --arg t "v$VERSION" --arg b "$NOTES" \
            '{tag_name:$t, name:$t, body:$b, draft:true}')")

    UPLOAD_URL=$(echo "$RELEASE" | jq -r '.upload_url' | sed 's/{.*}//')
    [[ "$UPLOAD_URL" != "null" ]] || error "GitHub rejected the release: $RELEASE"

    for f in SHA256SUMS SHA256SUMS.minisig "fluteos-$VERSION.torrent" latest.json; do
        [[ -f "$f" ]] || continue
        log "Attaching $f..."
        curl -sS --fail-with-body -X POST \
            -H "Authorization: Bearer $GITHUB_TOKEN" \
            -H "Content-Type: application/octet-stream" \
            --data-binary "@$f" \
            "$UPLOAD_URL?name=$f" >/dev/null
    done

    # Left as a draft on purpose: publishing is the one step that announces the
    # release to the world, and it should be a human clicking it after checking
    # that the CDN really serves what the checksums claim.
    log "Draft release created. Review it, then publish:"
    log "  https://github.com/$GITHUB_OWNER/$GITHUB_REPO/releases"
fi

log "Done. $BASE_URL/"
