# Waybar status bar.
#
# The bar's LAYOUT is an option, not a constant. Every chip on the bar is backed
# by a helper binary that some *optional* feature installs, so a fixed list of
# modules would hand anyone but the author blank or "?" chips. The defaults for
# `modules-{left,center,right}` and `groups` are therefore DERIVED from the
# features the host actually enables; a host that wants a different arrangement
# states it explicitly.
{ lib, config, ... }:

let
  cfg = config.features.fluteos.waybar;
  base = config.features.base;
  flute = config.features.fluteos;

  # Which bar module is backed by which feature. Single source of truth for both
  # the derived layout below and the module definitions in ./modules.nix — a
  # module is only ever *defined* when the feature that installs its binary is
  # on, which is what keeps a stranger's bar free of dead chips.
  has = {
    workspaces = flute.workspaces.enable;   # fluteos-workspace-display-name
    niri = base.niri.enable;                # cffi minimap talks to the niri IPC
    mpd = base.mpd.enable;                  # mpd-status, mpc, ncmpcpp
    obsidian = base.obsidian.enable;        # obsidian-tasks, obsidian-task-*
    claudeUsage = flute.claude-usage.enable; # fluteos-claude-usage, -ai-usage-toggle
    agents = flute.agents.enable;           # fluteos-agents-pick
    ptt = flute.ptt.enable;                 # fluteos-ptt-widget, -ptt-toggle
    weather = flute.weather.enable;         # fluteos-weather
    tailnets = flute.tailnets.enable;       # fluteos-tailnet-watch, -tailnet-menu
    audio = base.audio.enable;              # wpctl (pipewire/wireplumber)
    terminal = cfg.terminal.command != "";  # handlers that open a TUI
  };

  groupType = lib.types.submodule {
    options = {
      orientation = lib.mkOption {
        type = lib.types.enum [ "horizontal" "vertical" "inherit" ];
        default = "horizontal";
        description = "Layout direction of the group's children.";
      };
      modules = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = ''
          Modules inside the group. A group whose list ends up empty is not
          emitted at all — an empty waybar group renders as a stray gap.
        '';
      };
      drawer = lib.mkOption {
        type = lib.types.nullOr (lib.types.attrsOf lib.types.anything);
        default = null;
        example = { transition-duration = 300; children-class = "not-power"; };
        description = "Waybar drawer settings, for a group that expands on hover.";
      };
    };
  };

  # --- Derived defaults ------------------------------------------------------
  # Ordering is the distribution's, not the owner's: it is the same left-to-right
  # grouping for everybody, with the chips whose features are off left out.

  playerModules = lib.optionals has.mpd [ "custom/mpd" "custom/mpd-prev" "custom/mpd-next" ];

  taskModules = lib.optionals has.obsidian [ "custom/obsidian" ];

  # NetworkManager and the load meters come with the base system, so this group
  # always exists; only the volume chip depends on a feature (wpctl).
  statusModules =
    lib.optionals has.audio [ "pulseaudio" ]
    ++ [ "network" "cpu" "memory" "battery" ];

  defaultGroups =
    lib.optionalAttrs (playerModules != [ ]) { player.modules = playerModules; }
    // lib.optionalAttrs (taskModules != [ ]) { tasks.modules = taskModules; }
    // { status.modules = statusModules; };

  # A group is put on the bar only when it exists and carries something.
  hasGroup = name: cfg.groups ? ${name} && cfg.groups.${name}.modules != [ ];

  extraModuleType = lib.types.submodule {
    options = {
      settings = lib.mkOption {
        type = lib.types.attrsOf lib.types.anything;
        description = "The waybar module definition, verbatim (`exec`, `interval`, `on-click`, …).";
      };
      position = lib.mkOption {
        type = lib.types.enum [ "left" "center" "right" ];
        default = "right";
        description = "Which of the three module lists this chip joins.";
      };
      before = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "group/status";
        description = ''
          Insert immediately before this module. Null, or a name that is not on
          the bar (its feature may be off), appends to the end of the list
          instead — a chip is never silently dropped for missing its anchor.
        '';
      };
      style = lib.mkOption {
        type = lib.types.lines;
        default = "";
        example = "#custom-thing { background: #a6e3a1; }";
        description = "CSS appended to the bar's stylesheet.";
      };
    };
  };
