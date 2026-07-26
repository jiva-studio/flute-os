# Theme helper functions for DRY color manipulation
# Provides utilities for color conversion and manipulation
#
# Functions:
# - stripHash: Remove # prefix from hex colors
# - c: Alias for stripHash (backward compatibility)
# - rgba: Convert hex color to CSS rgba() string with alpha channel
# - contrastText: Calculate contrasting text color (black/white) based on luminance
#
# Usage:
#   helpers.rgba "#1e1e2e" 0.95  # => "rgba(30, 30, 46, 0.95)"
#   helpers.contrastText "#ffffff" # => "#000000" (black text on white bg)
{ lib }:

let
  # Hex digit lookup table
  hexDigits = {
    "0" = 0; "1" = 1; "2" = 2; "3" = 3; "4" = 4; "5" = 5; "6" = 6; "7" = 7;
    "8" = 8; "9" = 9; "a" = 10; "b" = 11; "c" = 12; "d" = 13; "e" = 14; "f" = 15;
    "A" = 10; "B" = 11; "C" = 12; "D" = 13; "E" = 14; "F" = 15;
  };

  # Helper to convert 2-char hex string to integer (0-255)
  hexToInt = hex:
    let
      chars = lib.stringToCharacters hex;
      high = if builtins.length chars > 0 then lib.elemAt chars 0 else "0";
      low = if builtins.length chars > 1 then lib.elemAt chars 1 else "0";
    in
    (hexDigits.${high} or 0) * 16 + (hexDigits.${low} or 0);

  # Calculate relative luminance (0.0 to 1.0)
  # Uses WCAG formula: L = 0.2126*R + 0.7152*G + 0.0722*B
  calculateLuminance = r: g: b:
    let
      rNorm = r / 255.0;
      gNorm = g / 255.0;
      bNorm = b / 255.0;
    in
    (0.2126 * rNorm) + (0.7152 * gNorm) + (0.0722 * bNorm);
in
{
  # Remove # prefix from hex color (for apps that don't want it)
  stripHash = color: lib.removePrefix "#" color;

  # Alias for backward compatibility
  c = color: lib.removePrefix "#" color;

  # Convert hex color to CSS rgba() string
  # Usage: rgba "#1e1e2e" 0.95 => "rgba(30, 30, 46, 0.95)"
  rgba = hex: alpha:
    let
      cleaned = lib.removePrefix "#" hex;
      r = hexToInt (builtins.substring 0 2 cleaned);
      g = hexToInt (builtins.substring 2 2 cleaned);
      b = hexToInt (builtins.substring 4 2 cleaned);
    in
    "rgba(${toString r}, ${toString g}, ${toString b}, ${toString alpha})";

  # Calculate contrasting text color (black or white) based on background luminance
  # Returns "#000000" for light backgrounds, "#ffffff" for dark backgrounds
  # Usage: contrastText "#ffffff" => "#000000"
  contrastText = hex:
    let
      cleaned = lib.removePrefix "#" hex;
      r = hexToInt (builtins.substring 0 2 cleaned);
      g = hexToInt (builtins.substring 2 2 cleaned);
      b = hexToInt (builtins.substring 4 2 cleaned);
      luminance = calculateLuminance r g b;
    in
    if luminance > 0.5 then "#000000" else "#ffffff";
}
