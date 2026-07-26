# TTY appearance.
#
# The colours are derived from the active theme rather than written out here.
# They used to be a hardcoded Tokyo Night palette while every graphical
# component followed Catppuccin, so switching the theme left the virtual console
# on a palette nothing else used — and no amount of editing the theme could fix
# it, because the TTY simply did not read it.
{ lib, config, pkgs, ... }:
let
  theme = config.features.fluteos.theme.resolved;
  ansi = theme.ansiColors;
  # The kernel wants 16 entries, ANSI 0-15, as bare RRGGBB with no leading '#'.
  consoleColors = map (c: lib.removePrefix "#" c) [
    ansi.ansi.black ansi.ansi.red ansi.ansi.green ansi.ansi.yellow
    ansi.ansi.blue ansi.ansi.magenta ansi.ansi.cyan ansi.ansi.white
    ansi.bright.black ansi.bright.red ansi.bright.green ansi.bright.yellow
    ansi.bright.blue ansi.bright.magenta ansi.bright.cyan ansi.bright.white
  ];
in
{
  config = lib.mkIf config.features.base.system.enable {
    console = {
      font = "ter-132b";
      packages = [ pkgs.terminus_font ];
      earlySetup = true;
      # Follows the graphical keyboard layout by default; "us" is the fallback
      # for a host that never set one.
      keyMap = lib.mkDefault
        (lib.head (lib.splitString "," config.features.base.niri.keyboard.layout));
      colors = consoleColors;
    };
  };
}
