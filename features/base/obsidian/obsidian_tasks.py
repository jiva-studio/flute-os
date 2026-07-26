"""Waybar widget: shows Obsidian tasks count or selected task."""

import json
import os
import re
from pathlib import Path
from datetime import datetime, date

# Root directory holding the Obsidian vaults. Supplied by the Nix wrapper from
# features.base.obsidian.vaultRoot; None when unconfigured, in which case there
# is nothing to scan.
_vault_root = os.environ.get("OBSIDIAN_VAULT_ROOT", "").strip()
VAULT_ROOT = Path(_vault_root).expanduser() if _vault_root else None
CACHE_DIR = Path.home() / ".cache" / "obsidian-tasks"
SELECTION_FILE = CACHE_DIR / "selection.json"

# Task emoji patterns
DUE_PATTERN = re.compile(r'📅\s*(\d{4}-\d{2}-\d{2})')
SCHEDULED_PATTERN = re.compile(r'⏳\s*(\d{4}-\d{2}-\d{2})')
START_PATTERN = re.compile(r'🛫\s*(\d{4}-\d{2}-\d{2})')
TASK_PATTERN = re.compile(r'^[\s>]*-\s+\[([ x])\]\s+(.+)$', re.MULTILINE)


def parse_date(date_str):
    """Parse YYYY-MM-DD date string."""
    try:
        return datetime.strptime(date_str, '%Y-%m-%d').date()
    except ValueError:
        return None


def extract_tasks_from_file(file_path):
    """Extract incomplete tasks from a markdown file."""
    tasks = []
    try:
        content = file_path.read_text(encoding='utf-8')
        for match in TASK_PATTERN.finditer(content):
            status, text = match.groups()
            if status == ' ':  # Incomplete task
                task = {
                    'description': text.strip(),
                    'file': str(file_path),
                    'due': None,
                    'scheduled': None,
                    'start': None,
                }

                # Extract dates
                due_match = DUE_PATTERN.search(text)
                if due_match:
                    task['due'] = parse_date(due_match.group(1))

                scheduled_match = SCHEDULED_PATTERN.search(text)
                if scheduled_match:
                    task['scheduled'] = parse_date(scheduled_match.group(1))

                start_match = START_PATTERN.search(text)
                if start_match:
                    task['start'] = parse_date(start_match.group(1))

                tasks.append(task)
    except Exception:
        pass
    return tasks


def get_all_tasks():
    """Scan all vaults for tasks."""
    tasks = []
    if VAULT_ROOT is None or not VAULT_ROOT.exists():
        return tasks

    # Sort files for stable ordering across invocations
    for md_file in sorted(VAULT_ROOT.rglob('*.md')):
        # Skip hidden files and .obsidian directories
        if any(part.startswith('.') for part in md_file.parts):
            continue
        tasks.extend(extract_tasks_from_file(md_file))

    return tasks


def filter_tasks_for_today(tasks):
    """Filter tasks that are due/scheduled for today or overdue."""
    today = date.today()
    filtered = []

    for task in tasks:
        due = task.get('due')
        scheduled = task.get('scheduled')
        start = task.get('start')

        # Include if due today or overdue
        if due and due <= today:
            task['is_overdue'] = due < today
            task['is_today'] = due == today
            filtered.append(task)
        # Include if scheduled for today or earlier
        elif scheduled and scheduled <= today:
            task['is_overdue'] = scheduled < today
            task['is_today'] = scheduled == today
            filtered.append(task)
        # Include if start date is today or earlier
        elif start and start <= today:
            task['is_overdue'] = False
            task['is_today'] = True
            filtered.append(task)

    # Sort: overdue first, then by date
    filtered.sort(key=lambda t: (not t.get('is_overdue', False), t.get('due') or t.get('scheduled') or t.get('start') or today))

    return filtered


def clean_description(desc):
    """Remove date emojis from description for display."""
    desc = DUE_PATTERN.sub('', desc)
    desc = SCHEDULED_PATTERN.sub('', desc)
    desc = START_PATTERN.sub('', desc)
    return desc.strip()


def load_selection():
    """Load current selection."""
    try:
        if SELECTION_FILE.exists():
            return json.loads(SELECTION_FILE.read_text())
    except Exception:
        pass
    return None


def main():
    tasks = get_all_tasks()
    filtered = filter_tasks_for_today(tasks)

    selection = load_selection()

    overdue_count = sum(1 for t in filtered if t.get('is_overdue'))
    today_count = sum(1 for t in filtered if t.get('is_today'))
    total = len(filtered)

    # Build tooltip
    tooltip_parts = []
    if overdue_count > 0:
        tooltip_parts.append(f"Overdue: {overdue_count}")
    if today_count > 0:
        tooltip_parts.append(f"Today: {today_count}")
    tooltip = "\n".join(tooltip_parts) if tooltip_parts else "No tasks"

    # Determine CSS class
    if overdue_count > 0:
        css_class = "warning"
    elif today_count > 0:
        css_class = "has-tasks"
    else:
        css_class = "no-tasks"

    if selection and total > 0:
        # Show selected task with position indicator
        index = selection.get("index", 0)
        # Validate index is still valid
        if index >= total:
            index = 0

        desc = clean_description(filtered[index].get('description', 'Task'))

        # Truncate description if too long
        max_len = 25
        if len(desc) > max_len:
            desc = desc[:max_len-1] + "..."

        output = {
            "text": f"<span size='16pt' rise='-2pt'>󱓧</span> [{index+1}/{total}] {desc}",
            "tooltip": f"Selected: {filtered[index].get('description', 'Task')}\n{tooltip}",
            "class": css_class
        }
    elif total > 0:
        output = {
            "text": f"<span size='16pt' rise='-2pt'>󱓧</span> {total}",
            "tooltip": tooltip,
            "class": css_class
        }
    else:
        output = {
            "text": "<span size='16pt' rise='-2pt'>󱓧</span>",
            "tooltip": "No tasks for today",
            "class": "no-tasks"
        }

    print(json.dumps(output))


if __name__ == "__main__":
    main()
