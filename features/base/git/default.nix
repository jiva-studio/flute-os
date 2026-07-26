{ lib, config, ... }:
let
  user = config.features.base.system.user;
in
{
  options.features.base.git = {
    enable = lib.mkEnableOption "Git + Lazygit + Delta";
  };

  config = lib.mkIf config.features.base.git.enable {
    home-manager.users.${user.name} = { lib, theme, ... }: {
      programs.git = {
        enable = true;
        settings = {
          # Global identity from features.base.system.user.{realName,email}.
          # Per-group identity (set via direnv .envrc env-vars in group-setup.nix)
          # overrides this — env-vars beat ~/.gitconfig.
          user = lib.mkMerge [
            (lib.mkIf (user.realName != "") { name = user.realName; })
            (lib.mkIf (user.email != "") { email = user.email; })
          ];
          init.defaultBranch = "main";
          diff.algorithm = "histogram";
          push.autoSetupRemote = true;
          pull.rebase = true;
          merge.conflictstyle = "zdiff3";
          rebase.autoStash = true;
          core.autocrlf = "input";
          alias = {
            co = "checkout"; br = "branch"; ci = "commit"; st = "status";
            unstage = "reset HEAD --"; last = "log -1 HEAD";
            lg = "log --oneline --graph --all"; amend = "commit --amend --no-edit";
            wip = "commit -am 'WIP'";
          };
        };
        ignores = [
          ".DS_Store" "Thumbs.db" "*.swp" "*.swo" "*~" ".idea/" ".vscode/"
          "result" "result-*" ".env" ".env.local" ".direnv/"
        ];
      };
      programs.delta = {
        enable = true;
        enableGitIntegration = true;
        options = { navigate = true; line-numbers = false; syntax-theme = "ansi"; side-by-side = false; };
      };
      programs.lazygit = {
        enable = true;
        settings = let
          palette = theme.palette;
        in {
          git.pagers = [{ pager = "delta --paging=never"; colorArg = "always"; }];
          notARepository = "skip";
          gui = {
            showIcons = true;
            nerdFontsVersion = "3";
            theme = {
              activeBorderColor = [ palette.mauve "bold" ];
              inactiveBorderColor = [ palette.overlay0 ];
              searchingActiveBorderColor = [ palette.yellow "bold" ];
              optionsTextColor = [ palette.blue ];
              selectedLineBgColor = [ palette.surface0 ];
              selectedRangeBgColor = [ palette.surface1 ];
              cherryPickedCommitBgColor = [ palette.surface1 ];
              cherryPickedCommitFgColor = [ palette.mauve ];
              markedBaseCommitBgColor = [ palette.yellow ];
              markedBaseCommitFgColor = [ palette.base ];
              unstagedChangesColor = [ palette.red ];
              defaultFgColor = [ palette.text ];
            };
          };
        };
      };
    };
  };
}
