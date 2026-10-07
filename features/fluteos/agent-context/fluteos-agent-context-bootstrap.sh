#!/usr/bin/env bash
# fluteos-agent-context-bootstrap [project-dir]
#
# Idempotently scaffolds <project>/agent/ with:
#   - CLAUDE.md (fluteos-managed block + USER NOTES below)
#   - .claude/skills/fluteos-{repo-scan,docs-generate,docs-serve,docs-open,agent-skill-new}/SKILL.md
#   - .gitignore
#
# Cheap state check: SHA of (HEAD of each repo + repo list). Skips regen if matches.

set -uo pipefail

PROJECT_DIR="${1:-${WORKSPACE_CWD:-$PWD}}"
AGENT_DIR="$PROJECT_DIR/agent"
SOURCE_DIR="$PROJECT_DIR/source"

PROJECT_NAME="$(basename "$PROJECT_DIR")"
GROUP_NAME="$(basename "$(dirname "$PROJECT_DIR")")"
WS_ID="${GROUP_NAME}:${PROJECT_NAME}"

mkdir -p "$AGENT_DIR/.claude/skills"

# --- Fastest path: if CLAUDE.md is newer than every source/<r>/.git/HEAD,
# nothing changed since last bootstrap — skip everything (including the per-repo
# git rev-parse loop). Direnv calls this on every cd into the project; for
# multi-repo projects this saves ~10ms per cd.
if [ -f "$AGENT_DIR/CLAUDE.md" ] && [ -d "$SOURCE_DIR" ]; then
  newest_head=$(find "$SOURCE_DIR" -mindepth 2 -maxdepth 3 -name HEAD -path '*/.git/HEAD' -printf '%T@\n' 2>/dev/null | sort -nr | head -1)
  claude_mtime=$(stat -c '%Y' "$AGENT_DIR/CLAUDE.md" 2>/dev/null)
  if [ -n "$newest_head" ] && [ -n "$claude_mtime" ]; then
    # head mtime is a float (sub-second); ceil it to the next integer second so
    # a commit + cd within the same wall-clock second still triggers regen.
    # Skip only when CLAUDE.md is *strictly newer* than the ceiled HEAD time.
    head_ts=$(( ${newest_head%.*} + 1 ))
    if [ "$claude_mtime" -gt "$head_ts" ]; then
      exit 0
    fi
  fi
fi

# --- Compute cheap state hash from repo HEADs + list ---
STATE_INPUT=""
if [ -d "$SOURCE_DIR" ]; then
  while IFS= read -r repo; do
    [ -z "$repo" ] && continue
    if [ -d "$SOURCE_DIR/$repo/.git" ]; then
      head=$(git -C "$SOURCE_DIR/$repo" rev-parse HEAD 2>/dev/null || echo "no-head")
      STATE_INPUT+="${repo}=${head}"$'\n'
    else
      STATE_INPUT+="${repo}=no-git"$'\n'
    fi
  done < <(find "$SOURCE_DIR" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort)
fi
STATE_SHA="$(printf '%s' "$STATE_INPUT" | sha256sum | cut -d' ' -f1 | cut -c1-16)"

# Second fast path: if SHA matches what's in the existing CLAUDE.md, skip regen
if [ -f "$AGENT_DIR/CLAUDE.md" ] && grep -q "<!-- fluteos-state: ${STATE_SHA} -->" "$AGENT_DIR/CLAUDE.md"; then
  exit 0
fi

