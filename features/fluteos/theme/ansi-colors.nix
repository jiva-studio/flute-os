# ANSI Color Standard Mapping
# Provides consistent ANSI color mappings for all terminal emulators
#
# Usage:
#   ansiColors = import ./lib/ansi-colors.nix { inherit palette; };
#   # Access with: ansiColors.ansi.red, ansiColors.bright.black, etc.
#
# Dependencies: Catppuccin Mocha palette
# Used by: wezterm/colors.nix
{ palette }:

{
  # ANSI regular colors (0-7)
  ansi = {
    black = palette.surface1;    # 0: surface1 for dark background
    red = palette.red;            # 1: red
    green = palette.green;        # 2: green
    yellow = palette.yellow;      # 3: yellow
    blue = palette.blue;          # 4: blue
    magenta = palette.pink;       # 5: magenta (using pink)
    cyan = palette.teal;          # 6: cyan (using teal)
    white = palette.subtext1;     # 7: white (using subtext1)
  };

  # ANSI bright colors (8-15)
  bright = {
    black = palette.surface2;    # 8: bright black (brighter surface)
    red = palette.red;            # 9: bright red (same as regular)
    green = palette.green;        # 10: bright green (same as regular)
    yellow = palette.yellow;      # 11: bright yellow (same as regular)
    blue = palette.blue;          # 12: bright blue (same as regular)
    magenta = palette.pink;       # 13: bright magenta (same as regular)
    cyan = palette.teal;          # 14: bright cyan (same as regular)
    white = palette.subtext0;     # 15: bright white (lighter than regular)
  };
}
