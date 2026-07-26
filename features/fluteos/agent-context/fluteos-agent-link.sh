#!/usr/bin/env bash
# fluteos-agent-link <repo> [options]
#
# Move a project's agent skills / docs / MCP config INTO a git repository under
# source/<repo>/ (using standard, agent-agnostic conventions so any clone of the
# repo gets them natively), then replace the originals with RELATIVE symlinks so
# the local agent workspace keeps working unchanged.
#
# Why symlinks point INTO the repo (not the reverse): git tracks file *content*,
# not symlinks-to-elsewhere. The single physical copy must live in the repo
# working tree; `git pull` then updates it in place and local edits are already
# staged-able. Relative links keep this valid across Syncthing'd machines.
#
# Repo layout written (all standard — a plain `git clone` + Claude Code from the
# repo root picks these up with zero extra setup):
#   <repo>/.claude/skills/   <- agent/.claude/skills
#   <repo>/docs/             <- <project>/docs   (docsify site; coexists with any existing docs)
#   <repo>/.mcp.json         <- agent/.mcp.json  (SHARED servers; commit this)
#
# Private/personal MCP servers stay OUT of the repo: add them with
#   claude mcp add --scope local <name> ...
# which lands in ~/.claude.json keyed by the agent dir, never in the repo.
#
# Usage:
#   fluteos-agent-link <repo> [--include skills,docs,mcp] [--project DIR]
#                             [--dry-run] [--status] [--unlink]
#
#   --include LIST   comma list of components to act on (default: skills,docs,mcp)
#   --project DIR    workspace root (default: $WORKSPACE_CWD or $PWD)
#   --dry-run        print actions, change nothing
#   --status         show current link state and exit
#   --unlink         reverse: restore a real local copy, leave the repo copy intact

set -uo pipefail

REPO_NAME=""
INCLUDE="skills,docs,mcp"
PROJECT="${WORKSPACE_CWD:-$PWD}"
DRY=0
MODE="link"

die() { printf 'error: %s\n' "$1" >&2; exit 1; }
note() { printf '%s\n' "$1" >&2; }

while [ $# -gt 0 ]; do
  case "$1" in
    --include) INCLUDE="$2"; shift 2;;
    --project) PROJECT="$2"; shift 2;;
    --dry-run) DRY=1; shift;;
    --status)  MODE="status"; shift;;
    --unlink)  MODE="unlink"; shift;;
    -h|--help) sed -n '2,40p' "$0"; exit 0;;
    -*) die "unknown option: $1";;
    *)  [ -z "$REPO_NAME" ] && REPO_NAME="$1" && shift || die "unexpected arg: $1";;
  esac
done

[ -n "$REPO_NAME" ] || die "missing <repo> (a folder under source/)"
PROJECT="$(cd "$PROJECT" 2>/dev/null && pwd)" || die "bad --project"
AGENT="$PROJECT/agent"
REPO="$PROJECT/source/$REPO_NAME"

[ -d "$REPO" ] || die "no repo at $REPO"
[ "$MODE" = "status" ] || [ -d "$REPO/.git" ] || die "$REPO is not a git repo"

# component <name> -> local path | repo path | type(dir|file)
component() {
  case "$1" in
    skills) echo "$AGENT/.claude/skills|$REPO/.claude/skills|dir";;
    docs)   echo "$PROJECT/docs|$REPO/docs|dir";;
    mcp)    echo "$AGENT/.mcp.json|$REPO/.mcp.json|file";;
    *) die "unknown component: $1";;
  esac
}

run() { # echo + (maybe) execute
  note "  + $*"
  [ "$DRY" -eq 1 ] || "$@"
}

rel_ln() { # rel_ln <target> <linkname>  — relative, force, no-deref
  run ln -srfn "$1" "$2"
}

link_one() {
  local spec lpath rpath typ
  spec="$(component "$1")"; lpath="${spec%%|*}"; rpath="$(echo "$spec" | cut -d'|' -f2)"; typ="${spec##*|}"

  if [ -L "$lpath" ]; then
    local cur; cur="$(readlink -f "$lpath" 2>/dev/null)"
    if [ "$cur" = "$(readlink -f "$rpath" 2>/dev/null)" ]; then
      note "[$1] already linked -> $rpath"; return
    fi
    note "[$1] WARN: already a symlink to $cur (expected $rpath); skipping"; return
  fi

  run mkdir -p "$(dirname "$rpath")"

  if [ -e "$rpath" ] && [ -e "$lpath" ]; then
    # both real exist -> merge local into repo, repo wins on conflicts
    if [ "$typ" = "dir" ]; then
      note "[$1] merging local into existing repo dir (repo wins on conflict)"
      run cp -rn "$lpath/." "$rpath/" 2>/dev/null || run cp -rn "$lpath/" "$rpath/"
      run rm -rf "$lpath"
    else
      note "[$1] repo file already exists; backing up local as $lpath.local-bak"
      run mv "$lpath" "$lpath.local-bak"
    fi
  elif [ -e "$lpath" ]; then
    note "[$1] moving local -> repo"
    run mv "$lpath" "$rpath"
  elif [ -e "$rpath" ]; then
    note "[$1] repo copy exists, local missing — linking only"
  else
    note "[$1] nothing local or in repo"
    [ "$typ" = "dir" ] && run mkdir -p "$rpath" || { note "[$1] skip (no file to link)"; return; }
  fi

  rel_ln "$rpath" "$lpath"
  note "[$1] linked $lpath -> $rpath"
}

unlink_one() {
  local spec lpath rpath
  spec="$(component "$1")"; lpath="${spec%%|*}"; rpath="$(echo "$spec" | cut -d'|' -f2)"
  if [ ! -L "$lpath" ]; then note "[$1] not a symlink; nothing to undo"; return; fi
  local tgt; tgt="$(readlink -f "$lpath")"
  run rm -f "$lpath"
  run cp -r "$tgt" "$lpath"
  note "[$1] restored real local copy from $tgt (repo copy kept)"
}

status_one() {
  local spec lpath rpath
  spec="$(component "$1")"; lpath="${spec%%|*}"; rpath="$(echo "$spec" | cut -d'|' -f2)"
  if [ -L "$lpath" ]; then
    printf '  %-7s linked -> %s\n' "$1" "$(readlink "$lpath")"
  elif [ -e "$lpath" ]; then
    printf '  %-7s LOCAL (not linked)\n' "$1"
  else
    printf '  %-7s absent\n' "$1"
  fi
}

IFS=',' read -r -a COMPONENTS <<< "$INCLUDE"

case "$MODE" in
  status)
    note "agent-link status for $REPO:"
    for c in "${COMPONENTS[@]}"; do status_one "$c"; done
    exit 0;;
  unlink)
    for c in "${COMPONENTS[@]}"; do unlink_one "$c"; done
    exit 0;;
  link)
    for c in "${COMPONENTS[@]}"; do link_one "$c"; done
    # Local-only ignores inside the tracked .claude/ folder.
    GI="$REPO/.claude/.gitignore"
    if [ ! -e "$GI" ]; then
      run mkdir -p "$REPO/.claude"
      if [ "$DRY" -eq 0 ]; then
        cat > "$GI" <<'IGN'
# Machine-local Claude Code state — never commit
settings.local.json
*.local.json
*.session.json
.cache/
IGN
      fi
      note "wrote $GI"
    fi
    note ""
    note "done. Review with: git -C \"$REPO\" status"
    note "Shared MCP servers live in $REPO/.mcp.json (commit them)."
    note "Personal MCP servers: claude mcp add --scope local <name> ... (stays in ~/.claude.json)"
    exit 0;;
esac