# --- Build repo inventory for CLAUDE.md ---
mk_repo_list() {
  if [ -z "$STATE_INPUT" ]; then
    echo "_(no repositories yet — clone or add via Nix \`projects.<p>.repos.<r>.url\`)_"
    return
  fi
  while IFS= read -r repo; do
    [ -z "$repo" ] && continue
    remote=""
    if [ -d "$SOURCE_DIR/$repo/.git" ]; then
      remote="$(git -C "$SOURCE_DIR/$repo" remote get-url origin 2>/dev/null || true)"
    fi
    head_para=""
    if [ -f "$SOURCE_DIR/$repo/README.md" ]; then
      # First non-heading paragraph, capped at a few lines (line-bounded so we
      # don't slice a UTF-8 codepoint mid-byte the way `head -c` would).
      head_para="$(awk '
        /^[^#[:space:]]/ { print; n++; if (n>=2) exit }
        n>0 && /^$/ { exit }
        n>0 { print; n++; if (n>=3) exit }
      ' "$SOURCE_DIR/$repo/README.md" 2>/dev/null)"
    fi
    printf -- "- **%s** — \`%s\`\n" "$repo" "${remote:-no remote}"
    [ -n "$head_para" ] && printf "  %s\n" "$head_para"
  done < <(find "$SOURCE_DIR" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort)
}

REPO_LIST="$(mk_repo_list)"

# --- Write CLAUDE.md ---
MANAGED_BLOCK="$(cat <<MD
<!-- fluteos-state: ${STATE_SHA} -->
<!-- fluteos-managed: do not edit this block. Re-run \`fluteos-agent-context-bootstrap\` to refresh. Anything below \`<!-- USER NOTES -->\` is preserved. -->

# ${PROJECT_NAME}

**Group:** ${GROUP_NAME}
**Workspace ID:** \`${WS_ID}\`
**Project root:** \`${PROJECT_DIR}\`

You are running inside this project's \`agent/\` directory. The other folders at \`../\` are:

- \`../source/\` — git checkouts (one folder per repo, see list below)
- \`../docs/\` — internal documentation site (docsify; serve with \`fluteos-docs-serve\`)
- \`../resources/\` — user-managed assets (binaries, scratch, drafts)
- \`../.config/\` — project-local secrets and configs (do not commit content)

## Repositories under \`../source/\`

${REPO_LIST}

## How to work in this project

1. **Read source first.** All code lives under \`../source/<repo>/\`. Use \`Glob\` and \`Read\`. The \`repo-scan\` skill gives a quick inventory.
2. **Documentation lives in \`../docs/\`.** It is the human-readable companion to source code. When the user asks "find/show/generate docs", that's where you go.
3. **When generating docs**, use the \`docs-generate\` skill. It knows the conventions:
   - Diagrams: Mermaid for everything (\`graph TD\`, \`erDiagram\`, \`sequenceDiagram\`, \`stateDiagram-v2\`).
   - Standard sections: \`architecture/\`, \`modules/\`, \`db/\`, \`api/\`, \`runbooks/\`.
   - Each page starts with a one-paragraph summary; deep code/concept references go below.
   - Auto-blocks wrapped in \`<!-- BEGIN AUTOGEN -->\` / \`<!-- END AUTOGEN -->\` — only edit inside on regen.
4. **When serving/showing docs**, use the \`docs-serve\` and \`docs-open\` skills.
5. **Project-local skills** live in \`./.claude/skills/\`. Add new ones with the \`fluteos-agent-skill-new\` skill (namespace-action format: \`docs-foo\`, \`repo-bar\`, \`db-baz\`).
6. **Git lives in the repos, not here.** This directory is not a git working
   tree, so anything that reads a diff — \`git\`, \`revdiff\`, a review skill —
   must be pointed at \`../source/<repo>/\` (run it there, or pass that path).
   Claude Code's own \`/diff\` panel reads the current directory only and stays
   empty in this workspace; that is the layout, not a fault. \`/diff\` hides it.

## Quick commands

- \`fluteos-docs-serve\` — start docsify server, prints URL
- \`fluteos-docs-open <page>\` — open a doc page in browser at URL
- \`fluteos-docs-init --rescan\` — refresh autogen blocks in docs
- \`fluteos-agent-context-bootstrap\` — regenerate this file when source changes

## Database / schema docs

If any repo has a database, generate an ER diagram into \`../docs/db/\` using Mermaid \`erDiagram\` syntax. Look for: \`schema.sql\`, \`migrations/\`, \`prisma/schema.prisma\`, \`models/\`, ORM annotations.

<!-- END fluteos-managed -->

<!-- USER NOTES -->
<!-- Everything below this marker is preserved across regeneration. Replace these
     stubs with project-specific content. -->

## Project conventions

<!-- Coding conventions, branch naming, commit style, PR rules. Examples:
     - Conventional commits enforced
     - Feature branches: feat/<ticket>-<slug>
     - All UI strings go through i18n
-->

## Glossary

<!-- Domain-specific terms an AI/new contributor wouldn't know. Examples:
     - "Realm" — a curriculum unit (entities/realms.ts)
     - "FLI" — Filevine integration adapter
-->

## Known gotchas

<!-- Things that look obvious but aren't. Examples:
     - Tests need DOTENV_LOCAL set or DB calls hang silently
     - The build script renames foo.js → foo.bundle.js; chase the bundle name when debugging
-->
MD
)"

# Write CLAUDE.md, preserving USER NOTES tail if present
CLAUDE_MD="$AGENT_DIR/CLAUDE.md"
if [ -f "$CLAUDE_MD" ] && grep -q '<!-- USER NOTES -->' "$CLAUDE_MD"; then
  # Capture content AFTER the marker (next skips the marker line itself, so re-runs
  # don't accumulate duplicate <!-- USER NOTES --> lines).
  USER_NOTES="$(awk '/<!-- USER NOTES -->/{found=1; next} found{print}' "$CLAUDE_MD")"
  # Write managed block (already contains its own USER NOTES marker), then preserved tail.
  printf '%s\n' "${MANAGED_BLOCK%%<!-- USER NOTES -->*}<!-- USER NOTES -->" > "$CLAUDE_MD"
  printf '%s\n' "$USER_NOTES" >> "$CLAUDE_MD"
else
  printf '%s\n' "$MANAGED_BLOCK" > "$CLAUDE_MD"
fi

# --- .gitignore ---
if [ ! -f "$AGENT_DIR/.gitignore" ]; then
  cat > "$AGENT_DIR/.gitignore" <<'GI'
# Claude Code session state
*.session.json
.local/
.cache/
GI
fi

# --- Skill scaffolds ---
# Templates live as separate .md files in $SKILLS_SRC_DIR (set by the Nix wrapper).
# Each file becomes ./.claude/skills/<basename>/SKILL.md. Existing skills are not
# touched (idempotent), letting the user safely customise per project.
SKILL_DIR="$AGENT_DIR/.claude/skills"
mkdir -p "$SKILL_DIR"

if [ -n "${SKILLS_SRC_DIR:-}" ] && [ -d "$SKILLS_SRC_DIR" ]; then
  for src in "$SKILLS_SRC_DIR"/*.md; do
    [ -e "$src" ] || continue
    name="$(basename "$src" .md)"
    target_dir="$SKILL_DIR/$name"
    target_file="$target_dir/SKILL.md"
    if [ ! -f "$target_file" ]; then
      mkdir -p "$target_dir"
      cp "$src" "$target_file"
    fi
  done
fi

exit 0
