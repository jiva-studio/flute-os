# Which-key menu definitions - modular entry point
{ config, lib, hostConfig }:

let
  appsMenus = import ./menus/apps.nix { inherit lib hostConfig; };
in
{
  main = import ./menus/main.nix { };
  brain = import ./menus/brain.nix;
  windows = import ./menus/windows.nix;
  inherit (appsMenus) apps apps-search;
  power = import ./menus/power.nix { inherit lib hostConfig; };
  screencast = import ./menus/screencast.nix;
  screenshot = import ./menus/screenshot.nix;
  projects = import ./menus/projects.nix;
  workspace = import ./menus/workspace.nix;
  firefox = import ./menus/firefox.nix { inherit config lib; };
  workspace-rename = import ./menus/workspace-rename.nix { inherit config lib; };
  agent = import ./menus/agent.nix;
  docs = import ./menus/docs.nix;
  docs-find = import ./menus/docs-find.nix;
}
