{ lib, config, ... }:
let theme = config.features.fluteos.theme.resolved; in
{
  config = lib.mkIf config.features.base.shell.enable {
    home-manager.users.${config.features.base.system.user.name} = {
      programs.starship = {
        enable = true;
        settings = {
          add_newline = false;
          format = "$directory$git_branch$git_status$nix_shell$character";
          directory = { style = "bold ${theme.palette.lavender}"; truncation_length = 3; };
          git_branch = { style = "bold ${theme.palette.mauve}"; format = "[$branch]($style) "; };
          git_status = { style = "bold ${theme.palette.red}"; format = "[$all_status$ahead_behind]($style) "; };
          nix_shell = { format = "[$symbol$state]($style) "; symbol = " "; style = "bold ${theme.palette.sapphire}"; };
          character = {
            success_symbol = "[❯](bold ${theme.palette.green})";
            error_symbol = "[❯](bold ${theme.palette.red})";
          };
        };
      };
    };
  };
}
