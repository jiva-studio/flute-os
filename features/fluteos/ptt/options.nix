# Push-to-talk: option schema.
#
# This file is the product surface of the ptt feature: it declares *what* can be
# configured and supplies neutral defaults. Nothing here encodes a language, a
# prompt, or a key file — those are values, and values live in personal/.
#
# Two rules govern the credential options:
#   1. A secret is never read at evaluation time. `builtins.readFile` would
#      inline the key into the systemd unit *and* into the derivation hash, i.e.
#      into the world-readable /nix/store.
#   2. A secret is never addressed as a Nix path (`./x.key`, `types.path`).
#      Anything Nix addresses as a path is copied into the store, which is the
#      same leak by another route.
# Hence: `apiKeyFile` is a `types.str` absolute path, handed to systemd as a
# LoadCredential source and read at RUNTIME by the daemon.
{ lib, config, ... }:
let
  inherit (lib) mkOption types;

  cfg = config.features.fluteos.ptt;

  # ---------------------------------------------------------------- backends --

  # Speech-to-text backend. `defaults` lets the same option set serve both the
  # global backend (literal product defaults) and a per-mode override, where the
  # defaults are the *resolved* global values — so a mode that only overrides
  # `language` inherits endpoint, model and key from the global backend.
  sttOptions = defaults: {
    api = mkOption {
      type = types.enum [ "deepgram" ];
      default = defaults.api;
      description = ''
        Wire protocol spoken to `endpoint`. Only the Deepgram streaming
        WebSocket shape is implemented; the option exists so `endpoint` can be
        pointed at a compatible proxy or self-hosted gateway.
      '';
    };
    endpoint = mkOption {
      type = types.str;
      default = defaults.endpoint;
      example = "wss://api.deepgram.com/v1/listen";
      description = "WebSocket URL of the streaming STT service (no query string; it is built from the fields below).";
    };
    model = mkOption {
      type = types.str;
      default = defaults.model;
      description = "Recognition model name passed to the service.";
    };
    language = mkOption {
      type = types.nullOr types.str;
      default = defaults.language;
      example = "en";
      description = ''
        BCP-47 language tag for recognition. Null sends no language parameter
        and lets the service decide — the distribution default, because the
        product must not assume the operator's language.
      '';
    };
    apiKeyFile = mkOption {
      type = types.nullOr types.str;
      default = defaults.apiKeyFile;
      example = "/home/you/fluteos-personal/secrets/deepgram.key";
      description = ''
        Absolute path, on the running machine, of a file containing the STT API
        key. A STRING and deliberately not `types.path`: a Nix path is copied
        into the world-readable /nix/store, publishing the key to every local
        user. The file is passed to systemd as a LoadCredential source and read
        at runtime; its contents never enter the store, the unit file, or the
        service environment.

        Null (the default) means no key: a build-time warning is emitted and
        the daemon refuses to start with a clear message.
      '';
    };
  };

  # Large-language-model backend used by `behavior = "llm"` modes.
  llmOptions = defaults: {
    api = mkOption {
      type = types.enum [ "anthropic" ];
      default = defaults.api;
      description = ''
        Wire protocol spoken to `endpoint`. Only the Anthropic Messages API
        shape is implemented; the option exists so `endpoint` can be pointed at
        a compatible proxy.
      '';
    };
    endpoint = mkOption {
      type = types.str;
      default = defaults.endpoint;
      example = "https://api.anthropic.com/v1/messages";
      description = "Full URL of the chat-completion endpoint.";
    };
    model = mkOption {
      type = types.str;
      default = defaults.model;
      description = "Model id sent with each request.";
    };
    maxTokens = mkOption {
      type = types.ints.positive;
      default = defaults.maxTokens;
      description = "Upper bound on the reply length. Dictation rewrites are short; 1024 is ample.";
    };
    apiKeyFile = mkOption {
      type = types.nullOr types.str;
      default = defaults.apiKeyFile;
      example = "/home/you/fluteos-personal/secrets/anthropic.key";
      description = ''
        Absolute path, on the running machine, of a file containing the LLM API
        key. Same string-path rule and same runtime-read mechanism as
        `stt.apiKeyFile`.

        Null (the default) degrades gracefully: plain dictation keeps working
        and only `behavior = "llm"` modes report themselves unconfigured.
      '';
    };
  };

  # Product defaults. Nothing here is personal: no prompt, no language, no key.
  sttDefaults = {
    api = "deepgram";
    endpoint = "wss://api.deepgram.com/v1/listen";
    model = "nova-2";
    language = null;
    apiKeyFile = null;
  };

  llmDefaults = {
    api = "anthropic";
    endpoint = "https://api.anthropic.com/v1/messages";
    # Current Sonnet alias. Intentionally undated: dated snapshots retire, and a
    # retired id fails at runtime with a 404 the user cannot fix without editing
    # the product.
    model = "claude-sonnet-5";
    maxTokens = 1024;
    apiKeyFile = null;
  };

  mkSttType = defaults: types.submodule { options = sttOptions defaults; };
  mkLlmType = defaults: types.submodule { options = llmOptions defaults; };

  # ------------------------------------------------------------------- modes --

  modeType = types.submodule ({ name, ... }: {
    options = {
      name = mkOption {
        type = types.str;
        default = name;
        description = "Label shown in waybar and notifications. Defaults to the attribute key.";
      };

      icon = mkOption {
        type = types.str;
        default = "";
        description = "Glyph shown next to the label (Nerd Font or emoji). Empty = no icon.";
      };

      behavior = mkOption {
        type = types.enum [ "live" "llm" "command" ];
        default = "live";
        description = ''
          What happens to the transcript:

          - `live`    — typed into the focused window as it arrives, interim
                        results included (plain dictation).
          - `llm`     — buffered, sent to the LLM backend with `prompt`, and the
                        reply is typed. Requires `prompt`.
          - `command` — buffered and handed to `command` as a final argument;
                        nothing is typed. Requires `command`.

          The daemon switches on this field, not on the attribute key: a mode
          named anything at all behaves exactly as declared here.
        '';
      };

      prompt = mkOption {
        type = types.nullOr types.lines;
        default = null;
        description = "System/user instruction prepended to the transcript for `behavior = \"llm\"`. Required for that behavior, ignored otherwise.";
      };

      command = mkOption {
        type = types.nullOr (types.listOf types.str);
        default = null;
        example = [ "fluteos-agent-command" ];
        description = ''
          Sink for `behavior = "command"`: argv prefix, spawned detached with the
          transcript appended as the last argument. Required for that behavior,
          ignored otherwise.
        '';
      };

      stt = mkOption {
        type = mkSttType cfg.stt;
        default = { };
        description = "Per-mode STT override. Unset fields inherit `features.fluteos.ptt.stt`.";
      };

      llm = mkOption {
        type = mkLlmType cfg.llm;
        default = { };
        description = "Per-mode LLM override. Unset fields inherit `features.fluteos.ptt.llm`.";
      };
    };
  });

  isEvdevKeyName = k: builtins.match "(KEY|BTN)_[A-Z0-9_]+" k != null;
