# Workspace rename menu with group suggestions
{ config, lib }:
let
  groups = config.features.fluteos.projects.groups or {};
  items = lib.mapAttrsToList (_: g: {
    icon = "󰍹";
    label = g.name;
    action = { exec = [ "niri-workspace-rename-set" g.name ]; };
  }) groups;
in
{
  type = "fuzzy";
  inputAction = { exec = [ "niri-workspace-rename-set" ]; };
  prefillCmd = [ "fluteos-niri-workspace" ];
  prefillSelect = true;
  inherit items;
}
