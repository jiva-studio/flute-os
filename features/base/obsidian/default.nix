{ lib, config, ... }:
{
  options.features.base.obsidian = {
    enable = lib.mkEnableOption "Obsidian note-taking";
    vaultRoot = lib.mkOption {
      type = lib.types.str;
      default = "";
      example = "Documents/Notes";
      description = ''
        Directory that holds your Obsidian vaults, relative to $HOME. The task
        scripts scan `$HOME/<vaultRoot>/<vault>/**/*.md` and take the first path
        component below the root as the vault name — that is what the
        `obsidian://open?vault=…` URI needs.

        Empty by default: the distribution does not know where you keep your
        notes, and an inert task widget is better than one pointing at somebody
        else's folder. Unset, `obsidian-tasks` reports no tasks and
        `obsidian-task-open` merely focuses or launches Obsidian.

        Deliberately independent of `features.fluteos.which-key.brainPath`,
        which names the same directory for the brain-folders menu: features/base
        is the lower layer and must not reach into a features/fluteos option for
        its own default. Set both from one value in your host or personal
        overlay — or, better, let which-key's option default from this one.
      '';
    };
  };

  config = lib.mkIf config.features.base.obsidian.enable {
    home-manager.users.${config.features.base.system.user.name} = { pkgs, ... }: {
      home.packages = [ pkgs.obsidian ];
      imports = [
        ./scripts.nix
      ];
    };
  };
}
