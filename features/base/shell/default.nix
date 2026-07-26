{ lib, config, ... }:
let theme = config.features.fluteos.theme.resolved; in
{
  imports = [ ./aliases.nix ./functions.nix ./starship.nix ];

  options.features.base.shell = {
    enable = lib.mkEnableOption "Shell (Fish + Starship)";

    projectsRoot = lib.mkOption {
      type = lib.types.str;
      default = "Projects";
      example = "work/code";
      description = ''
        Where checkouts live, relative to $HOME, in a
        `<projectsRoot>/<group>/<project>` layout. Anything that has to
        *recognise* a project directory from a path reads this: the fish `title`
        helper (features/base/shell) and the WezTerm project badges
        (features/base/terminal), which cannot ask Nix at run time and would
        otherwise carry the directory name as a literal in fish and Lua.

        This is the same directory as `features.fluteos.projects.rootDir`, which
        states it absolutely (default `''${home}/Projects`) for the home-manager
        side that *creates* the checkouts. The two are declared separately
        because they live on opposite sides of the NixOS/home-manager boundary;
        keep them in agreement if you move the root.
      '';
    };
  };

  config = lib.mkIf config.features.base.shell.enable {
    home-manager.users.${config.features.base.system.user.name} = {
      programs.fish = {
        enable = true;

        shellInit = ''
          # Disable fish greeting
          set -g fish_greeting

          # Set editor
          set -gx EDITOR nvim
          set -gx VISUAL nvim

          # Remember niri window ID for this WezTerm pane
          if set -q WEZTERM_PANE
            set -l _niri_windows (niri msg -j windows 2>/dev/null)
            set -l _pid $fish_pid
            while test "$_pid" -gt 1
              set -l _wid (echo $_niri_windows | jq -r --argjson p $_pid '.[] | select(.pid == $p) | .id // empty')
              if test -n "$_wid"
                set -gx NIRI_WINDOW_ID $_wid
                break
              end
              set _pid (ps -o ppid= -p $_pid 2>/dev/null | string trim)
            end
          end
        '';

        interactiveShellInit = ''
          # Catppuccin Mocha colors
          set -g fish_color_command ${theme.palette.green}
          set -g fish_color_param ${theme.palette.text}
          set -g fish_color_error ${theme.palette.red}
          set -g fish_color_quote ${theme.palette.yellow}
          set -g fish_color_keyword ${theme.palette.mauve}
          set -g fish_color_redirection ${theme.palette.pink}
          set -g fish_color_end ${theme.palette.peach}
          set -g fish_color_comment ${theme.palette.overlay0}
          set -g fish_color_autosuggestion ${theme.palette.overlay0}
          set -g fish_color_selection --background=${theme.palette.surface1}
        '';
      };
    };
  };
}
