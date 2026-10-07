# Push-to-talk: option schema.
#
# This file declares the configuration surface for real-time streaming
# push-to-talk dictation (RAW mode).
#
# Two rules govern the credential options:
#   1. A secret is never read at evaluation time.
#   2. A secret is never addressed as a Nix path.
# Hence: `apiKeyFile` is a `types.str` absolute path, handed to systemd as a
# LoadCredential source and read at RUNTIME by the daemon.
{ lib, config, ... }:
let
  inherit (lib) mkOption types;

  cfg = config.features.fluteos.ptt;

  sttOptions = {
    api = mkOption {
      type = types.enum [ "deepgram" ];
      default = "deepgram";
      description = ''
        Wire protocol spoken to `endpoint`. Only the Deepgram streaming
        WebSocket shape is implemented; the option exists so `endpoint` can be
        pointed at a compatible proxy or self-hosted gateway.
      '';
    };
    endpoint = mkOption {
      type = types.str;
      default = "wss://api.deepgram.com/v1/listen";
      example = "wss://api.deepgram.com/v1/listen";
      description = "WebSocket URL of the streaming STT service (no query string; it is built from the fields below).";
    };
    model = mkOption {
      type = types.str;
      default = "nova-2";
      description = "Recognition model name passed to the service.";
    };
    language = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "en";
      description = ''
        BCP-47 language tag for recognition. Null sends no language parameter
        and lets the service decide — the distribution default, because the
        product must not assume the operator's language.
      '';
    };
    apiKeyFile = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "/home/you/fluteos-personal/secrets/deepgram.key";
      description = ''
        Absolute path, on the running machine, of a file containing the STT API
        key. Passed to systemd as a LoadCredential source and read at runtime.
      '';
    };
  };

  isEvdevKeyName = k: builtins.match "(KEY|BTN)_[A-Z0-9_]+" k != null;
in
{
  options.features.fluteos.ptt = {
    enable = lib.mkEnableOption "Push-to-talk streaming dictation (RAW mode)";

    holdKey = mkOption {
      type = types.str;
      default = "KEY_RIGHTALT";
      example = "KEY_RIGHTCTRL";
      description = ''
        Key held down to record, as an evdev key NAME from
        linux/input-event-codes.h (e.g. KEY_RIGHTALT).
      '';
    };

    stt = mkOption {
      type = types.submodule { options = sttOptions; };
      default = { };
      description = "Speech-to-text backend configuration for live dictation.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = isEvdevKeyName cfg.holdKey;
        message = "features.fluteos.ptt.holdKey = \"${cfg.holdKey}\" is not an evdev key name (expected e.g. KEY_RIGHTALT, not a scancode).";
      }
    ];

    warnings = lib.optional (cfg.stt.apiKeyFile == null)
      "features.fluteos.ptt.stt.apiKeyFile is not set — transcription is unavailable. Set features.fluteos.ptt.stt.apiKeyFile to an absolute path on the running machine.";
  };
}
