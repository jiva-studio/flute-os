# Niri Window Rule Generators
# Centralized rule generators to eliminate repetition in window-rules.nix
#
# Usage:
#   rules = import ../../lib/niri-rules.nix { inherit theme c; };
#   ${rules.pipRules}
#
# Used by: niri/window-rules.nix
{ theme, c }:

let
  # Generate a Picture-in-Picture rule for a browser
  mkPipRule = appId: ''
    window-rule {
      match app-id=r#"^${appId}$"# title="^Picture-in-Picture$"
      open-floating true
      default-floating-position x=16 y=16 relative-to="bottom-right"
      border {
        on
        width 2
        active-color "#${c theme.colors.bg-highlight}"
        inactive-color "#${c theme.colors.bg-highlight}"
      }
      focus-ring {
        off
      }
    }
  '';

  # Generate a floating rule for an app
  mkFloatingRule = appId: ''
    window-rule {
      match app-id="${appId}"
      open-floating true
    }
  '';

  # Generate a tiled rule (override floating default)
  mkTiledRule = appId: title: ''
    window-rule {
      match app-id="${appId}" title="${title}"
      open-floating false
    }
  '';
in
{
  inherit mkPipRule mkFloatingRule mkTiledRule;

  # All PiP rules combined for browsers
  pipRules = builtins.concatStringsSep "\n" (map mkPipRule [
    "firefox"
    "chromium"
  ]);
}
