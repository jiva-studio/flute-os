{ lib, config, ... }:

let
  nixosCfg = config;
in
{
  options.features.fluteos.which-key = {
    enable = lib.mkEnableOption "Which-key modal menu system";
    brainPath = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = ''
        Path to the user's notes vault (e.g. Obsidian) relative to $HOME.
        When non-empty, brain-folders fuzzy menu becomes available.
        Example: "Documents/Brain". Empty disables the menu.
      '';
    };
  };

  config = lib.mkIf nixosCfg.features.fluteos.which-key.enable {
    home-manager.users.${config.features.base.system.user.name} = { config, pkgs, theme, lib, ... }:
    let
      c = theme.helpers.c;

      # Build hostConfig shim from NixOS-level feature options
      hostConfig = {
        # The resolved launcher list, not the raw data file: which-key must show
        # what this machine has, and must not re-derive it.
        apps = nixosCfg.features.fluteos.apps.resolved or [];
        hasTurboBoost = nixosCfg.features.base.performance.turboBoost or false;
      };

      # Import modular components
      cssStyles = import ./styles.nix { inherit theme c; };
      menus = import ./menus.nix { inherit config lib hostConfig; };

      # Menu configuration combining styles and menus
      menuConfig = {
        css = cssStyles;
        inherit menus;
      };

      configFile = pkgs.writeText "which-key-config.json" (builtins.toJSON menuConfig);

      pythonEnv = pkgs.python3.withPackages (ps: [ ps.pygobject3 ]);

      # Generate JSON list of Brain folders for fuzzy menu.
      # When brainPath option is unset, the script falls back to its own default
      # ($HOME/Documents/Brain). $HOME is unknown at Nix eval time, so build the
      # absolute path inside the wrapper at runtime.
      brainPath = nixosCfg.features.fluteos.which-key.brainPath;
      brainFoldersList = pkgs.writeShellScriptBin "fluteos-brain-folders" ''
        export JQ="${pkgs.jq}/bin/jq"
        export GREP="${pkgs.gnugrep}/bin/grep"
        ${lib.optionalString (brainPath != "") ''export BRAIN_DIR="$HOME/${brainPath}"''}
        bash ${./fluteos-brain-folders.sh}
      '';

      # Get current Niri workspace name (one-shot, for menu prefill)
      niriCurrentWorkspace = pkgs.writeShellScriptBin "fluteos-niri-workspace" ''
        export NIRI="${pkgs.niri}/bin/niri"
        export JQ="${pkgs.jq}/bin/jq"
        bash ${./fluteos-niri-workspace.sh}
      '';

      # Agent scripts (fluteos-agent-check, fluteos-agent-launch) live in
      # features/fluteos/workspaces — they read the same workspaces.json registry.

      # Power control script for profile switching and turbo boost
      powerControl = pkgs.writeShellScriptBin "fluteos-power-control" ''
        export NOTIFY_SEND="${pkgs.libnotify}/bin/notify-send"
        bash ${./fluteos-power-control.sh} "$@"
      '';

      # Long-lived GtkApplication service. Owns the com.fluteos.WhichKey
      # bus name and waits for D-Bus activations — Python + GTK4 init only
      # happens once per session.
      whichKeyDaemon = pkgs.stdenv.mkDerivation {
        pname = "fluteos-which-key-daemon";
        version = "1.0.0";

        nativeBuildInputs = [ pkgs.wrapGAppsHook4 pkgs.gobject-introspection ];

        buildInputs = [
          pkgs.gtk4
          pkgs.glib
          pkgs.pango
          pkgs.gdk-pixbuf
          pkgs.graphene
          pkgs.harfbuzz
        ];

        dontUnpack = true;
        dontBuild = true;

        installPhase = ''
          mkdir -p $out/bin
          cat > $out/bin/fluteos-which-key-daemon << 'WRAPPER'
          #!${pkgs.bash}/bin/bash
          exec ${pythonEnv}/bin/python3 ${./menu.py} ${configFile}
          WRAPPER
          chmod +x $out/bin/fluteos-which-key-daemon
        '';
      };

      # Thin client invoked by the Cmd+Space keybind. A single gdbus call
      # tells the running daemon to present its window — no Python or GTK
      # involved on the hot path.
      whichKeyClient = pkgs.writeShellScriptBin "fluteos-which-key" ''
        exec ${pkgs.glib.bin}/bin/gdbus call --session \
          --dest com.fluteos.WhichKey \
          --object-path /com/fluteos/WhichKey \
          --method org.gtk.Application.Activate '@a{sv} {}' \
          >/dev/null
      '';
    in
    {
      home.packages = [
        whichKeyDaemon
        whichKeyClient
        powerControl
        brainFoldersList
        niriCurrentWorkspace
      ];

      systemd.user.services.fluteos-which-key = {
        Unit = {
          Description = "fluteos which-key menu daemon";
          After = [ "niri-session.target" ];
          Requires = [ "niri-session.target" ];
        };
        Service = {
          ExecCondition = "${pkgs.bash}/bin/bash -c 'test -n \"$WAYLAND_DISPLAY\"'";
          ExecStart = "${whichKeyDaemon}/bin/fluteos-which-key-daemon";
          Restart = "on-failure";
          RestartSec = 2;
        };
        Install.WantedBy = [ "niri-session.target" ];
      };
    };
  };
}
