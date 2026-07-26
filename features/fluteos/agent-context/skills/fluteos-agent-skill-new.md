---
name: fluteos-agent-skill-new
description: Scaffold a new project-local skill in ./.claude/skills/<namespace>-<action>/SKILL.md. Use when the user asks to 'add a skill', 'create a skill for X'. Enforces namespace-action naming convention.
---

## When to use

- User asks to add a project-specific skill, e.g., 'create a skill for running migrations'.

## Naming convention (enforced)

Format: `<namespace>-<action>`. Examples: `docs-foo`, `repo-baz`, `db-migrate`, `deploy-staging`. **No spaces, no slashes, no underscores in the name.** Lowercase only.

Reject names that don't follow the format and explain the convention before retrying.

## How to use

1. Choose namespace: `docs`, `repo`, `agent`, `db`, `api`, `build`, `deploy`, `test` (extend if needed).
2. Choose action verb (run, scan, generate, refresh, open, stop, …).
3. Create `./.claude/skills/<name>/SKILL.md` with frontmatter:

   ```
   ---
   name: <namespace>-<action>
   description: When to use (one sentence). What it does (one sentence).
   ---

   ## When to use
   ...

   ## How to use
   ...
   ```

4. Tell the user the new skill is project-local (won't leak to other projects).
