#!/usr/bin/env bash
# fluteos-docs-pages [project-id-or-dir]
#
# Emit JSON list of doc *headings* (not just files) for fuzzy menu — searching
# by file name alone is rarely what you want; you want to jump to a section.
#
# For each H1–H4 in every .md (excluding sidebar/navbar partials), emit:
#   label: "<page-path> › <heading text>"   (root → just the heading)
#   action: open the page at the heading's docsify anchor
#
# Output: [{label, action: {exec: ["fluteos-docs-open", "<id>", "<page>#<anchor>"]}}]

set -uo pipefail

# shellcheck source=./_resolve-workspace.sh
source "$RESOLVE_HELPER"

if ! resolve_workspace "${1:-}" || [ ! -d "$DOCS_DIR" ]; then
  echo "[]"
  exit 0
fi

python3 - "$DOCS_DIR" "$PROJECT_ID" <<'PY'
import json, os, re, sys

docs_dir, project_id = sys.argv[1], sys.argv[2]

# Mirror docsify v4 slugify exactly (lib/docsify.js, function slugify):
#   trim → ASCII uppercase to lower → strip HTML tags → drop chars matched by
#   the punctuation regex below → whitespace to hyphen → collapse runs of
#   hyphens → prepend "_" when first char is a digit. Dup counter per page.
# `_` and `-` are NOT in the punctuation set, so they survive — important for
# code-fence-style headings like "User notes (`_v: 1`)" → "user-notes-_v-1".
_DOCSIFY_PUNCT = re.compile(
    r"[ -⁯⸀-⹿\\'!\"#$%&()*+,./:;<=>?@\[\]^`{|}~]"
)
_TAG_RE = re.compile(r'<[^>]+>')

def docsify_slugify(text, page_cache):
    if not isinstance(text, str):
        return ''
    s = text.strip()
    # ASCII /[A-Z]+/g → lower (matches docsify; non-Latin uppercase untouched)
    s = re.sub(r'[A-Z]+', lambda m: m.group(0).lower(), s)
    s = _TAG_RE.sub('', s)
    s = _DOCSIFY_PUNCT.sub('', s)
    s = re.sub(r'\s', '-', s)
    s = re.sub(r'-+', '-', s)
    s = re.sub(r'^(\d)', r'_\1', s)
    n = page_cache.get(s, -1) + 1
    page_cache[s] = n
    return f"{s}-{n}" if n else s

def strip_md(text):
    """Remove inline markdown so heading text reads cleanly in a fuzzy menu.

    Handles: `code`, **bold**, *em*, _em_, [text](url), ~~strike~~. Conservative —
    only the wrappers, never the content. Anchor slug is computed from the
    *cleaned* text so "Foo `bar`" → slug "foo-bar" matches docsify's behavior.
    """
    # Links: [text](url) → text
    text = re.sub(r'\[([^\]]+)\]\([^)]+\)', r'\1', text)
    # Code spans: `code` → code  (handle ``code`` too)
    text = re.sub(r'`+([^`]+)`+', r'\1', text)
    # Bold/italic wrappers: **x**, __x__, *x*, _x_
    text = re.sub(r'\*\*([^*]+)\*\*', r'\1', text)
    text = re.sub(r'__([^_]+)__', r'\1', text)
    text = re.sub(r'\*([^*]+)\*', r'\1', text)
    text = re.sub(r'(?<!\w)_([^_]+)_(?!\w)', r'\1', text)
    # Strikethrough
    text = re.sub(r'~~([^~]+)~~', r'\1', text)
    return text.strip()

def parse_headings(path):
    """Yield (level, text) for ATX headings, skipping fenced code blocks.
    Heading text is stripped of inline markdown formatting."""
    in_fence = False
    fence_re = re.compile(r'^\s*(```|~~~)')
    heading_re = re.compile(r'^(#{1,4})\s+(.+?)\s*#*\s*$')
    with open(path, encoding='utf-8', errors='replace') as f:
        for line in f:
            if fence_re.match(line):
                in_fence = not in_fence
                continue
            if in_fence:
                continue
            m = heading_re.match(line)
            if m:
                yield len(m.group(1)), strip_md(m.group(2).strip())

def page_path(rel):
    # README.md → ""  (docsify root); foo/bar.md → foo/bar
    if rel == 'README.md':
        return ''
    if rel.endswith('/README.md'):
        return rel[:-len('/README.md')] + '/'
    return rel[:-len('.md')] if rel.endswith('.md') else rel

# First pass: collect (text, page, target). Second pass: emit labels — bare
# heading text by default; suffix " (<page>)" only when the same heading
# appears in multiple pages, so the menu stays clean.
raw = []
for root, dirs, files in os.walk(docs_dir):
    dirs[:] = [d for d in dirs if not d.startswith('.')]
    for name in sorted(files):
        if not name.endswith('.md') or name.startswith('_'):
            continue
        full = os.path.join(root, name)
        rel = os.path.relpath(full, docs_dir)
        page = page_path(rel)
        # docsify resets its slug cache per page, so do the same.
        page_slug_cache = {}
        had_heading = False
        for level, text in parse_headings(full):
            had_heading = True
            anchor = docsify_slugify(text, page_slug_cache) or 'section'
            raw.append((text, page, f"{page}#{anchor}"))
        if not had_heading:
            raw.append((page or '(root)', page, page))

# Disambiguate duplicates by the bare label.
from collections import Counter
counts = Counter(text for text, _, _ in raw)
entries = []
for text, page, target in raw:
    label = text if counts[text] == 1 or not page else f"{text}  ·  {page}"
    entries.append({
        'label': label,
        'action': {'exec': ['fluteos-docs-open', project_id, target]},
    })

entries.sort(key=lambda e: e['label'].lower())
json.dump(entries, sys.stdout, ensure_ascii=False)
PY
