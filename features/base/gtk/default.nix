# GTK theming: widget theme, icon theme, and the dark-mode preference.
#
# Two mechanisms have to agree here. home-manager's `gtk.*` writes
# ~/.config/gtk-3.0/settings.ini and gtk-4.0/settings.ini, which GTK
# applications read directly; `dconf` is what GNOME's own applications and the
# xdg-desktop-portal read. Set only one and half the desktop comes up light.
#
# Names and package overrides are derived from the FluteOS palette. The flavour
# and accent used to be written out four times, which meant switching palettes
# re-themed the bar and the menus while leaving every GTK window on mocha-mauve.
# A palette that is not a catppuccin flavour leaves the theme alone rather than
# claiming to be one — only the dark-mode preference still applies.
{ lib, config, ... }:
let
  ctp = config.features.fluteos.theme.resolved.catppuccin;
  themeName = "catppuccin-${ctp.flavor}-${ctp.accent}-standard";
  # Papirus' own icons; only the folder hue comes from the palette.
  iconThemeName = "Papirus-Dark";
in
{
  options.features.base.gtk = {
    enable = lib.mkEnableOption "GTK theming";
  };

  config = lib.mkIf config.features.base.gtk.enable {
    home-manager.users.${config.features.base.system.user.name} = { pkgs, ... }: {
      gtk = {
        enable = true;
        gtk3.extraConfig = { gtk-application-prefer-dark-theme = true; };
        gtk4.extraConfig = { gtk-application-prefer-dark-theme = true; };
      } // lib.optionalAttrs (ctp != null) {
        theme = {
          name = themeName;
          package = pkgs.catppuccin-gtk.override {
            accents = [ ctp.accent ];
            variant = ctp.flavor;
          };
        };
        iconTheme = {
          name = iconThemeName;
          package = pkgs.catppuccin-papirus-folders.override {
            flavor = ctp.flavor;
            accent = ctp.accent;
          };
        };
      };

      dconf.settings = {
        "org/gnome/desktop/interface" = {
          color-scheme = "prefer-dark";
        } // lib.optionalAttrs (ctp != null) {
          gtk-theme = themeName;
          icon-theme = iconThemeName;
        };
      };
    };
  };
}
