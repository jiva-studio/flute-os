# Meeting recorder: capture a whole session, then hand it to a transcriber.
#
# What this is NOT is push-to-talk. features.fluteos.ptt records for as long as
# a key is held and types the result straight back at you; this runs for hours,
# unattended, and its product is a file read later. The failure modes are
# therefore different ones, and the design is mostly about them:
#
#   * audio is written in SEGMENTS, so a crash, a suspend or a full disk two
#     hours in costs one segment instead of the meeting;
#   * transcription is a SEPARATE, resumable pass over those segments — the
#     recording is safely on disk before any network call is made, and a run
#     that half-failed is finished by running it again;
#   * the recording is a systemd unit, so closing the terminal, the bar, or the
#     session that started it does not take the meeting with it.
#
# Where a recording goes is the workspace's business: the focused workspace's
# `resourcesDir` from features.fluteos.workspaces, resolved once at the start.
{ lib, config, ... }:
let
  cfg = config.features.fluteos.recorder;
  theme = config.features.fluteos.theme.resolved;
in
{
  options.features.fluteos.recorder = {
    enable = lib.mkEnableOption "Meeting recorder (system audio + microphone) with transcription";

    segmentSeconds = lib.mkOption {
      type = lib.types.ints.positive;
      default = 900;
      description = ''
        Length of one audio segment. This is the blast radius of a crash: only
        the segment being written when ffmpeg dies is lost. It is also the unit
        of transcription, so very long segments push a single upload towards
        the transcriber's request limits.
      '';
    };

    directoryName = lib.mkOption {
      type = lib.types.str;
      default = "recordings";
      description = "Subdirectory of the workspace's `resourcesDir` that recordings are written into.";
    };

    fallbackDir = lib.mkOption {
      type = lib.types.str;
      default = "";
      defaultText = lib.literalMD "`$HOME/recordings`";
      example = "/home/you/Meetings";
      description = ''
        Where to record when the focused workspace has no registry entry — a
        scratch workspace, or a host without features.fluteos.workspaces.

        There is deliberately no "refuse to record" mode: losing a meeting
        because the compositor was on the wrong workspace is a worse outcome
        than a file in the wrong folder.
      '';
    };

    minFreeMb = lib.mkOption {
      type = lib.types.ints.positive;
      default = 500;
      description = "Refuse to start with less free space than this. Recording costs roughly 11 MB per hour.";
    };

    sampleRate = lib.mkOption {
      type = lib.types.ints.positive;
      default = 16000;
      description = "Capture sample rate. 16 kHz is what speech recognition consumes; higher rates cost size and buy nothing here.";
    };

    bitrate = lib.mkOption {
      type = lib.types.str;
      default = "24k";
      description = "Opus bitrate for the mixed mono track.";
    };

    levelling = lib.mkOption {
      type = lib.types.enum [ "speechnorm" "none" ];
      default = "speechnorm";
      description = ''
        Even out how loud the voices are, on each input separately, while the
        meeting is being recorded.

        A fixed gain balances the microphone against the meeting and no more —
        inside the meeting the participants are still at whatever level their
        own microphones give, one twice as loud as the next on the same input,
        and no single number follows that. `speechnorm` does: it works towards
        a target peak a phrase at a time, only ever amplifying, capped so the
        silence between sentences is not lifted into a hiss.

        `none` records the levels exactly as they arrive.
      '';
    };

    micGainDb = lib.mkOption {
      type = lib.types.number;
      default = 0;
      example = -6;
      description = ''
        Gain applied to the microphone before it is mixed with the system
        audio, in dB.

        The two sources are summed as they come, so nothing balances them
        against each other: a laptop microphone with automatic gain usually
        sits well above a meeting playing at a third of the system volume, and
        the owner of the machine ends up the loudest voice in their own
        recording — which also skews diarisation towards them.

        Negative values quieten the microphone. Compare the two sides before
        picking a number rather than guessing.
      '';
    };

    systemGainDb = lib.mkOption {
      type = lib.types.number;
      default = 0;
      example = 6;
      description = "Gain applied to the system audio before the mix, in dB. The other half of `micGainDb`.";
    };

    live = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Transcribe the meeting AS IT HAPPENS, over Deepgram's streaming
          endpoint, into a floating window split by speaker.

          This is a second, independent path over the same audio: the segments
          are still written and are still the record. Nothing here can stop or
          truncate a recording — the live tap is dropped rather than allowed to
          stall the encoder.

          Billed separately from the batch pass. Running both over every
          meeting pays for the same hour twice, which is why
          `transcribe.auto = false` is the natural companion to this.
        '';
      };

      endpoint = lib.mkOption {
        type = lib.types.str;
        default = "wss://api.deepgram.com/v1/listen";
        description = "Streaming transcription endpoint. Anything speaking Deepgram's WebSocket shape works.";
      };

      model = lib.mkOption {
        type = lib.types.str;
        default = "nova-3";
        description = "Model used for the live stream.";
      };

      language = lib.mkOption {
        type = lib.types.str;
        default = "en";
        example = "ru";
        description = ''
          Language of the live stream.

          Deliberately NOT inherited from `transcribe.language`: the batch pass
          accepts `multi`, and Deepgram does not document it for streaming. Set
          the language you actually speak, and expect the socket to be refused
          if you set something the streaming endpoint does not take.
        '';
      };

      window = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Open the floating transcript window when a recording starts. With it
          off the live transcript is still written; `fluteos-record live` opens
          the window on demand.
        '';
      };
    };

    transcribe = {
      auto = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Queue transcription as soon as a recording is stopped. With it off, `fluteos-record transcribe` does it on demand.";
      };

      endpoint = lib.mkOption {
        type = lib.types.str;
        default = "https://api.deepgram.com/v1/listen";
        description = "Pre-recorded transcription endpoint. Anything speaking Deepgram's API works here, including a self-hosted one.";
      };

      model = lib.mkOption {
        type = lib.types.str;
        default = "nova-3";
        description = "Transcription model.";
      };

      language = lib.mkOption {
        type = lib.types.str;
        default = "multi";
        example = "ru";
        description = "Language code, or `multi` for code-switching within one meeting (nova-3 only).";
      };

      apiKeyFile = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "/run/secrets/deepgram.key";
        description = ''
          Path to a file holding the API key. A PATH, and a `str` rather than a
          `path`: a Nix path would be copied into the world-readable store at
          evaluation time. The file is read at runtime, by systemd, as a
          credential — never by this module and never into the environment.

          Without it, recording still works; transcription reports that it is
          unconfigured.
        '';
      };
    };
  };

  config = lib.mkIf cfg.enable {
    warnings = lib.optional (cfg.transcribe.auto && cfg.transcribe.apiKeyFile == null)
      "features.fluteos.recorder: transcribe.auto is on but transcribe.apiKeyFile is null — recordings will be saved but never transcribed.";

    home-manager.users.${config.features.base.system.user.name} = { pkgs, lib, config, ... }:
    let
      fallbackDir = if cfg.fallbackDir != "" then cfg.fallbackDir
                    else "${config.home.homeDirectory}/recordings";
      # Survives a reboot on purpose: `fluteos-record transcribe` with no
      # argument means "the last meeting", which is most useful the morning
      # after the network was down.
      lastFile = "${config.home.homeDirectory}/.cache/fluteos/record-last";

      fuzzelTheme = theme.fuzzel.env;

      captureScript = pkgs.writeShellScriptBin "fluteos-record-capture" ''
        export JQ="${pkgs.jq}/bin/jq"
        export FFMPEG="${pkgs.ffmpeg}/bin/ffmpeg"
        export WPCTL="${pkgs.wireplumber}/bin/wpctl"
        export NOTIFY_SEND="${pkgs.libnotify}/bin/notify-send"
        export SEGMENT_SECONDS="${toString cfg.segmentSeconds}"
        export SAMPLE_RATE="${toString cfg.sampleRate}"
        export BITRATE="${cfg.bitrate}"
        export LIVE_ENABLED="${if cfg.live.enable then "1" else "0"}"
        export MIC_GAIN_DB="${toString cfg.micGainDb}"
        export SYSTEM_GAIN_DB="${toString cfg.systemGainDb}"
        export LEVELLING="${cfg.levelling}"
        exec bash ${./fluteos-record-capture.sh} "$@"
      '';

      transcribeScript = pkgs.writeShellScriptBin "fluteos-record-transcribe" ''
        export JQ="${pkgs.jq}/bin/jq"
        export CURL="${pkgs.curl}/bin/curl"
        export FFPROBE="${pkgs.ffmpeg}/bin/ffprobe"
        export NOTIFY_SEND="${pkgs.libnotify}/bin/notify-send"
        export PKILL="${pkgs.procps}/bin/pkill"
        export ENDPOINT="${cfg.transcribe.endpoint}"
        export MODEL="${cfg.transcribe.model}"
        export LANGUAGE="${cfg.transcribe.language}"
        bash ${./fluteos-record-transcribe.sh} "$@"
      '';

      recordScript = pkgs.writeShellScriptBin "fluteos-record" ''
        export JQ="${pkgs.jq}/bin/jq"
        export NIRI="${pkgs.niri}/bin/niri"
        export FFPROBE="${pkgs.ffmpeg}/bin/ffprobe"
        export FUZZEL="${pkgs.fuzzel}/bin/fuzzel"
        export NOTIFY_SEND="${pkgs.libnotify}/bin/notify-send"
        export PKILL="${pkgs.procps}/bin/pkill"
        export SYSTEMCTL="${pkgs.systemd}/bin/systemctl"
        export SYSTEMD_RUN="${pkgs.systemd}/bin/systemd-run"
        export XDG_OPEN="${pkgs.xdg-utils}/bin/xdg-open"
        export TRANSCRIBE_SCRIPT="${transcribeScript}/bin/fluteos-record-transcribe"
        export DEEPGRAM_KEY_FILE="${lib.optionalString (cfg.transcribe.apiKeyFile != null) cfg.transcribe.apiKeyFile}"
        export AUTO_TRANSCRIBE="${if cfg.transcribe.auto then "1" else "0"}"
        export FALLBACK_DIR="${fallbackDir}"
        export DIR_NAME="${cfg.directoryName}"
        export MIN_FREE_MB="${toString cfg.minFreeMb}"
        export LAST_FILE="${lastFile}"
        export LIVE_ENABLED="${if cfg.live.enable then "1" else "0"}"
        export LIVE_WINDOW="${lib.optionalString cfg.live.window "${liveWindow}/bin/fluteos-record-live-window"}"
        export WORKSPACE_REGISTRY_CMD="fluteos-workspaces-registry-path"
        ${fuzzelTheme}
        bash ${./fluteos-record.sh} "$@"
      '';

      # Two interpreters, because the two halves need different worlds: the
      # streaming client wants a socket and nothing else, the window wants all
      # of GTK. Keeping them apart means the process holding the meeting's
      # audio does not carry a UI toolkit it never calls.
      liveEnv = pkgs.python3.withPackages (ps: [ ps.websocket-client ]);
      windowEnv = pkgs.python3.withPackages (ps: [ ps.pygobject3 ]);

      liveScript = pkgs.writeShellScriptBin "fluteos-record-live" ''
        export JQ="${pkgs.jq}/bin/jq"
        export PYTHON="${liveEnv}/bin/python3"
        export LIVE_SCRIPT="${./fluteos-record-live.py}"
        export ENDPOINT="${cfg.live.endpoint}"
        export MODEL="${cfg.live.model}"
        export LANGUAGE="${cfg.live.language}"
        export SAMPLE_RATE="${toString cfg.sampleRate}"
        exec bash ${./fluteos-record-live.sh} "$@"
      '';

      liveWindow = pkgs.stdenv.mkDerivation {
        pname = "fluteos-record-live-window";
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
          cat > $out/bin/fluteos-record-live-window << 'WRAPPER'
          #!${pkgs.bash}/bin/bash
          export LIVE_BG="${theme.palette.base}"
          export LIVE_FG="${theme.palette.text}"
          export LIVE_DIM="${theme.palette.overlay0}"
          export LIVE_SPEAKERS="${lib.concatStringsSep "," (with theme.palette; [
            blue green yellow red mauve teal
          ])}"
          exec ${windowEnv}/bin/python3 ${./fluteos-record-live-window.py} "$@"
          WRAPPER
          chmod +x $out/bin/fluteos-record-live-window
        '';
      };

      recorderWidget = pkgs.writeShellScriptBin "fluteos-recorder-widget" ''
        export JQ="${pkgs.jq}/bin/jq"
        export RECORD="${recordScript}/bin/fluteos-record"
        # `ink`, not the plain accents: these are drawn ON a bar chip, whose
        # background is already an accent colour.
        export COLOR_REC="${theme.palette.ink.red}"
        export COLOR_WARN="${theme.palette.ink.amber}"
        bash ${./fluteos-recorder-widget.sh}
      '';
    in
    {
      home.packages = [ recordScript captureScript transcribeScript recorderWidget ]
        ++ lib.optionals cfg.live.enable [ liveScript liveWindow ];

      systemd.user.services.fluteos-record = {
        Unit = {
          Description = "FluteOS meeting recorder";
          # Started on demand by fluteos-record, never by a target: a recording
          # begins when you say so.
          After = [ "pipewire.service" ];
          Wants = [ "pipewire.service" ];
        };
        Service = {
          ExecStart = "${captureScript}/bin/fluteos-record-capture";

          # SIGINT, not SIGTERM. ffmpeg treats SIGINT as "stop cleanly": it
          # flushes the encoder and closes the Ogg container. SIGTERM kills it
          # where it stands and leaves the segment that was open truncated —
          # which is precisely the last few minutes of the meeting, the part
          # nobody has heard yet.
          KillSignal = "SIGINT";
          KillMode = "mixed";
          TimeoutStopSec = 20;

          # No restart. A recorder that silently comes back has lost the
          # boundary between what was captured and what was not; the state file
          # outlives the unit, so `fluteos-record status` reports "aborted" and
          # the bar says so instead of pretending.
          Restart = "no";
        };
      };

      systemd.user.services.fluteos-record-live = lib.mkIf cfg.live.enable {
        Unit = {
          Description = "FluteOS live meeting transcription";
          After = [ "pipewire.service" ];
        };
        Service = {
          ExecStart = "${liveScript}/bin/fluteos-record-live";

          # The key reaches the client the same way it reaches the batch pass:
          # a credential in a unit-private tmpfs, never an environment variable
          # and never a path this module reads at evaluation time.
          LoadCredential = lib.optional (cfg.transcribe.apiKeyFile != null)
            "deepgram:${cfg.transcribe.apiKeyFile}";

          # No restart, for the same reason the recorder has none: coming back
          # silently would reopen the pipe under a capture that has already
          # moved on, and the transcript would gain a hole nobody was told
          # about. `fluteos-record resume` is what starts a new live session.
          Restart = "no";
          TimeoutStopSec = 15;
        };
      };
    };

    # The transcript window floats, and is placed where a meeting's second
    # screen belongs: bottom-right, out of the way of whatever is being shared.
    features.base.niri.extraWindowRules = lib.mkIf cfg.live.enable ''
      window-rule {
          match app-id="com.fluteos.RecordLive"
          open-floating true
          default-column-width { fixed 560; }
          default-floating-position x=16 y=16 relative-to="bottom-right"
      }
    '';
  };
}