in
{
  options.features.fluteos.ptt = {
    enable = lib.mkEnableOption "Push-to-talk with transcription and AI processing";

    holdKey = mkOption {
      type = types.str;
      default = "KEY_RIGHTALT";
      example = "KEY_RIGHTCTRL";
      description = ''
        Key held down to record, as an evdev key NAME from
        linux/input-event-codes.h — not a scancode. Resolved to a code at
        startup; an unknown name is a clear startup error rather than a key that
        silently never fires.
      '';
    };

    cycleKeys = mkOption {
      type = types.listOf types.str;
      default = [ "KEY_LEFTSHIFT" "KEY_RIGHTSHIFT" ];
      description = "Keys that advance to the next mode while `holdKey` is held. evdev key NAMES, as above.";
    };

    defaultMode = mkOption {
      type = types.str;
      default = "raw";
      description = "Mode used before the user has ever cycled, and whenever the cached mode no longer exists.";
    };

    modeOrder = mkOption {
      type = types.listOf types.str;
      default = lib.attrNames cfg.modes;
      description = ''
        Cycle order. Every entry must name a mode. Defaults to the attribute
        names of `modes` (alphabetical), so an operator who cares about the
        order states it explicitly.
      '';
    };

    stt = mkOption {
      type = mkSttType sttDefaults;
      default = { };
      description = "Default speech-to-text backend, inherited by every mode that does not override it.";
    };

    llm = mkOption {
      type = mkLlmType llmDefaults;
      default = { };
      description = "Default LLM backend, inherited by every `behavior = \"llm\"` mode that does not override it.";
    };

    modes = mkOption {
      type = types.attrsOf modeType;
      default = {
        raw = {
          name = "RAW";
          icon = "󰍬";
          behavior = "live";
        };
      };
      example = lib.literalExpression ''
        {
          raw.name = "RAW";
          translate = {
            name = "Translate";
            behavior = "llm";
            prompt = "Translate the following text to English. Output only the translation:";
          };
        }
      '';
      description = ''
        The mode table — data, not code. A downstream user adds, removes,
        reorders or re-prompts modes entirely from their own configuration; the
        distribution ships exactly one mode (`raw`: plain dictation, no prompt,
        no language assumption).

        Serialised to JSON and consumed by the daemon, the waybar widget and the
        toggle script, so this attribute set is the single source of truth for
        all three.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions =
      # An llm mode without a prompt would send the bare transcript and type
      # whatever came back; a command mode without a sink would silently drop
      # every phrase. Both are schema errors, so they fail the build.
      (lib.mapAttrsToList (id: m: {
        assertion = m.behavior != "llm" || (m.prompt != null && m.prompt != "");
        message = "features.fluteos.ptt.modes.${id}: behavior = \"llm\" requires a non-empty `prompt`.";
      }) cfg.modes)
      ++ (lib.mapAttrsToList (id: m: {
        assertion = m.behavior != "command" || (m.command != null && m.command != [ ]);
        message = "features.fluteos.ptt.modes.${id}: behavior = \"command\" requires a non-empty `command` sink (e.g. [ \"fluteos-agent-command\" ]).";
      }) cfg.modes)
      ++
      # Mode ids become systemd credential names, jq object keys and a cache
      # file's contents; keep them boring.
      (lib.mapAttrsToList (id: _: {
        assertion = builtins.match "[a-zA-Z0-9_-]+" id != null;
        message = "features.fluteos.ptt.modes.${id}: mode ids must match [a-zA-Z0-9_-]+.";
      }) cfg.modes)
      ++ [
        {
          assertion = cfg.modes != { };
          message = "features.fluteos.ptt.modes is empty; there is nothing to record into.";
        }
        {
          assertion = cfg.modes ? "${cfg.defaultMode}";
          message = "features.fluteos.ptt.defaultMode = \"${cfg.defaultMode}\" is not a declared mode. Declared: ${lib.concatStringsSep ", " (lib.attrNames cfg.modes)}.";
        }
        {
          assertion = lib.all (m: cfg.modes ? "${m}") cfg.modeOrder;
          message = "features.fluteos.ptt.modeOrder references undeclared modes: ${
            lib.concatStringsSep ", " (lib.filter (m: !(cfg.modes ? "${m}")) cfg.modeOrder)
          }. Declared: ${lib.concatStringsSep ", " (lib.attrNames cfg.modes)}.";
        }
        {
          assertion = cfg.modeOrder != [ ];
          message = "features.fluteos.ptt.modeOrder is empty; mode cycling would have nothing to cycle through.";
        }
        {
          assertion = isEvdevKeyName cfg.holdKey;
          message = "features.fluteos.ptt.holdKey = \"${cfg.holdKey}\" is not an evdev key name (expected e.g. KEY_RIGHTALT, not a scancode).";
        }
        {
          assertion = lib.all isEvdevKeyName cfg.cycleKeys;
          message = "features.fluteos.ptt.cycleKeys must be evdev key names (e.g. KEY_LEFTSHIFT), got: ${lib.concatStringsSep ", " cfg.cycleKeys}.";
        }
      ];

    # Deliberately warnings and not assertions: a fresh install that has not
    # been given its credentials yet must still BUILD and activate. The daemon
    # is what refuses to run, at the moment it would need the key.
    warnings =
      (lib.mapAttrsToList
        (id: m: "features.fluteos.ptt.modes.${id}: stt.apiKeyFile is not set — transcription is unavailable in this mode. Set features.fluteos.ptt.stt.apiKeyFile (or modes.${id}.stt.apiKeyFile) to an absolute path on the running machine.")
        (lib.filterAttrs (_: m: m.stt.apiKeyFile == null) cfg.modes))
      ++ (lib.mapAttrsToList
        (id: m: "features.fluteos.ptt.modes.${id}: behavior = \"llm\" but llm.apiKeyFile is not set — plain dictation still works; this mode will report itself unconfigured at runtime.")
        (lib.filterAttrs (_: m: m.behavior == "llm" && m.llm.apiKeyFile == null) cfg.modes));
  };
}
