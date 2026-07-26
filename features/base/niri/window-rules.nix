# Niri window rules and visual settings
{ theme, c, niriRules }:

let
  rules = niriRules;
  cursorSize = theme.uiConstants.cursor.size;
  cornerRadius = theme.uiConstants.layout.cornerRadius;
in
''
  prefer-no-csd

  screenshot-path "~/Pictures/Screenshots/Screenshot from %Y-%m-%d %H-%M-%S.png"

  animations {
      slowdown 1.0
  }

  overview {
      backdrop-color "#${c theme.colors.bg-dark}"
      workspace-shadow {
          off
      }
  }

  window-rule {
      geometry-corner-radius ${toString cornerRadius}
      clip-to-geometry true
  }

  window-rule {
      match app-id="com.fluteos.WhichKey"
      open-floating true
      default-floating-position x=0 y=16 relative-to="top"
  }

  // Workspace rename dialog
  window-rule {
      match app-id="niri-workspace-rename"
      open-floating true
      default-column-width { fixed 400; }
  }

  // Zoom: all windows floating by default
  ${rules.mkFloatingRule "zoom"}

  // Zoom: main meeting window - tiled
  ${rules.mkTiledRule "zoom" "^Meeting$"}

  // Zoom: main application window - tiled
  ${rules.mkTiledRule "zoom" "^Zoom Workplace"}

  // Picture-in-Picture rules for browsers
  ${rules.pipRules}

  // Readest e-book reader (Flatpak)
  window-rule {
      match app-id="com.bilingify.readest"
      draw-border-with-background false
      focus-ring {
          on
      }
      border {
          off
      }
  }

  layer-rule {
      match namespace="^awww-daemon$"
      place-within-backdrop true
  }

  cursor {
      xcursor-theme "Bibata-Modern-Classic"
      xcursor-size ${toString cursorSize}
  }

  hotkey-overlay {
      skip-at-startup
  }
''
