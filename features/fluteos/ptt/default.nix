# Push-to-talk: packaging and wiring.
#
# Options (and their assertions/warnings) live in ./options.nix. This file turns
# the resolved option values into a JSON config, a Python package, two shell
# helpers and a user service.
#
# The mode table is serialised ONCE here and consumed by all three runtime
# pieces (daemon, waybar widget, toggle script). None of them carries a fallback
# copy: a missing config is a loud failure, because a silent fallback would ship
# whatever the last editor happened to have in mind — including their language.
{ lib, config, ... }:
let
  cfg = config.features.fluteos.ptt;

  # Credential names handed to systemd. One per (mode, backend) pair that has a
  # key file; the same file loaded twice under two names costs nothing and keeps
  # the mapping readable in `systemctl show`.
  sttCredential = id: m: if m.stt.apiKeyFile != null then "stt-${id}" else null;
  llmCredential = id: m: if m.behavior == "llm" && m.llm.apiKeyFile != null then "llm-${id}" else null;

  credentials = lib.flatten (lib.mapAttrsToList
    (id: m:
      (lib.optional (sttCredential id m != null) { name = sttCredential id m; path = m.stt.apiKeyFile; })
      ++ (lib.optional (llmCredential id m != null) { name = llmCredential id m; path = m.llm.apiKeyFile; })
    )
    cfg.modes);

  # Fully resolved per-mode view. Inheritance is done here, in Nix, so the
  # runtime never has to merge anything — and so `nix eval` shows exactly what
  # the daemon will see. Note what is absent: key CONTENTS (never read at eval
  # time) and key PATHS (the daemon reads credentials, not paths).
  resolvedModes = lib.mapAttrs
    (id: m: {
      inherit (m) name icon behavior prompt command;
      stt = {
        inherit (m.stt) api endpoint model language;
        credential = sttCredential id m;
      };
      llm = {
        inherit (m.llm) api endpoint model;
        maxTokens = m.llm.maxTokens;
        credential = llmCredential id m;
      };
    })
    cfg.modes;

  runtimeConfig = {
    version = 1;
    holdKey = cfg.holdKey;
    cycleKeys = cfg.cycleKeys;
    defaultMode = cfg.defaultMode;
    order = cfg.modeOrder;
    modes = resolvedModes;
  };
in
{
  imports = [ ./options.nix ];

  config = lib.mkIf cfg.enable {
    home-manager.users.${config.features.base.system.user.name} = { pkgs, lib, config, ... }:
    let
      pythonEnv = pkgs.python3.withPackages (ps: [
        ps.evdev
        ps.websocket-client
        ps.pyaudio
        ps.pyudev
        ps.httpx
      ]);

      configFile = pkgs.writeText "fluteos-ptt.json" (builtins.toJSON runtimeConfig);

      pttScript = pkgs.stdenv.mkDerivation {
        pname = "fluteos-ptt";
        version = "1.0.0";
        # Only the Python sources go into the store. A permissive filter is
        # exactly how a stray `deepgram.key` next to these files would end up
        # published in /nix/store, so the filter is an allow-list.
        src = lib.cleanSourceWith {
          src = ./.;
          filter = path: type:
            let base = baseNameOf (toString path); in
            if type == "directory" then base != "__pycache__"
            else lib.hasSuffix ".py" base;
        };

        nativeBuildInputs = [ pkgs.makeWrapper ];

        installPhase = ''
          mkdir -p $out/lib/ptt
          cp -r $src/* $out/lib/ptt/

          # PYTHONPATH belongs in the wrapper, not only in the systemd unit's
          # Service.Environment: fluteos-ptt is on the user's PATH via
          # home.packages, and running it from a terminal died with
          # "No module named ptt" because the hand-written wrapper set nothing.
          makeWrapper ${pythonEnv}/bin/python3 $out/bin/fluteos-ptt \
            --add-flags "-m ptt.main" \
            --set PYTHONPATH $out/lib
        '';
      };

      # PTT Widget script - outputs JSON for waybar
      pttWidget = pkgs.writeShellScriptBin "fluteos-ptt-widget" ''
        export JQ="${pkgs.jq}/bin/jq"
        export STDBUF="${pkgs.coreutils}/bin/stdbuf"
        export FLUTEOS_PTT_CONFIG="${configFile}"
        bash ${./fluteos-ptt-widget.sh}
      '';

      # PTT Toggle script - cycles through modes
      pttToggle = pkgs.writeShellScriptBin "fluteos-ptt-toggle" ''
        export JQ="${pkgs.jq}/bin/jq"
        export NOTIFY_SEND="${pkgs.libnotify}/bin/notify-send"
        export PKILL="${pkgs.procps}/bin/pkill"
        export FLUTEOS_PTT_CONFIG="${configFile}"
        bash ${./fluteos-ptt-toggle.sh}
      '';

    in
    {
      # Named for what they hold. `toggle` used to be the DAEMON and the mode
      # cycler was `toggleMode`, so the compositor's mod+V — bound to `toggle` —
      # started a second daemon that fought the first one for the evdev devices.
      options.ptt.daemon = lib.mkOption {
        type = lib.types.path; default = pttScript;
        description = "The push-to-talk daemon itself; run by the systemd user unit, not by a keybinding.";
      };
      options.ptt.toggle = lib.mkOption {
        type = lib.types.path; default = pttToggle;
        description = "Cycles to the next dictation mode. This is what a keybinding should spawn.";
      };
      options.ptt.widget = lib.mkOption { type = lib.types.path; default = pttWidget; };

      config = {
        home.packages = [ pttScript pttWidget pttToggle pkgs.wl-clipboard pkgs.wtype pkgs.portaudio pkgs.wireplumber ];

        systemd.user.services.fluteos-ptt = {
          Unit = {
            Description = "PTT";
            After = [ "niri-session.target" "pipewire.service" ];
            Requires = [ "niri-session.target" ];
            Wants = [ "pipewire.service" ];
          };
          Service = {
            ExecStart = "${pttScript}/bin/fluteos-ptt";
            Restart = "on-failure";
            Environment = [
              "PYTHONUNBUFFERED=1"
              "PYTHONPATH=${pttScript}/lib"
              "WTYPE_PATH=${pkgs.wtype}/bin/wtype"
              "NOTIFY_SEND_PATH=${pkgs.libnotify}/bin/notify-send"
              "FLUTEOS_PTT_CONFIG=${configFile}"
            ];
          }
          # API keys travel as systemd credentials, never as environment
          # variables: `Environment=` is visible to anyone who can read
          # /proc/<pid>/environ or run `systemctl show`, and would additionally
          # be inherited by every process the daemon spawns (wtype, notify-send,
          # the command sink). LoadCredential copies each file into a 0400 tmpfs
          # readable only by this service, and the daemon reads it from
          # $CREDENTIALS_DIRECTORY at runtime.
          #
          # The paired empty `SetCredential=` is what keeps a missing key file
          # non-fatal at the systemd level (systemd.exec: "not being able to
          # retrieve the credential from the path specified in LoadCredential=
          # is not considered fatal" when a SetCredential= default exists). The
          # daemon then sees a zero-length credential and reports the specific
          # mode as unconfigured — instead of the unit failing to start with an
          # opaque error before any of our code runs.
          // lib.optionalAttrs (credentials != [ ]) {
            LoadCredential = map (c: "${c.name}:${c.path}") credentials;
            SetCredential = map (c: "${c.name}:") credentials;
          };
          Install.WantedBy = [ "niri-session.target" ];
        };
      };
    };
  };
}
