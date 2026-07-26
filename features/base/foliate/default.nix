{ lib, config, ... }:
{
  options.features.base.foliate = {
    enable = lib.mkEnableOption "Foliate e-book reader";
  };

  config = lib.mkIf config.features.base.foliate.enable {
    # Sepia and Latte are their own palettes and stay literal — there is no
    # palette file for either. The Mocha reader theme, on the other hand, must
    # not be able to drift from the Mocha the rest of the system uses, so it is
    # read from the theme.
    home-manager.users.${config.features.base.system.user.name} = { pkgs, theme, ... }: {
      home.packages = [ pkgs.foliate ];
      home.file.".config/com.github.johnfactotum.Foliate/themes/sepia-hc.json".text = builtins.toJSON {
        label = "Sepia HC";
        light = { fg = "#321e0a"; bg = "#faf0d7"; link = "#78461e"; };
        dark = { fg = "#faf0d7"; bg = "#321e0a"; link = "#c4956a"; };
      };
      home.file.".config/com.github.johnfactotum.Foliate/themes/catppuccin-latte.json".text = builtins.toJSON {
        label = "Catppuccin Latte";
        light = { fg = "#4c4f69"; bg = "#eff1f5"; link = "#8839ef"; };
        dark = { fg = "#4c4f69"; bg = "#eff1f5"; link = "#8839ef"; };
      };
      home.file.".config/com.github.johnfactotum.Foliate/themes/catppuccin-mocha.json".text = builtins.toJSON {
        label = "Catppuccin Mocha";
        light = { fg = theme.palette.text; bg = theme.palette.base; link = theme.palette.mauve; };
        dark = { fg = theme.palette.text; bg = theme.palette.base; link = theme.palette.mauve; };
      };
    };
  };
}