in
{
  options.features.fluteos.waybar = {
    enable = lib.mkEnableOption "Waybar status bar";

    modules-left = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default =
        lib.optionals has.workspaces [ "custom/workspace-name" ]
        ++ lib.optionals has.niri [ "cffi/niri-windows" ];
      defaultText = lib.literalMD "derived from the enabled features";
      description = "Waybar `modules-left`. Module names, including `group/<name>` from `groups`.";
    };

    modules-center = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Waybar `modules-center`. Empty by default — the bar keeps its middle free for window titles.";
    };

    modules-right = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default =
        lib.optionals (hasGroup "player") [ "group/player" ]
        ++ lib.optionals (hasGroup "tasks") [ "group/tasks" ]
        ++ lib.optionals has.claudeUsage [ "custom/claude" ]
        ++ lib.optionals (hasGroup "status") [ "group/status" ]
        ++ lib.optionals has.ptt [ "custom/ptt-mode" ]
        ++ lib.optionals has.weather [ "custom/weather" ]
        ++ [ "clock" ]
        ++ lib.optionals has.tailnets [ "custom/tailnet" ]
        ++ [ "tray" ];
      defaultText = lib.literalMD "derived from the enabled features";
      description = "Waybar `modules-right`. Module names, including `group/<name>` from `groups`.";
    };

    extraModules = lib.mkOption {
      type = lib.types.attrsOf extraModuleType;
      default = { };
      example = lib.literalExpression ''
        {
          "custom/mailbox" = {
            settings = { exec = "my-unread-count"; return-type = "json"; interval = 60; on-click = "my-mail-client"; };
            before = "group/status";
            style = "#custom-mailbox { background: #a6e3a1; }";
          };
        }
      '';
      description = ''
        Chips contributed from outside this module, keyed by waybar module name.

        The bar's own chips are derived from the features FluteOS ships, so
        anything installed elsewhere — a private overlay, a host that packages
        its own widget — has no way to reach the layout. This is that way in:
        the definition, where it sits and its CSS travel together, and they are
        spliced in regardless of whether the host also overrode
        `modules-left/center/right` by hand.
      '';
    };

    groups = lib.mkOption {
      type = lib.types.attrsOf groupType;
      default = defaultGroups;
      defaultText = lib.literalMD "`player` / `tasks` / `status`, each holding only the modules whose features are enabled";
      example = lib.literalExpression ''
        {
          status.modules = [ "pulseaudio" "network" "battery" ];
          media = { orientation = "horizontal"; modules = [ "custom/mpd" ]; };
        }
      '';
      description = ''
        `group/<name>` definitions. Reference a group from `modules-left` /
        `modules-center` / `modules-right` as `group/<name>`.
      '';
    };

    terminal = {
      command = lib.mkOption {
        type = lib.types.str;
        default = lib.optionalString config.features.base.terminal.enable
          (lib.concatStringsSep " " config.features.base.terminal.spawnCommand);
        defaultText = lib.literalMD
          "`features.base.terminal.spawnCommand`, or empty when no terminal is installed";
        example = "wezterm start";
        description = ''
          Command that opens a terminal window, used by the bar handlers that
          run a TUI (workspace rename, `nmtui-connect`, `ncmpcpp`). Follows the
          terminal feature by default, so the terminal is named in exactly one
          place; empty when no terminal is installed, in which case those
          handlers are left out rather than pointing at nothing.
        '';
      };
      execFlag = lib.mkOption {
        type = lib.types.str;
        default = "--";
        example = "-e";
        description = "Separator between `command` and the program to run — `--` for wezterm/kitty, `-e` for alacritty, empty for foot.";
      };
      appIdFlag = lib.mkOption {
        type = lib.types.str;
        default = config.features.base.terminal.appIdFlag;
        defaultText = lib.literalMD "`features.base.terminal.appIdFlag`";
        example = "--app-id";
        description = ''
          Flag that sets the new window's app-id, for handlers whose window has
          a compositor rule attached to it. Empty means the app-id is not set.
        '';
      };
    };

    # Geometry. Not identity, but it is fitted to a font size and a panel, so a
    # HiDPI machine or a vertical strip needs to say something else.
    height = lib.mkOption {
      type = lib.types.ints.positive;
      default = 38;
      description = "Bar height in pixels.";
    };
    spacing = lib.mkOption {
      type = lib.types.ints.unsigned;
      default = 1;
      description = "Gap in pixels between adjacent modules.";
    };
    margin = lib.mkOption {
      type = lib.types.attrsOf lib.types.ints.unsigned;
      default = { top = 6; left = 8; right = 8; };
      example = { top = 0; left = 0; right = 0; };
      description = ''
        Outer margins in pixels, keyed by edge (`top`, `bottom`, `left`,
        `right`). Only the edges present here are emitted.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # `@hm` rather than destructuring `config`: everything above reads the NixOS
    # config through the outer `config`, and a second one in scope here would
    # shadow it silently.
    home-manager.users.${config.features.base.system.user.name} = { pkgs, theme, ... }@hm:
    let
      niri-windows = pkgs.callPackage ./niri-windows.nix { };
      modules = import ./modules.nix {
        inherit lib niri-windows has;
        terminal = cfg.terminal;
      };
      style = import ./style.nix { inherit theme; };

      groupAttrs = lib.mapAttrs' (name: g: lib.nameValuePair "group/${name}" (
        { inherit (g) orientation modules; }
        // lib.optionalAttrs (g.drawer != null) { inherit (g) drawer; }
      )) (lib.filterAttrs (_: g: g.modules != [ ]) cfg.groups);

      marginAttrs = lib.mapAttrs' (edge: px: lib.nameValuePair "margin-${edge}" px) cfg.margin;

      # Splice cfg.extraModules into the three lists. Done here rather than in
      # the option defaults so a host that states `modules-right` by hand still
      # gets the contributed chips instead of quietly losing them.
      insertOne = list: name:
        let e = cfg.extraModules.${name}; in
        if e.before != null && lib.elem e.before list
        then lib.concatMap (m: if m == e.before then [ name m ] else [ m ]) list
        else list ++ [ name ];
      placed = position: list: lib.foldl' insertOne list
        (lib.attrNames (lib.filterAttrs (_: e: e.position == position) cfg.extraModules));

      extraStyle = lib.concatMapStrings (e: e.style) (lib.attrValues cfg.extraModules);
      extraSettings = lib.mapAttrs (_: e: e.settings) cfg.extraModules;
    in
    {
      programs.waybar = {
        enable = true;
        settings = {
          mainBar = {
            layer = "top";
            position = "top";
            inherit (cfg) height spacing;

            modules-left = placed "left" cfg.modules-left;
            modules-center = placed "center" cfg.modules-center;
            modules-right = placed "right" cfg.modules-right;
          } // marginAttrs // groupAttrs // modules // extraSettings;
        };
        style = style + extraStyle;
      };

      systemd.user.services.waybar = {
        Unit = {
          Description = "Waybar - Wayland bar for Niri";
          PartOf = [ "niri-session.target" ];
          After = [ "niri-session.target" ];
          # Waybar reads its config, its stylesheet and — through the workspace
          # chip's helper — the workspaces registry exactly once, when it
          # starts. None of that is in the unit, so without naming the files
          # here a rebuild leaves the running bar on yesterday's data: a project
          # added today shows up as its raw `group:project` id, and a restyled
          # chip does not change at all until the next login.
          X-Restart-Triggers = [
            "${hm.config.xdg.configFile."waybar/config".source}"
            "${hm.config.xdg.configFile."waybar/style.css".source}"
          ] ++ lib.optional (hm.config.features.fluteos.workspaces ? registryPath)
              hm.config.features.fluteos.workspaces.registryPath;
        };
        Service = {
          Type = "simple";
          ExecStart = "${pkgs.waybar}/bin/waybar";
          Restart = "on-failure";
          RestartSec = 2;
        };
        Install.WantedBy = [ "niri-session.target" ];
      };
    };
  };
}
