# Waybar module configurations.
#
# A module is defined only when the feature that installs the binary behind it is
# enabled — `has` comes from ./default.nix, which owns that mapping. Nothing here
# may assume an optional program exists: a definition whose `exec` is missing
# renders as a blank or "?" chip on someone else's bar.
{ lib, niri-windows, has, terminal }:

let
  icons = import ./icons.nix;

  # Spawning a TUI needs a terminal, and which terminal that is belongs to the
  # host (see features.fluteos.waybar.terminal). Every handler built here is
  # gated on `has.terminal`, so an unconfigured terminal drops the handler
  # instead of shelling out to a program that may not be installed.
  joinArgs = parts: lib.concatStringsSep " " (lib.filter (p: p != "") parts);
  spawn = program: joinArgs [ terminal.command terminal.execFlag program ];
  # Same, but tags the window with an app-id so compositor rules can match it.
  spawnAs = appId: program: joinArgs (
    [ terminal.command ]
    ++ lib.optionals (terminal.appIdFlag != "") [ terminal.appIdFlag appId ]
    ++ [ terminal.execFlag program ]
  );

  # Always available: everything these read comes from the base system.
  alwaysModules = {
    clock = {
      format = "{:%H:%M}";
      format-alt = "{:%Y-%m-%d %H:%M}";
      tooltip-format = "<big>{:%Y %B}</big>\n<tt><small>{calendar}</small></tt>";
    };

    cpu = {
      format = "󰍛 {usage}%";
      tooltip = true;
    };

    memory = {
      format = "󰘚 {}%";
    };

    battery = {
      states = {
        warning = 30;
        critical = 15;
      };
      format = "{icon} {capacity}%";
      format-charging = "󰂄 {capacity}%";
      format-plugged = "󰚥 {capacity}%";
      format-icons = [ "󰁺" "󰁻" "󰁼" "󰁽" "󰁾" "󰁿" "󰂀" "󰂁" "󰂂" "󰁹" ];
    };

    # NetworkManager comes with features.base.system, so nmtui-connect is always
    # there — only the terminal that would host it is optional.
    network = {
      format-wifi = "󰤨 {signalStrength}%";
      format-ethernet = "󰈀 {ipaddr}";
      format-disconnected = "󰤭 ";
      tooltip-format = "{ifname}: {ipaddr}/{cidr}";
    } // lib.optionalAttrs has.terminal {
      on-click = spawn "bash -c 'sleep 0.1; nmtui-connect'";
    };

    tray = {
      spacing = 10;
    };
  };
in
alwaysModules

# features.base.audio — wpctl is wireplumber's, which comes with the feature.
// lib.optionalAttrs has.audio {
  pulseaudio = {
    format = "{icon} {volume}%";
    format-muted = "󰝟 ";
    format-icons = {
      default = [ "󰕿" "󰖀" "󰕾" ];
    };
    on-click = "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle";
  };
}

# features.fluteos.workspaces — display name of the focused workspace.
// lib.optionalAttrs has.workspaces {
  "custom/workspace-name" = {
    exec = "fluteos-workspace-display-name";
    return-type = "json";
  } // lib.optionalAttrs has.terminal {
    # The app-id matches the niri window rule that floats the rename prompt.
    on-click = spawnAs "niri-workspace-rename" "niri-workspace-rename";
  };
}

# features.base.niri — the minimap speaks the niri IPC.
// lib.optionalAttrs has.niri {
  "cffi/niri-windows" = {
    module_path = "${niri-windows}/lib/waybar-niri-windows.so";
    options = {
      mode = "graphical";
      show-floating = "never";
      spacing = 1;
      minimum-size = 30;
      icon-minimum-size = 0;
      rules = icons.titleRules ++ icons.appRules;
    };
  };
}

# features.base.obsidian — task list scripts live with the app.
// lib.optionalAttrs has.obsidian {
  "custom/obsidian" = {
    exec = "obsidian-tasks";
    return-type = "json";
    interval = 60;
    signal = 12;
    on-click = "obsidian-task-open";
    on-scroll-up = "obsidian-task-select-prev";
    on-scroll-down = "obsidian-task-select-next";
  };
}

# features.fluteos.ai-usage — what is left on every AI plan plus, when
# features.fluteos.agents is on, the status of every agent across all
# workspaces in one chip. The agent half reads a hook-written registry, so the
# poll only needs to be fast enough to feel live; the quota half is cached
# behind its own TTL inside the script and is not refetched at this rate.
# RTMIN+13 forces an immediate redraw.
// lib.optionalAttrs has.aiUsage {
  "custom/ai" = {
    exec = "fluteos-ai-usage";
    return-type = "json";
    # One second, not two: the "an agent is waiting for you" dot blinks by
    # alternating its colour between polls, and at 2s that reads as a glitch
    # rather than a blink. The quota half is cached behind its own TTL inside
    # the script, so this does not refetch anything.
    interval = 3;
    signal = 13;
    # No on-click: every provider is on the bar at once, so there is nothing
    # left to switch between. The clicks below belong to the agent half.
  } // lib.optionalAttrs has.agents {
    on-click-right = "fluteos-agents-pick";
    # "Seen them all, stop blinking." Focusing an agent's window clears its own
    # flag; this clears the lot, for when you looked and had nothing to add.
    on-click-middle = "fluteos-agents-widget --dismiss";
  };
}

# features.fluteos.recorder — records the meeting you are in, then sends it for
# transcription. The poll is slow because the chip only shows minutes; every
# state CHANGE arrives immediately via RTMIN+14, which fluteos-record and the
# transcriber both raise. When nothing is being recorded the widget answers from
# two file checks, so this costs nothing at rest.
// lib.optionalAttrs has.recorder {
  "custom/recorder" = {
    exec = "fluteos-recorder-widget";
    return-type = "json";
    interval = 10;
    signal = 14;
    # Start (asking for a label) / stop-and-transcribe.
    on-click = "fluteos-record toggle --prompt";
    on-click-middle = "fluteos-record pause-toggle";
    on-click-right = "fluteos-record open";
  };
}


# features.base.mpd — mpd-status, mpc and ncmpcpp all come with the feature.
// lib.optionalAttrs has.mpd {
  "custom/mpd" = {
    exec = "mpd-status";
    return-type = "json";
    interval = 3;
    on-click = "mpc toggle";
    on-scroll-up = "mpc next";
    on-scroll-down = "mpc prev";
  } // lib.optionalAttrs has.terminal {
    on-click-right = spawn "ncmpcpp";
  };

  "custom/mpd-prev" = {
    format = "󰒮";
    on-click = "mpc prev";
    tooltip = false;
  };

  "custom/mpd-next" = {
    format = "󰒭";
    on-click = "mpc next";
    tooltip = false;
  };
}

# features.fluteos.tailnets — shows the active Tailscale tailnet (manual model,
# no auto-switch). Polled like the other custom modules; click opens the fuzzel
# switcher, which signals RTMIN+15 to refresh this immediately after switching.
// lib.optionalAttrs has.tailnets {
  "custom/tailnet" = {
    exec = "fluteos-tailnet-watch";
    return-type = "json";
    interval = 5;
    on-click = "fluteos-tailnet-menu";
    signal = 15;
  };
}

# features.fluteos.weather
// lib.optionalAttrs has.weather {
  "custom/weather" = {
    exec = "fluteos-weather";
    interval = 1800;
    tooltip = false;
  };
}
