# Qt theming, so Qt applications (DigiKam, zoom, KDE utilities) do not come up
# in the default Fusion light theme next to a dark GTK desktop.
#
# Kvantum is the indirection: Qt has no equivalent of a GTK theme package, so a
# style *plugin* is installed and pointed at a theme directory. Both the Qt5 and
# Qt6 plugins are needed — nixpkgs ships them as separate packages, and an
# application linked against the one that is missing silently falls back.
#
# The theme directory has to be copied into ~/.config/Kvantum by name: Kvantum
# only looks there and in its own store path, and kvantum.kvconfig names the
# theme as a plain string. All three names come from the palette; they used to be
# spelled out, so switching palettes left every Qt window on mocha-mauve.
{ lib, config, ... }:
let
  ctp = config.features.fluteos.theme.resolved.catppuccin;
  themeName = "catppuccin-${ctp.flavor}-${ctp.accent}";
in
{
  options.features.base.qt = {
    enable = lib.mkEnableOption "Qt theming (Kvantum)";
  };

  config = lib.mkIf config.features.base.qt.enable {
    home-manager.users.${config.features.base.system.user.name} = { pkgs, ... }:
    let
      kvantumTheme = pkgs.catppuccin-kvantum.override {
        accent = ctp.accent;
        variant = ctp.flavor;
      };
    in
    {
      home.packages = with pkgs; [
        libsForQt5.qtstyleplugin-kvantum
        kdePackages.qtstyleplugin-kvantum
      ];

      qt = {
        enable = true;
        platformTheme.name = "kvantum";
        style.name = "kvantum";
      };
    } // lib.optionalAttrs (ctp != null) {
      xdg.configFile."Kvantum/${themeName}".source =
        "${kvantumTheme}/share/Kvantum/${themeName}";
      xdg.configFile."Kvantum/kvantum.kvconfig".text = ''
        [General]
        theme=${themeName}
      '';
    };
  };
}
