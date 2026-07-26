---
name: fluteos-repo-scan
description: Scan all repositories under ../source/. Returns inventory: name, remote URL, README first paragraph, detected stack (package.json/pyproject.toml/Cargo.toml/flake.nix/go.mod). Use when the user asks 'what's in this project' or you need a fresh map of the codebase.
---

## When to use

- First time exploring a project; user asks 'what is this' or 'show me the repos'.
- After adding a new repository to `projects.<p>.repos` in Nix config and running activation.
- Before generating docs, to ground yourself in the actual current code.

## How to use

1. List directories: `ls -1 ../source/`.
2. For each: read README.md (head), `git -C ../source/<r> remote get-url origin`, detect stack via package.json / pyproject.toml / Cargo.toml / flake.nix / go.mod.
3. Report a structured inventory back to the user (markdown table works well).

## Output template

| Repo | Remote | Stack | One-line description |
|---|---|---|---|
| name | git@host/x | Node/TS | summary from README |
