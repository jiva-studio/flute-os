# Niri workspace utilities - rename, name display
{ lib, config, ... }:

{
  config = lib.mkIf config.features.base.niri.enable {
    home-manager.users.${config.features.base.system.user.name} = { pkgs, ... }:
    let
      # Script to rename workspace via dialog
      workspaceRename = pkgs.writeShellScriptBin "niri-workspace-rename" ''
        export NIRI="${pkgs.niri}/bin/niri"
        export JQ="${pkgs.jq}/bin/jq"
        bash ${./workspace-rename.sh}
      '';

      # Script to set workspace name from argument
      workspaceRenameSet = pkgs.writeShellScriptBin "niri-workspace-rename-set" ''
        export NIRI="${pkgs.niri}/bin/niri"
        bash ${./workspace-rename-set.sh} "$@"
      '';

      # Script to get current workspace name for waybar
      workspaceNameScript = pkgs.writeShellScriptBin "niri-workspace-name" ''
        export NIRI="${pkgs.niri}/bin/niri"
        export JQ="${pkgs.jq}/bin/jq"
        bash ${./workspace-name.sh}
      '';

      # Script to close the focused workspace: close all its windows and clear
      # its name, so niri reaps the now-empty (unnamed) workspace.
      workspaceClose = pkgs.writeShellScriptBin "niri-workspace-close" ''
        export NIRI="${pkgs.niri}/bin/niri"
        export JQ="${pkgs.jq}/bin/jq"
        bash ${./workspace-close.sh}
      '';
    in
    {
      home.packages = [ workspaceRename workspaceRenameSet workspaceNameScript workspaceClose ];
    };
  };
}
