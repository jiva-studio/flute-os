# MPD status script for waybar
{ pkgs }:

pkgs.writeShellScriptBin "mpd-status" ''
  export MPC="${pkgs.mpc}/bin/mpc"
  bash ${./mpd-status.sh}
''
