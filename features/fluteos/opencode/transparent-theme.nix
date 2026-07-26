# opencode's theme file, with `background` set to "none" so the terminal's
# transparency shows through.
#
# Extracted from default.nix, where it was 113 of 282 lines and held 60 hex
# literals — 26 of which were the Mocha palette retyped by hand, so opencode was
# the one window that would not follow a palette change.
#
# opencode requires EVERY theme key to be present: a partial override crashes
# with "theme.backgroundElement.a is undefined". Hence the full table.
#
# The dark half is generated from the palette. The light half stays literal:
# there is no Latte palette file, and inventing one to satisfy this file would
# be the tail wagging the dog.
{ lib, palette }:

let
  capitalise = s:
    lib.toUpper (builtins.substring 0 1 s) + builtins.substring 1 (-1) s;

  # rosewater -> darkRosewater, subtext1 -> darkSubtext1, …
  darkDefs = lib.mapAttrs'
    (name: value: lib.nameValuePair "dark${capitalise name}" value)
    (lib.removeAttrs palette [ "name" ]);

  lightDefs = {
    lightRosewater = "#dc8a78";
    lightFlamingo = "#dd7878";
    lightPink = "#ea76cb";
    lightMauve = "#8839ef";
    lightRed = "#d20f39";
    lightMaroon = "#e64553";
    lightPeach = "#fe640b";
    lightYellow = "#df8e1d";
    lightGreen = "#40a02b";
    lightTeal = "#179299";
    lightSky = "#04a5e5";
    lightSapphire = "#209fb5";
    lightBlue = "#1e66f5";
    lightLavender = "#7287fd";
    lightText = "#4c4f69";
    lightSubtext1 = "#5c5f77";
    lightSubtext0 = "#6c6f85";
    lightOverlay2 = "#7c7f93";
    lightOverlay1 = "#8c8fa1";
    lightOverlay0 = "#9ca0b0";
    lightSurface2 = "#acb0be";
    lightSurface1 = "#bcc0cc";
    lightSurface0 = "#ccd0da";
    lightBase = "#eff1f5";
    lightMantle = "#e6e9ef";
    lightCrust = "#dce0e8";
  };
in
{
  "$schema" = "https://opencode.ai/theme.json";

  defs = darkDefs // lightDefs // {
    # Semi-transparent Mantle for panels/message bubbles so the terminal
    # wallpaper subtly shows through (≈80% opacity).
    darkMantleAlpha = "${palette.mantle}cc";
    lightMantleAlpha = "#e6e9efcc";
  };

  theme = {
    primary = { dark = "darkBlue"; light = "lightBlue"; };
    secondary = { dark = "darkMauve"; light = "lightMauve"; };
    accent = { dark = "darkPink"; light = "lightPink"; };
    error = { dark = "darkRed"; light = "lightRed"; };
    warning = { dark = "darkYellow"; light = "lightYellow"; };
    success = { dark = "darkGreen"; light = "lightGreen"; };
    info = { dark = "darkTeal"; light = "lightTeal"; };
    text = { dark = "darkText"; light = "lightText"; };
    textMuted = { dark = "darkOverlay2"; light = "lightOverlay2"; };
    background = "none";
    backgroundPanel = { dark = "darkMantleAlpha"; light = "lightMantleAlpha"; };
    backgroundElement = { dark = "darkCrust"; light = "lightCrust"; };
    border = { dark = "darkSurface0"; light = "lightSurface0"; };
    borderActive = { dark = "darkSurface1"; light = "lightSurface1"; };
    borderSubtle = { dark = "darkSurface2"; light = "lightSurface2"; };
    diffAdded = { dark = "darkGreen"; light = "lightGreen"; };
    diffRemoved = { dark = "darkRed"; light = "lightRed"; };
    diffContext = { dark = "darkOverlay2"; light = "lightOverlay2"; };
    diffHunkHeader = { dark = "darkPeach"; light = "lightPeach"; };
    diffHighlightAdded = { dark = "darkGreen"; light = "lightGreen"; };
    diffHighlightRemoved = { dark = "darkRed"; light = "lightRed"; };
    # Diff backgrounds are green/red mixed into the surface, not palette entries.
    diffAddedBg = { dark = "#24312b"; light = "#d6f0d9"; };
    diffRemovedBg = { dark = "#3c2a32"; light = "#f6dfe2"; };
    diffContextBg = { dark = "darkMantle"; light = "lightMantle"; };
    diffLineNumber = { dark = "darkSurface1"; light = "lightSurface1"; };
    diffAddedLineNumberBg = { dark = "#1e2a25"; light = "#c9e3cb"; };
    diffRemovedLineNumberBg = { dark = "#32232a"; light = "#e9d3d6"; };
    markdownText = { dark = "darkText"; light = "lightText"; };
    markdownHeading = { dark = "darkMauve"; light = "lightMauve"; };
    markdownLink = { dark = "darkBlue"; light = "lightBlue"; };
    markdownLinkText = { dark = "darkSky"; light = "lightSky"; };
    markdownCode = { dark = "darkGreen"; light = "lightGreen"; };
    markdownBlockQuote = { dark = "darkYellow"; light = "lightYellow"; };
    markdownEmph = { dark = "darkYellow"; light = "lightYellow"; };
    markdownStrong = { dark = "darkPeach"; light = "lightPeach"; };
    markdownHorizontalRule = { dark = "darkSubtext0"; light = "lightSubtext0"; };
    markdownListItem = { dark = "darkBlue"; light = "lightBlue"; };
    markdownListEnumeration = { dark = "darkSky"; light = "lightSky"; };
    markdownImage = { dark = "darkBlue"; light = "lightBlue"; };
    markdownImageText = { dark = "darkSky"; light = "lightSky"; };
    markdownCodeBlock = { dark = "darkText"; light = "lightText"; };
    syntaxComment = { dark = "darkOverlay2"; light = "lightOverlay2"; };
    syntaxKeyword = { dark = "darkMauve"; light = "lightMauve"; };
    syntaxFunction = { dark = "darkBlue"; light = "lightBlue"; };
    syntaxVariable = { dark = "darkRed"; light = "lightRed"; };
    syntaxString = { dark = "darkGreen"; light = "lightGreen"; };
    syntaxNumber = { dark = "darkPeach"; light = "lightPeach"; };
    syntaxType = { dark = "darkYellow"; light = "lightYellow"; };
    syntaxOperator = { dark = "darkSky"; light = "lightSky"; };
    syntaxPunctuation = { dark = "darkText"; light = "lightText"; };
  };
}
