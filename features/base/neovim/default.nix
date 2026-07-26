{ lib, config, lazyvim-nix, ... }:
{
  options.features.base.neovim = {
    enable = lib.mkEnableOption "Neovim (LazyVim)";
  };

  config = lib.mkIf config.features.base.neovim.enable {
    home-manager.users.${config.features.base.system.user.name} = { pkgs, theme, ... }: {
      imports = [ lazyvim-nix.homeManagerModules.default ];
      programs.lazyvim = {
        enable = true;
        extras = {
          lang = {
            nix.enable = true; python.enable = true; typescript.enable = true;
            go.enable = true; rust.enable = true; vue.enable = true;
          };
        };
        extraPackages = [ pkgs.vtsls ];
      };
      xdg.configFile."nvim/lua/plugins/treesitter-fix.lua".text = ''
        return {
          {
            "nvim-treesitter/nvim-treesitter",
            init = function(plugin)
              local runtime_path = plugin.dir .. "/runtime"
              if vim.fn.isdirectory(runtime_path) == 1 then
                vim.opt.rtp:prepend(runtime_path)
              end
            end,
          },
        }
      '';
      xdg.configFile."nvim/lua/plugins/colorscheme.lua".text = ''
        return {
          { "catppuccin/nvim", name = "catppuccin", priority = 1000, opts = { flavour = "${theme.catppuccin.flavor}" } },
          { "LazyVim/LazyVim", opts = { colorscheme = "catppuccin" } },
        }
      '';
      xdg.configFile."nvim/lua/plugins/smear-cursor.lua".text = ''
        return { { "sphamba/smear-cursor.nvim", opts = {} } }
      '';
    };
  };
}
