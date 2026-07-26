{ lib, config, ... }:
{
  options.features.base.zathura = {
    enable = lib.mkEnableOption "Zathura PDF viewer";
  };

  config = lib.mkIf config.features.base.zathura.enable {
    home-manager.users.${config.features.base.system.user.name} = {
      xdg.mimeApps.enable = true;
      xdg.mimeApps.defaultApplications = { "application/pdf" = "org.pwmt.zathura.desktop"; };
      programs.zathura = {
        enable = true;
        options = { scroll-step = 100; selection-clipboard = "clipboard"; recolor = true; recolor-keephue = true; };
      };
      # flavour and accent come from the global catppuccin.* the theme module sets,
      # so a palette switch reaches this port too.
      catppuccin.zathura.enable = true;
    };
  };
}
