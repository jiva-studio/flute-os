#!/usr/bin/env bash
# Verify every output of this flake still evaluates.
#
# It forces the FULL module fixpoint (system.build.toplevel), not a shallow
# attribute like networking.hostName: a shallow read does not reach the
# home-manager modules, which is exactly where breakage hides. Nothing is built,
# so it is cheap enough to run after every change.
#
# It checks EVERY output the repo is supposed to have — both host templates and
# both installer images. Checking one host was not enough: it passed happily
# while the x86_64 template did not exist at all, and `nix flake show` and the
# default x86_64 package were broken on a clean clone.
#
# The name is historical. This script used to copy the tree with the author's
# `personal/` directory removed, to prove nothing under features/ depended on it.
# That directory now lives in a separate repository, so the property it was
# guarding is structural and the copy is gone; what remains is the part that
# still earns its keep.
#
# Usage: ./check-distributable.sh [config ...]   (default: pc live iso iso-arm)
set -euo pipefail

TARGETS=("$@")
if [[ ${#TARGETS[@]} -eq 0 ]]; then
  TARGETS=(pc live iso iso-arm)
fi
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ERRLOG="$(mktemp)"
trap 'rm -f "$ERRLOG"' EXIT

failed=0
for target in "${TARGETS[@]}"; do
  printf '=== %-8s ' "$target"
  # The WORKING tree (path:), not the git tree (.#): an uncommitted change must
  # be what gets checked, or the check reports on the previous commit.
  #
  # stderr to a file, not into $out: nixpkgs' evaluation warnings would otherwise
  # be printed as if they were the derivation path.
  if out="$(nix --extra-experimental-features 'nix-command flakes' eval --raw \
      "path:$REPO#nixosConfigurations.$target.config.system.build.toplevel.drvPath" \
      2>"$ERRLOG")"; then
    echo "OK  $out"
  else
    echo "FAILED"
    sed 's/^/      /' "$ERRLOG" >&2
    failed=1
  fi
done

echo
if [[ $failed -eq 0 ]]; then
  echo "OK — every configuration evaluates."
else
  echo "FAILED — see the errors above." >&2
  exit 1
fi
