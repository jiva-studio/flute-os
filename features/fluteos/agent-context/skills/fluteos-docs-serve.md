---
name: fluteos-docs-serve
description: Returns the URL of the per-project docsify server. The server itself is a declarative systemd --user unit started at login — no manual start/stop needed. Use before opening any doc page.
---

## When to use

- User asks to 'open documentation' / 'show me the docs' — call this to get the URL.
- Auto-invoke before `fluteos-docs-open` if you need the URL.

## How to use

Run `fluteos-docs-serve` (no args, uses current workspace).
The output line `URL=http://127.0.0.1:<port>` is what you tell the user.

The docsify server runs as a systemd user service that is started automatically.
There is no `fluteos-docs-stop` and no need to start the server manually — if it
is not running, that is a configuration bug, not user error.
