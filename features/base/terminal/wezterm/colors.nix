# WezTerm color scheme based on theme palette
{ theme, c }:

''
  config.colors = {
    foreground = '#${c theme.palette.text}',
    background = '#${c theme.palette.base}',
    cursor_bg = '#${c theme.palette.text}',
    cursor_border = '#${c theme.palette.text}',
    selection_bg = '#${c theme.palette.surface0}',
    selection_fg = '#${c theme.palette.text}',

    -- ANSI colors - using centralized mapping from lib/ansi-colors.nix
    -- Normal colors (0-7)
    ansi = {
      '#${c theme.ansiColors.ansi.black}',    -- 0: black
      '#${c theme.ansiColors.ansi.red}',      -- 1: red
      '#${c theme.ansiColors.ansi.green}',    -- 2: green
      '#${c theme.ansiColors.ansi.yellow}',   -- 3: yellow
      '#${c theme.ansiColors.ansi.blue}',     -- 4: blue
      '#${c theme.ansiColors.ansi.magenta}',  -- 5: magenta
      '#${c theme.ansiColors.ansi.cyan}',     -- 6: cyan
      '#${c theme.ansiColors.ansi.white}',    -- 7: white
    },

    -- Bright colors (8-15)
    brights = {
      '#${c theme.ansiColors.bright.black}',    -- 8: bright black
      '#${c theme.ansiColors.bright.red}',      -- 9: bright red
      '#${c theme.ansiColors.bright.green}',    -- 10: bright green
      '#${c theme.ansiColors.bright.yellow}',   -- 11: bright yellow
      '#${c theme.ansiColors.bright.blue}',     -- 12: bright blue
      '#${c theme.ansiColors.bright.magenta}',  -- 13: bright magenta
      '#${c theme.ansiColors.bright.cyan}',     -- 14: bright cyan
      '#${c theme.ansiColors.bright.white}',    -- 15: bright white
    },

    tab_bar = {
      background = '#${c theme.palette.mantle}',
      active_tab = {
        bg_color = '#${c theme.palette.base}',
        fg_color = '#${c theme.palette.text}',
      },
      inactive_tab = {
        bg_color = '#${c theme.palette.mantle}',
        fg_color = '#${c theme.palette.subtext1}',
      },
    },
  }
''
