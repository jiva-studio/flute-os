# Niri layout configuration: gaps, borders, focus ring, struts
{ theme, c }:

let
  gaps = theme.uiConstants.layout.gaps;
  borderWidth = theme.uiConstants.borderWidth.normal;
in
''
  layout {
      background-color "transparent"
      gaps ${toString gaps}

      center-focused-column "never"

      preset-column-widths {
          proportion 0.33333
          proportion 0.5
          proportion 0.66667
      }

      default-column-width { proportion 0.5; }

      focus-ring {
          width ${toString borderWidth}
          active-color "#${c theme.colors.accent}"
          inactive-color "#${c theme.colors.bg-light}"
          urgent-color "#${c theme.palette.red}"
      }

      border {
          off
      }

      shadow {
          off
      }

      struts {
          left 0
          right 0
          top 0
          bottom 0
      }
  }
''
