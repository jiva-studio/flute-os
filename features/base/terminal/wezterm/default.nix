{ lib, config, ... }:

let
  theme = config.features.fluteos.theme.resolved;
  c = theme.helpers.c;
  colorsConfig = import ./colors.nix { inherit theme c; };

  # The projects layout is an option, not a literal in Lua. The value ends up
  # inside a `path:match` pattern, so escape Lua's pattern metacharacters —
  # replaceStrings is a single left-to-right pass, so "%" cannot double-escape.
  luaPatternEscape = builtins.replaceStrings
    [ "%" "^" "$" "(" ")" "." "[" "]" "*" "+" "-" "?" ]
    [ "%%" "%^" "%$" "%(" "%)" "%." "%[" "%]" "%*" "%+" "%-" "%?" ];
  projectsRootPattern = luaPatternEscape config.features.base.shell.projectsRoot;

  projectInfoLua = builtins.replaceStrings
    [ "@PROJECTS_ROOT@" ] [ projectsRootPattern ]
    (builtins.readFile ./project-info.lua);

  projectBadgesConfig = import ./project-badges.nix { inherit projectInfoLua; };
in
{
  config = lib.mkIf config.features.base.terminal.enable {
    home-manager.users.${config.features.base.system.user.name} = { pkgs, ... }: {
      programs.wezterm = {
        enable = true;
        extraConfig = ''
          local wezterm = require 'wezterm'
          local config = wezterm.config_builder()

          -- Load project info helpers
          ${projectInfoLua}

          local project_helpers = {
            get_project_info = get_project_info,
            color_from_string = color_from_string,
            is_dark = is_dark,
          }

          -- Font configuration
          config.font = wezterm.font_with_fallback {
            { family = '${theme.fonts.mono}', weight = 'Regular' },
            'Noto Sans Symbols 2',
          }
          config.font_size = 12

          -- Color scheme
          ${colorsConfig}

          -- Tab bar (hidden by default, toggle with Ctrl+Shift+B)
          config.enable_tab_bar = false
          config.use_fancy_tab_bar = false
          config.tab_bar_at_bottom = false
          config.show_new_tab_button_in_tab_bar = false
          config.tab_max_width = 999

          -- Window appearance
          config.window_decorations = "NONE"  -- Niri manages decorations
          config.window_padding = { left = 10, right = 10, top = 10, bottom = 10 }
          config.window_background_opacity = 0.90

          -- Unix domain for persistent sessions (mux server)
          config.unix_domains = { { name = 'unix' } }

          -- Keybindings
          config.keys = {
            -- Copy mode (Vim-style selection)
            { key = 'Space', mods = 'CTRL|SHIFT', action = wezterm.action.ActivateCopyMode },

            -- Toggle tab bar with project badges
            { key = 'b', mods = 'CTRL|SHIFT', action = wezterm.action.EmitEvent 'toggle-tab-bar' },

            -- Navigate by commands (semantic zones from Fish OSC 133)
            { key = 'UpArrow', mods = 'CTRL|SHIFT', action = wezterm.action.ScrollToPrompt(-1) },
            { key = 'DownArrow', mods = 'CTRL|SHIFT', action = wezterm.action.ScrollToPrompt(1) },

            -- Set custom tab title (runs fish function that supports emoji)
            { key = 't', mods = 'CTRL|SHIFT', action = wezterm.action.SendString 'set-tab-title\n' },
          }

          -- Mouse bindings
          config.mouse_bindings = {
            -- Triple click - select entire command output (semantic zone)
            {
              event = { Down = { streak = 3, button = 'Left' } },
              action = wezterm.action.SelectTextAtMouseCursor 'SemanticZone',
              mods = 'NONE',
            },
          }

          -- Dynamic padding: remove when TUI app is active (neovim, htop, etc)
          local default_padding = { left = 10, right = 10, top = 10, bottom = 10 }
          wezterm.on("update-status", function(window, _)
            local tab = window:active_tab()
            local panes = tab:panes()
            local alt_screen_active = false

            for i = 1, #panes, 1 do
              local pane = panes[i]
              if pane:is_alt_screen_active() then
                alt_screen_active = true
                break
              end
            end

            -- Preserve existing overrides (like enable_tab_bar)
            local overrides = window:get_config_overrides() or {}

            if alt_screen_active then
              overrides.window_padding = { left = 0, right = 0, top = 0, bottom = 0 }
            else
              overrides.window_padding = default_padding
            end

            -- Accent window tint: the active pane whose title matches
            -- features.base.terminal.accentPaneTitle exactly (a title set
            -- explicitly via set-tab-title) gets a translucent mauve wash over
            -- the base background, so it stands out among sibling windows.
            -- Empty option = no title ever matches = feature off.
            local accent_title = '${config.features.base.terminal.accentPaneTitle}'
            local ap = window:active_pane()
            local uv = ap and ap:get_user_vars() or {}
            if #accent_title > 0 and uv.tab_title == accent_title then
              -- Layers bypass window_background_opacity, so the base layer
              -- carries the ~0.90 translucency itself; mauve is a thin wash.
              overrides.background = {
                { source = { Color = '#${c theme.palette.base}' },  width = '100%', height = '100%', opacity = 0.90 },
                { source = { Color = '#${c theme.palette.mauve}' }, width = '100%', height = '100%', opacity = 0.12 },
              }
            else
              overrides.background = nil
            end

            window:set_config_overrides(overrides)
          end)

          -- Load project badge event handlers
          ${projectBadgesConfig}

          return config
        '';
      };
    };
  };
}
