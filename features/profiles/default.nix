# features.profiles — bundles of features that always travel together.
#
# Every host used to restate the same wall of `enable = true`: yoga listed 48
# toggles, hosts/live listed 30, and 25 of them were the same lines maintained by
# hand in two places. A host should describe what is different about it, not
# re-derive what FluteOS is.
#
# Profiles only ever `mkDefault`, so a host can still switch any individual
# feature off — the bundle is a starting point, not a straitjacket. Applications
# are deliberately NOT in here: which browser, reader or music player someone
# wants is taste, and taste belongs to the host.
{ lib, config, ... }:
let
  cfg = config.features.profiles;

  # The graphical session. Without these FluteOS is not recognisably itself:
  # the compositor, its bar and menu, notifications, locking, theming.
  desktopFeatures = {
    base = [ "niri" "terminal" "shell" "gtk" "qt" "mako" "swaylock" "greetd" "emoji" "audio" "screencast" ];
    fluteos = [ "waybar" "which-key" "wallpapers" "sessions" "apps" ];
  };

  # Working on code: version control, an editor, an agent.
  devFeatures = {
    base = [ "git" "neovim" ];
    fluteos = [ "claude-code" ];
  };

  # `features.<ns>.<name>.enable = mkDefault true` for each listed feature.
  enableAll = spec: lib.mkMerge (lib.mapAttrsToList
    (ns: names: {
      features.${ns} = lib.genAttrs names (_: { enable = lib.mkDefault true; });
    })
    spec);
in
{
  options.features.profiles = {
    desktop = lib.mkEnableOption ''
      the FluteOS graphical session — niri, terminal, shell, theming,
      notifications, screen locking, the bar and the which-key menu. Individual
      features stay overridable: the profile only sets defaults
    '';

    dev = lib.mkEnableOption ''
      development tooling — git, neovim and Claude Code. Individual features
      stay overridable
    '';
  };

  config = lib.mkMerge [
    (lib.mkIf cfg.desktop (enableAll desktopFeatures))
    (lib.mkIf cfg.dev (enableAll devFeatures))
  ];
}
