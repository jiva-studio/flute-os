# Niri keybindings configuration
{ mod, config, theme, lib, osFeatures, extraBinds ? "" }:

let
  media = theme.uiConstants.mediaSteps;
  resize = theme.uiConstants.resizeSteps;

  # Spawn a program in a new terminal window, using whichever terminal the
  # terminal feature declares rather than naming one here.
  term = osFeatures.base.terminal;
  quoted = xs: lib.concatMapStringsSep " " (a: ''"${a}"'') xs;
  spawnInTerminal = appId: argv:
    ''spawn ${quoted (term.spawnCommand ++ [ term.appIdFlag appId "--" ] ++ argv)};'';

  # Bindings whose target is an optional feature: emitted only when that feature
  # is on, so a downstream install gets no key that runs a missing binary.
  optionalBind = enabled: line: if enabled then line else "";
  hasMpd = osFeatures.base.mpd.enable or false;
in
''
  binds {
      // Disable default window switchers
      Alt+Tab { spawn "true"; }
      Alt+Grave { spawn "true"; }

      // Which-key menu
      ${mod}+Space { spawn "fluteos-which-key"; }

      // Terminal & Apps
      ${mod}+Return { spawn "fluteos-workspace-terminal"; }
      ${mod}+G { spawn "fluteos-agent-prompt"; }
      ${mod}+Q { close-window; }

      // Window state
      ${mod}+F { maximize-column; }
      ${mod}+Shift+F { fullscreen-window; }
      ${mod}+Ctrl+F { expand-column-to-available-width; }
      ${mod}+R { switch-preset-column-width; }
      ${mod}+Shift+R { switch-preset-window-height; }
      ${mod}+C { center-column; }
      ${mod}+W { toggle-column-tabbed-display; }

      // Focus
      ${mod}+Left { focus-column-or-monitor-left; }
      ${mod}+Right { focus-column-or-monitor-right; }
      ${mod}+Up { focus-window-or-workspace-up; }
      ${mod}+Down { focus-window-or-workspace-down; }

      // Move windows
      ${mod}+Shift+Left { move-column-left-or-to-monitor-left; }
      ${mod}+Shift+Right { move-column-right-or-to-monitor-right; }
      ${mod}+Shift+Up { move-window-up-or-to-workspace-up; }
      ${mod}+Shift+Down { move-window-down-or-to-workspace-down; }

      // Reorder the whole workspace (raise/lower it in the monitor stack)
      ${mod}+Ctrl+Up { move-workspace-up; }
      ${mod}+Ctrl+Down { move-workspace-down; }

      // Column management
      ${mod}+BracketLeft { consume-window-into-column; }
      ${mod}+BracketRight { expel-window-from-column; }
      ${mod}+Minus { set-column-width "-${resize.column}"; }
      ${mod}+Equal { set-column-width "+${resize.column}"; }
      ${mod}+Shift+Minus { set-window-height "-${resize.window}"; }
      ${mod}+Shift+Equal { set-window-height "+${resize.window}"; }

      // Workspaces 1-10
      Ctrl+Alt+1 { focus-workspace 1; }
      Ctrl+Alt+2 { focus-workspace 2; }
      Ctrl+Alt+3 { focus-workspace 3; }
      Ctrl+Alt+4 { focus-workspace 4; }
      Ctrl+Alt+5 { focus-workspace 5; }
      Ctrl+Alt+6 { focus-workspace 6; }
      Ctrl+Alt+7 { focus-workspace 7; }
      Ctrl+Alt+8 { focus-workspace 8; }
      Ctrl+Alt+9 { focus-workspace 9; }
      Ctrl+Alt+0 { focus-workspace 10; }

      Ctrl+Alt+Shift+1 { move-window-to-workspace 1; }
      Ctrl+Alt+Shift+2 { move-window-to-workspace 2; }
      Ctrl+Alt+Shift+3 { move-window-to-workspace 3; }
      Ctrl+Alt+Shift+4 { move-window-to-workspace 4; }
      Ctrl+Alt+Shift+5 { move-window-to-workspace 5; }
      Ctrl+Alt+Shift+6 { move-window-to-workspace 6; }
      Ctrl+Alt+Shift+7 { move-window-to-workspace 7; }
      Ctrl+Alt+Shift+8 { move-window-to-workspace 8; }
      Ctrl+Alt+Shift+9 { move-window-to-workspace 9; }
      Ctrl+Alt+Shift+0 { move-window-to-workspace 10; }

      // Monitor focus
      ${mod}+N { focus-monitor-left; }
      ${mod}+M { focus-monitor-right; }
      ${mod}+Shift+N { move-column-to-monitor-left; }
      ${mod}+Shift+M { move-column-to-monitor-right; }

      // Overview
      ${mod}+O { toggle-overview; }

      // Workspace rename
      ${mod}+Comma { ${spawnInTerminal "niri-workspace-rename" [ "niri-workspace-rename" ]} }

      // Toggle waybar
      ${optionalBind (osFeatures.fluteos.waybar.enable or false)
        ''${mod}+B { spawn "pkill" "-SIGUSR1" "waybar"; }''}

      // Screenshots
      Print { screenshot; }
      Shift+Print { screenshot-screen; }
      ${mod}+Print { screenshot-window; }

      // Media keys
      XF86AudioRaiseVolume allow-when-locked=true { spawn "wpctl" "set-volume" "@DEFAULT_AUDIO_SINK@" "${media.volume}+"; }
      XF86AudioLowerVolume allow-when-locked=true { spawn "wpctl" "set-volume" "@DEFAULT_AUDIO_SINK@" "${media.volume}-"; }
      XF86AudioMute allow-when-locked=true { spawn "wpctl" "set-mute" "@DEFAULT_AUDIO_SINK@" "toggle"; }
      XF86MonBrightnessUp allow-when-locked=true { spawn "brightnessctl" "s" "+${media.brightness}"; }
      XF86MonBrightnessDown allow-when-locked=true { spawn "brightnessctl" "s" "${media.brightness}-"; }

      // Media player controls (MPD)
      ${optionalBind hasMpd ''XF86AudioPlay allow-when-locked=true { spawn "mpc" "toggle"; }''}
      ${optionalBind hasMpd ''XF86AudioNext allow-when-locked=true { spawn "mpc" "next"; }''}
      ${optionalBind hasMpd ''XF86AudioPrev allow-when-locked=true { spawn "mpc" "prev"; }''}
      ${optionalBind hasMpd ''XF86AudioStop allow-when-locked=true { spawn "mpc" "stop"; }''}

      // Push-to-talk: cycle to the next dictation mode. `ptt.toggle` is the
      // cycle script — it used to be the daemon, so this key started a second
      // one that fought the first for the input devices.
      ${if config ? ptt && config ? ptt.toggle then ''${mod}+V { spawn "${config.ptt.toggle}"; }'' else "// ptt not enabled"}

      // Window tags (focus)
      Alt+1 { spawn "niri-tags" "focus" "1"; }
      Alt+2 { spawn "niri-tags" "focus" "2"; }
      Alt+3 { spawn "niri-tags" "focus" "3"; }
      Alt+4 { spawn "niri-tags" "focus" "4"; }

      // Window tags (set)
      Alt+Shift+1 { spawn "niri-tags" "set" "1"; }
      Alt+Shift+2 { spawn "niri-tags" "set" "2"; }
      Alt+Shift+3 { spawn "niri-tags" "set" "3"; }
      Alt+Shift+4 { spawn "niri-tags" "set" "4"; }

      // Emoji picker
      ${optionalBind (osFeatures.base.emoji.enable or false)
        ''${mod}+Period { spawn "emoji"; }''}

      // Lock screen
      ${optionalBind (osFeatures.base.swaylock.enable or false)
        ''${mod}+Ctrl+L { spawn "swaylock" "-f"; }''}

      // Quit niri
      ${mod}+Shift+E { quit; }${lib.optionalString (extraBinds != "") "\n\n      ${extraBinds}"}
  }
''
