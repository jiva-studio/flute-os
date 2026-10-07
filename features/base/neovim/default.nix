{ lib, config, lazyvim-nix, ... }:
{
  options.features.base.neovim = {
    enable = lib.mkEnableOption "Neovim (LazyVim)";
  };

  config = lib.mkIf config.features.base.neovim.enable {
    home-manager.users.${config.features.base.system.user.name} = { pkgs, theme, ... }:
    let
      # Vue tooling since v3 is split in two: vue-language-server owns the
      # template and style blocks, while the <script> block is handled by vtsls
      # loading @vue/typescript-plugin. Without the plugin, vtsls parses the
      # whole .vue file as TypeScript and every tag becomes a syntax error.
      #
      # nixpkgs builds the server with a pnpm whose version carries an
      # advisory. It is a build-time package manager that never reaches the
      # running system, so the flag is dropped here rather than opening
      # permittedInsecurePackages for the whole configuration.
      vue-language-server = pkgs.vue-language-server.override {
        pnpm_10_34_0 = pkgs.pnpm_10_34_0.overrideAttrs (old: {
          meta = builtins.removeAttrs old.meta [ "knownVulnerabilities" ];
        });
      };
      vueTypescriptPlugin = "${vue-language-server}/lib/language-tools/packages/language-server";
    in
    {
      imports = [ lazyvim-nix.homeManagerModules.default ];
      programs.lazyvim = {
        enable = true;
        extras = {
          lang = {
            nix.enable = true; python.enable = true; typescript.enable = true;
            go.enable = true; rust.enable = true; vue.enable = true;
          };
        };
        extraPackages = [ pkgs.vtsls vue-language-server ];
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
      # LazyVim's vue extra asks Mason where @vue/typescript-plugin lives, and
      # Mason is disabled here. Point vtsls at the Nix copy instead.
      xdg.configFile."nvim/lua/plugins/vue.lua".text = ''
        return {
          {
            "neovim/nvim-lspconfig",
            opts = function(_, opts)
              local plugins = vim.tbl_get(opts, "servers", "vtsls", "settings", "vtsls", "tsserver", "globalPlugins")
              for _, plugin in ipairs(plugins or {}) do
                if plugin.name == "@vue/typescript-plugin" then
                  plugin.location = "${vueTypescriptPlugin}"
                end
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
