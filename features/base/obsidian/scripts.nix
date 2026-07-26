# Obsidian Tasks Scripts
# CLI tools for extracting tasks from Obsidian vaults
#
# Tasks plugin format:
# - `📅 YYYY-MM-DD` — due date
# - `⏳ YYYY-MM-DD` — scheduled date
# - `🛫 YYYY-MM-DD` — start date
# - `- [ ]` — incomplete task
# - `- [x]` — completed task
#
# Scripts:
#   obsidian-tasks            - Waybar widget showing tasks
#   obsidian-task-select-next - Select next task
#   obsidian-task-select-prev - Select previous task
#   obsidian-task-open        - Open selected task in Obsidian
#
# Where the vault lives is NOT baked into the Python: it arrives as
# OBSIDIAN_VAULT_ROOT, exported by the wrappers below from
# features.base.obsidian.vaultRoot. $HOME is unknown at Nix eval time, so the
# absolute path is assembled inside the wrapper at run time — the same trick
# features/fluteos/which-key uses for its own scripts. Unset (the default) the
# scripts report no tasks instead of scanning a stranger's home directory.
{ pkgs, lib, osConfig ? null, ... }:

let
  vaultRoot =
    if osConfig != null
    then osConfig.features.base.obsidian.vaultRoot
    else "";

  exportVaultRoot =
    lib.optionalString (vaultRoot != "") ''export OBSIDIAN_VAULT_ROOT="$HOME/${vaultRoot}"'';

  # A shell wrapper rather than a bare `#!python3` script, because the env var
  # has to be computed from $HOME before Python starts.
  pythonScript = name: source: pkgs.writeShellScriptBin name ''
    ${exportVaultRoot}
    exec ${pkgs.python3}/bin/python3 ${source} "$@"
  '';

  # Main Obsidian tasks widget for Waybar
  obsidianTasks = pythonScript "obsidian-tasks" ./obsidian_tasks.py;

  # Select next task
  obsidianTaskSelectNext = pythonScript "obsidian-task-select-next" ./obsidian_task_next.py;

  # Select previous task
  obsidianTaskSelectPrev = pythonScript "obsidian-task-select-prev" ./obsidian_task_prev.py;

  # Open selected task in Obsidian
  obsidianTaskOpen = pythonScript "obsidian-task-open" ./obsidian_task_open.py;
in
{
  # Export all scripts as packages
  home.packages = [
    obsidianTasks
    obsidianTaskSelectNext
    obsidianTaskSelectPrev
    obsidianTaskOpen
  ];
}
