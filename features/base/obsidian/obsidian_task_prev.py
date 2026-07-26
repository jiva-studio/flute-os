"""Select previous task in the list (wrap-around)."""

import json
import os
import subprocess
import re
from pathlib import Path
from datetime import datetime, date

# Root directory holding the Obsidian vaults. Supplied by the Nix wrapper from
# features.base.obsidian.vaultRoot; None when unconfigured.
_vault_root = os.environ.get("OBSIDIAN_VAULT_ROOT", "").strip()
VAULT_ROOT = Path(_vault_root).expanduser() if _vault_root else None
CACHE_DIR = Path.home() / ".cache" / "obsidian-tasks"
SELECTION_FILE = CACHE_DIR / "selection.json"

DUE_PATTERN = re.compile(r'📅\s*(\d{4}-\d{2}-\d{2})')
SCHEDULED_PATTERN = re.compile(r'⏳\s*(\d{4}-\d{2}-\d{2})')
START_PATTERN = re.compile(r'🛫\s*(\d{4}-\d{2}-\d{2})')
TASK_PATTERN = re.compile(r'^[\s>]*-\s+\[([ x])\]\s+(.+)$', re.MULTILINE)


def parse_date(date_str):
    try:
        return datetime.strptime(date_str, '%Y-%m-%d').date()
    except ValueError:
        return None


def extract_tasks_from_file(file_path):
    tasks = []
    try:
        content = file_path.read_text(encoding='utf-8')
        for match in TASK_PATTERN.finditer(content):
            status, text = match.groups()
            if status == ' ':
                task = {
                    'description': text.strip(),
                    'file': str(file_path),
                    'due': None,
                    'scheduled': None,
                    'start': None,
                }

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
    tasks = []
    if VAULT_ROOT is None or not VAULT_ROOT.exists():
        return tasks

    # Sort files for stable ordering across invocations
    for md_file in sorted(VAULT_ROOT.rglob('*.md')):
        if any(part.startswith('.') for part in md_file.parts):
            continue
        tasks.extend(extract_tasks_from_file(md_file))

    return tasks


def filter_tasks_for_today(tasks):
    today = date.today()
    filtered = []

    for task in tasks:
        due = task.get('due')
        scheduled = task.get('scheduled')
        start = task.get('start')

        if due and due <= today:
            task['is_overdue'] = due < today
            task['is_today'] = due == today
            filtered.append(task)
        elif scheduled and scheduled <= today:
            task['is_overdue'] = scheduled < today
            task['is_today'] = scheduled == today
            filtered.append(task)
        elif start and start <= today:
            task['is_overdue'] = False
            task['is_today'] = True
            filtered.append(task)

    filtered.sort(key=lambda t: (not t.get('is_overdue', False), t.get('due') or t.get('scheduled') or t.get('start') or today))

    return filtered


def load_selection():
    try:
        if SELECTION_FILE.exists():
            return json.loads(SELECTION_FILE.read_text())
    except Exception:
        pass
    return None


def save_selection(index, total, file_path):
    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    selection = {
        "index": index,
        "total": total,
        "file": file_path
    }
    SELECTION_FILE.write_text(json.dumps(selection))


def signal_waybar():
    subprocess.run(["pkill", "-SIGRTMIN+12", "waybar"], capture_output=True)


def main():
    tasks = get_all_tasks()
    filtered = filter_tasks_for_today(tasks)

    if not filtered:
        return

    total = len(filtered)
    selection = load_selection()
    current_index = selection.get("index", 0) if selection else 0

    # Validate current index
    if current_index >= total:
        current_index = 0

    # Move to previous (wrap-around)
    prev_index = (current_index - 1) % total
    save_selection(prev_index, total, filtered[prev_index]['file'])
    signal_waybar()


if __name__ == "__main__":
    main()
