# UI Design Tokens
# Centralized spacing, border, and opacity constants for consistent UI design
#
# Usage:
#   uiConstants = import ./lib/ui-constants.nix { };
#   # Access with: uiConstants.spacing.md, uiConstants.borderRadius.normal, etc.
#
# Used by: waybar/style.nix, niri/layout.nix, niri/keybindings.nix, theme.nix
{ }:

{
  # Spacing scale (in pixels)
  spacing = {
    xs = 2;   # Extra small - minimal gaps
    sm = 5;   # Small - inner gaps
    md = 10;  # Medium - outer gaps, padding
    lg = 20;  # Large - major section spacing
  };

  # Border radius values (in pixels)
  borderRadius = {
    small = 2;   # Subtle rounding for small elements
    normal = 5;  # Standard rounding for buttons, windows
    large = 10;  # Prominent rounding for cards, modals
  };

  # Border width values (in pixels)
  borderWidth = {
    thin = 1;    # Fine borders for subtle separation
    normal = 2;  # Standard borders for windows, buttons
    thick = 3;   # Heavy borders for emphasis
  };

  # Opacity values (0.0 to 1.0)
  opacity = {
    translucent = 0.7;      # 70% - See-through backgrounds
    semitransparent = 0.85; # 85% - Slightly visible backgrounds
    opaque = 0.9;           # 90% - Mostly solid
    solid = 1.0;            # 100% - Fully opaque
  };

  # Media control step values (for volume, brightness)
  mediaSteps = {
    volume = "5%";      # Volume adjustment step
    brightness = "5%";  # Brightness adjustment step
  };

  # Window/column resize step values
  resizeSteps = {
    column = "10%";  # Column width adjustment step
    window = "10%";  # Window height adjustment step
  };

  # Layout values (gaps, corner radius for windows)
  layout = {
    gaps = 8;          # Gap between windows
    cornerRadius = 5;  # Window corner radius
  };

  # Cursor configuration
  cursor = {
    size = 24;  # Cursor size in pixels
  };
}
