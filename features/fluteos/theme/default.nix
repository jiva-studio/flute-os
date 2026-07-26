# The FluteOS theme. One tree, one place, read by every UI-touching module.
#
# Configure it with exactly one option:
#
#   features.fluteos.theme.active = "catppuccin-mocha";
#
# To add a theme: drop a palette in palettes/<name>.nix and extend the enum.
# Everything else — semantic colours, fonts, spacing tokens, launcher colours,
# bar chip CSS, and the flavour the catppuccin/nix ports are configured with —
# is DERIVED from that palette, so a new palette re-themes the whole system
# rather than half of it.
#
# It had drifted badly, in ways that all had the same effect — modules giving up
# on the theme and hardcoding values:
#
#   - `theme.waybar` (18 attributes) and `theme.icons` (11) had no readers at
#     all, dead since the bar moved to the cffi niri minimap. Between them they
#     held every hex literal in this module.
#   - `theme.ui` and `theme.uiConstants` were two token sets with the SAME values
#     in different casing; mako and which-key read one, niri and waybar the
#     other. Now there is one.
#   - There was nothing here for a fuzzel popup or a bar chip, so four modules
#     pasted the same five colours plus a font name, and the chip CSS lived in
#     waybar where nobody outside it could reach. Changing the theme font
#     changed no launcher at all.
#   - Five modules stated the catppuccin flavour and accent by hand, so a second
#     palette would have left GTK, Qt, zathura, yazi and neovim on mocha-mauve.
#
# There is no `enable`: nothing in FluteOS works without a theme, and a module
# reading `.resolved` while it was off used to get `{}` and fail somewhere far
# away with "attribute 'palette' missing".
{ lib, config, ... }:
let
  cfg = config.features.fluteos.theme;

  palette = import (./palettes + "/${cfg.active}.nix");
  helpers = import ./helpers.nix { inherit lib; };
  ansiColors = import ./ansi-colors.nix { inherit palette; };
  uiConstants = import ./ui-constants.nix { };

  fonts = {
    # The family name on its own. fontconfig patterns want this ("Family:size=14");
    # the Mono variant below is what terminals and CSS ask for. Both spellings
    # are needed, which is why hardcoding one of them kept happening.
    monoFamily = "JetBrainsMono Nerd Font";
    mono = "JetBrainsMono Nerd Font Mono";
    sans = "Noto Sans";
    serif = "Noto Serif";
    size = {
      small = 9;
      normal = 10;
      large = 11;
      # Popups and pickers sit further from the eye than bar text.
      ui = 14;
    };
  };

  # Everything a fuzzel picker needs. `env` is the preamble the wrappers
  # source, so adding a picker is one line instead of six copied ones.
  fuzzel = rec {
    bg = "${palette.base}ff";
    fg = "${palette.text}ff";
    selBg = "${palette.surface1}ff";
    selFg = "${palette.mauve}ff";
    border = "${palette.mauve}ff";
    borderWidth = uiConstants.borderWidth.normal;
    borderRadius = uiConstants.borderRadius.normal;
    font = "${fonts.monoFamily}:size=${toString fonts.size.ui}";
    env = ''
      export BG="${bg}"
      export FG="${fg}"
      export SEL_BG="${selBg}"
      export SEL_FG="${selFg}"
      export BORDER="${border}"
      export FONT="${font}"
    '';
  };

  resolved = {
    inherit palette helpers ansiColors uiConstants fonts fuzzel;

    # Which upstream catppuccin flavour/accent this palette IS, or null for a
    # palette that is not a catppuccin one. Read by every module that configures
    # a catppuccin/nix port, and set globally in the config block below.
    catppuccin = palette.catppuccin or null;

    # Semantic layer. Prefer these over `palette` — they are what a second
    # palette has to satisfy. Kept complete on purpose: a vocabulary, not a
    # log of what happens to be used today.
    colors = {
      # Primary backgrounds
      bg = palette.base;
      bg-dark = palette.mantle;
      bg-light = palette.surface0;
      bg-highlight = palette.surface1;

      # Foreground
      fg = palette.text;
      fg-dark = palette.subtext1;
      fg-gutter = palette.overlay0;

      # Accent
      accent = palette.mauve;
      accent-alt = palette.green;

      # Semantic
      red = palette.red;
      orange = palette.peach;
      yellow = palette.yellow;
      green = palette.green;
      teal = palette.teal;
      cyan = palette.sky;
      blue = palette.blue;
      magenta = palette.mauve;

      # UI states
      warning = palette.peach;
      critical = palette.red;
      success = palette.green;

      # Transparency variants
      bg-alpha-95 = helpers.rgba palette.base 0.95;
      bg-alpha-90 = helpers.rgba palette.base 0.9;
      mantle-alpha-90 = helpers.rgba palette.mantle 0.9;
      accent-alpha-30 = helpers.rgba palette.mauve 0.3;
      accent-alpha-20 = helpers.rgba palette.mauve 0.2;
    };

    css = import ./css.nix { inherit palette uiConstants; };
  };
in
{
  options.features.fluteos.theme = {
    active = lib.mkOption {
      type = lib.types.enum [ "catppuccin-mocha" ];
      default = "catppuccin-mocha";
      description = "Active palette, a file under palettes/. The one knob this system has.";
    };

    resolved = lib.mkOption {
      type = lib.types.attrs;
      readOnly = true;
      description = ''
        The resolved theme tree. Read it as
        `config.features.fluteos.theme.resolved` on the NixOS side, or as the
        `theme` module argument inside home-manager.

        Branches, in the order you should reach for them:
          `colors`      semantic names (bg, fg, accent, warning, …) — prefer these
          `palette`     the raw palette, when you need a specific hue
          `uiConstants` spacing, radii, border widths, opacity, input steps
          `fonts`       families and sizes
          `fuzzel`      colours, font and a ready-made shell preamble for pickers
          `css`         chip style helpers for the bar and for contributed chips
          `catppuccin`  `{ flavor; accent; }` for catppuccin/nix ports, or null
          `helpers`     rgba / stripHash / contrastText
          `ansiColors`  terminal palette
      '';
    };
  };

  # Not behind mkIf: the tree is a pure function of `active`, and every consumer
  # needs it. See the header.
  config = {
    features.fluteos.theme.resolved = resolved;

    # The catppuccin/nix ports (gtk, qt, zathura, yazi, neovim, …) are configured
    # by flavour and accent NAME, not by colours, so they cannot read the palette.
    # Set once here, from the palette that knows which upstream flavour it is.
    home-manager.users.${config.features.base.system.user.name} =
      lib.mkIf (resolved.catppuccin != null) {
        catppuccin = {
          # Explicit, not defaulted: the module prints a deprecation warning on
          # every single evaluation until autoEnable is stated. Ports are enabled
          # individually by the features that own them, so this stays false.
          autoEnable = false;
          inherit (resolved.catppuccin) flavor accent;
        };
      };
  };
}
