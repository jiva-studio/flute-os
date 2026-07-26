"""Open Obsidian with the selected task's note, focusing existing window."""

import json
import os
import subprocess
import urllib.parse
from pathlib import Path

# Root directory holding the Obsidian vaults. Supplied by the Nix wrapper from
# features.base.obsidian.vaultRoot; None when unconfigured, in which case we can
# still focus/launch Obsidian but cannot resolve a vault name from a file path.
_vault_root = os.environ.get("OBSIDIAN_VAULT_ROOT", "").strip()
VAULT_ROOT = Path(_vault_root).expanduser() if _vault_root else None
CACHE_DIR = Path.home() / ".cache" / "obsidian-tasks"
SELECTION_FILE = CACHE_DIR / "selection.json"


def load_selection():
    """Load current selection."""
    try:
        if SELECTION_FILE.exists():
            return json.loads(SELECTION_FILE.read_text())
    except Exception:
        pass
    return None


def extract_vault_and_file(file_path):
    """Extract vault name and relative file path from full path.

    Paths are interpreted relative to VAULT_ROOT ($OBSIDIAN_VAULT_ROOT); the
    first component below it is the vault. With <root> standing for that
    directory:

      <root>/<vault>/Tasks.md
      -> vault="<vault>", file="Tasks.md"

      <root>/<vault>/folder/note.md
      -> vault="<vault>", file="folder/note.md"
    """
    if VAULT_ROOT is None:
        return None, None

    path = Path(file_path)

    # Find the vault by looking for first directory below VAULT_ROOT
    try:
        relative_to_root = path.relative_to(VAULT_ROOT)
        parts = relative_to_root.parts

        if len(parts) >= 2:
            vault = parts[0]
            file_relative = str(Path(*parts[1:]))
            return vault, file_relative
    except ValueError:
        pass

    return None, None


def open_obsidian_uri(vault, file_path):
    """Open Obsidian using URI scheme."""
    # URL encode the parameters
    vault_encoded = urllib.parse.quote(vault)
    file_encoded = urllib.parse.quote(file_path)

    uri = f"obsidian://open?vault={vault_encoded}&file={file_encoded}"
    subprocess.run(["xdg-open", uri], capture_output=True)


def get_obsidian_windows():
    """Get all Obsidian windows from niri."""
    try:
        result = subprocess.run(
            ["niri", "msg", "--json", "windows"],
            capture_output=True, text=True
        )
        if result.returncode == 0:
            windows = json.loads(result.stdout)
            return [w for w in windows if w.get("app_id") == "obsidian"]
    except (FileNotFoundError, json.JSONDecodeError):
        # niri not available or invalid JSON
        pass
    return []


def focus_window_by_id(window_id):
    """Focus window by niri window ID."""
    try:
        subprocess.run(
            ["niri", "msg", "action", "focus-window", "--id", str(window_id)],
            capture_output=True
        )
        return True
    except FileNotFoundError:
        return False


def focus_obsidian_window(vault_name=None):
    """Focus Obsidian window, optionally matching by vault name in title.

    Matching logic:
    - Window title format: "<note title> - <vault name> - Obsidian v<version>"
    - We check if vault_name appears in the title

    Returns True if window was focused, False otherwise.
    """
    windows = get_obsidian_windows()

    if not windows:
        return False

    target_window = None

    if vault_name:
        # Find window with vault name in title
        for window in windows:
            title = window.get("title", "")
            if vault_name in title:
                target_window = window
                break

    # Fallback: first Obsidian window if no vault match
    if not target_window:
        target_window = windows[0]

    return focus_window_by_id(target_window["id"])


def main():
    selection = load_selection()

    if not selection or "file" not in selection:
        # No task selected - focus any Obsidian or open new
        if not focus_obsidian_window():
            subprocess.run(["obsidian"], capture_output=True)
        return

    file_path = selection["file"]
    vault, relative_file = extract_vault_and_file(file_path)

    # 1. Focus the correct Obsidian window (by vault name)
    focused = focus_obsidian_window(vault)

    # 2. Open URI to navigate to file (this also focuses, but less reliably)
    if vault and relative_file:
        open_obsidian_uri(vault, relative_file)
    elif not focused:
        # Neither focus nor URI worked, just open Obsidian
        subprocess.run(["obsidian"], capture_output=True)


if __name__ == "__main__":
    main()
