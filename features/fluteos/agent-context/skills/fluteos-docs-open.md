---
name: fluteos-docs-open
description: Open a specific doc page in the browser at the right URL (deep-link supported). Use when the user asks to 'show me the auth docs', 'open the architecture page', 'show the ER diagram'. Calls docs-serve automatically.
---

## When to use

- User asks to view a specific doc page or section.
- After `fluteos-docs-generate` to verify the result.

## How to use

`fluteos-docs-open <page>` where page is path under `docs/`:

- `fluteos-docs-open architecture` → opens `architecture/README.md`
- `fluteos-docs-open modules/auth` → opens `modules/auth.md` (or `/README.md` if folder)
- `fluteos-docs-open db#users-table` → opens `db/README.md` scrolled to `#users-table` anchor

If unsure which page matches a query, use `fluteos-docs-pages` first to list all pages.
