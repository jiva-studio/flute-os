#!/usr/bin/env bash
# fluteos-docs-serve [project-id-or-dir]
#
# Returns the URL of the per-project docsify server.
#
# The server itself runs as a declarative `systemd --user` service defined
# in features/fluteos/docs/default.nix and started at login. This script
# does not start, stop, or own the server — it only resolves the URL from
# the registry so callers (fluteos-docs-open, etc.) can hand it to a browser.
#
# Output: "URL=http://127.0.0.1:<port>" on stdout.

set -uo pipefail

# shellcheck source=./_resolve-workspace.sh
source "$RESOLVE_HELPER"

if ! resolve_workspace "${1:-}"; then
  echo "fluteos-docs-serve: cannot resolve workspace (no arg, no \$WORKSPACE_CWD, no focused niri workspace)" >&2
  exit 2
fi

if [ -z "${DOCS_PORT:-}" ]; then
  echo "fluteos-docs-serve: no docsPort configured for '$PROJECT_ID'" >&2
  echo "fluteos-docs-serve: add 'docsPort = <port>;' to the project's fluteos definition" >&2
  exit 6
fi

echo "URL=http://127.0.0.1:${DOCS_PORT}"
