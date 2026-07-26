---
name: fluteos-docs-generate
description: Generate or refresh internal documentation in ../docs/. Knows the conventions: Mermaid diagrams for everything, standard sections (architecture/modules/db/api/runbooks), autogen blocks wrapped in HTML markers. Use when the user asks to 'document', 'add a doc', 'generate docs', or 'update the architecture diagram'.
---

## When to use

- User asks to document a new module / endpoint / flow / table.
- User asks to refresh / regenerate existing autogen blocks.
- After major code changes (new repo added, schema migration, API rename).

## Conventions (read these before writing)

1. **Standard sections** under `../docs/` (create on demand — they don't exist by default):
   - `architecture/` — system overview, component boundaries, data flow (Mermaid `graph TD`).
   - `modules/<module>.md` — per-module deep dives.
   - `db/` — ER diagrams (Mermaid `erDiagram`), schema docs, migration notes.
   - `api/` — endpoint reference, request/response examples.
   - `runbooks/` — how-to / on-call / debug recipes.
   - `repos/<repo>/README.md` — auto-generated stub per repo (don't write here directly; `fluteos-docs-init --rescan` refreshes).

2. When you create a new top-level section, also add a link to it in `../docs/_navbar.md` and `../docs/_sidebar.md`.

3. **Every page starts with a one-paragraph summary** (LLM-friendly). Then optional frontmatter block. Then content.

4. **Diagrams in Mermaid** (rendered by docsify-mermaid plugin):
   - System architecture: ` ```mermaid\ngraph TD\n  A[Client] --> B[API]\n``` `
   - DB schema: ` ```mermaid\nerDiagram\n  USER ||--o{ ORDER : places\n``` `
   - Sequence: ` ```mermaid\nsequenceDiagram\n  Alice->>Bob: hi\n``` `
   - State: ` ```mermaid\nstateDiagram-v2\n  [*] --> Idle\n``` `

5. **Auto-generated blocks** (`<!-- BEGIN AUTOGEN -->` … `<!-- END AUTOGEN -->`) — read user content outside before writing inside. Use `fluteos-docs-init --rescan` for the standard scaffolding pages (README, _sidebar, repos/*).

## Workflow

1. Read `../docs/_sidebar.md` and `../docs/README.md` to understand current structure.
2. `fluteos-docs-init --rescan` to refresh standard scaffolding.
3. Open or create the relevant page under the right section.
4. Write summary → diagrams → details.
5. After writing, suggest the user run `fluteos-docs-serve` + `docs-open <new-page>` to verify.
