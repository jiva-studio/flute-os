# Bar chip CSS, as theme helpers.
#
# These lived in features/fluteos/waybar/styles.nix, imported inside the waybar
# module and exposed through nothing. So a chip contributed from outside — via
# features.fluteos.waybar.extraModules — had to re-type the five lines of
# `chip` by hand and would drift silently the day the shared one changed.
# personal/modules/anki did exactly that, and said so in a comment.
#
# They belong to the theme because that is what they are made of: a background
# colour the caller picks, and radius and foreground from the palette.
#
# Usage, from anywhere that has `theme`:
#   style = "#custom-mailbox { ${theme.css.chip theme.palette.green} }";
{ palette, uiConstants }:

let
  radius = "${toString uiConstants.borderRadius.small}px";
in
{
  # Standard chip: text with breathing room. Weather, clock, tray, tasks, usage.
  chip = bg: ''
    background: ${bg};
    border-radius: ${radius};
    color: ${palette.base};
    padding: 0 10px;
    margin: 0;
  '';

  # A button in a group — no horizontal padding, fixed width. mpd prev/next.
  chipControl = bg: ''
    background: ${bg};
    border-radius: ${radius};
    color: ${palette.base};
    padding: 0;
    margin-left: 1px;
    min-width: 28px;
  '';

  # Flush indicator, no padding at all. The status group.
  chipStatus = bg: ''
    background: ${bg};
    border-radius: ${radius};
    color: ${palette.base};
    padding: 0;
    margin: 0;
  '';
}
