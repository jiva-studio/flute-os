{ lib, config, ... }:
let
  cfg = config.features.fluteos.opencode;

  # One entry of a provider's model catalogue. Freeform, so any extra key
  # opencode understands (limit, tool_call, reasoning, …) passes through to JSON
  # without this module having to track opencode's schema.
  modelType = lib.types.submodule ({ name, ... }: {
    freeformType = lib.types.anything;
    options.name = lib.mkOption {
      type = lib.types.str;
      default = name;
      description = "Display name in the model picker. Defaults to the attribute key (the model id).";
    };
  });
in
{
  options.features.fluteos.opencode = {
    enable = lib.mkEnableOption "OpenCode terminal AI agent";

    openrouterApiKeyFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "/home/you/fluteos-personal/secrets/openrouter-api-key";
      description = ''
        Absolute path, on the running machine, of a file containing the
        OpenRouter API key. Null (the default) leaves the OpenRouter provider
        out of the generated config entirely: opencode is still installed, and
        any provider it can configure on its own keeps working.

        A string and not a `types.path`: anything Nix addresses as a path is
        copied into the world-readable /nix/store, and `builtins.readFile` would
        additionally bake the key into both the generated config file and the
        derivation hash. Only this path is written to the store; it is emitted as
        an opencode `{file:…}` substitution, which opencode resolves when it
        starts. A `~/`-prefixed path is expanded by opencode itself.
      '';
    };

    defaultModel = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "openrouter/qwen/qwen3-coder-next";
      description = ''
        opencode `model` — the default model for a session, as
        "<provider>/<model-id>". Null (the default) omits the key, leaving the
        choice to opencode (last used, or its picker on first run).

        Which model is best is taste and it dates fast, so the product ships no
        opinion; set it from your own configuration.
      '';
    };

    smallModel = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "openrouter/deepseek/deepseek-chat-v3.1";
      description = ''
        opencode `small_model` — the cheap model used for titles, summaries and
        other side tasks. Null omits the key (opencode falls back to `model`).
      '';
    };

    openrouterModels = lib.mkOption {
      type = lib.types.attrsOf modelType;
      default = { };
      example = lib.literalExpression ''
        {
          "qwen/qwen3-coder-next".name = "Qwen 3 Coder Next";
          "deepseek/deepseek-chat-v3.1".name = "DeepSeek V3.1";
        }
      '';
      description = ''
        Extra OpenRouter models to list in the picker, keyed by OpenRouter model
        id. Empty (the default) means only what opencode already knows about
        OpenRouter from its own models.dev catalogue — a neutral default that
        never goes stale, because a hardcoded catalogue rots the moment a model
        is renamed or retired.

        Ignored when `openrouterApiKeyFile` is null (no provider is emitted).
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # A fresh install has no keys and must still build, so this is a warning and
    # not an assertion. The module degrades: opencode is installed, only the
    # OpenRouter provider is missing.
    warnings =
      lib.optional (cfg.openrouterApiKeyFile == null) ''
        features.fluteos.opencode is enabled but openrouterApiKeyFile is null —
        the OpenRouter provider is not configured, so opencode starts without it.
        Set features.fluteos.opencode.openrouterApiKeyFile to the absolute path of
        a file holding the key (a string path, read by opencode at launch; never a
        Nix path, which would copy the key into /nix/store).
      ''
      ++ lib.optional (cfg.openrouterApiKeyFile == null && cfg.openrouterModels != { }) ''
        features.fluteos.opencode.openrouterModels is set but
        openrouterApiKeyFile is null — the catalogue is ignored because no
        OpenRouter provider is emitted.
      ''
      ++ lib.optional (cfg.openrouterApiKeyFile == null
                       && (cfg.defaultModel != null && lib.hasPrefix "openrouter/" cfg.defaultModel)) ''
        features.fluteos.opencode.defaultModel points at the openrouter provider
        ("${cfg.defaultModel}") but openrouterApiKeyFile is null — opencode will
        not be able to resolve that model.
      '';

    # `theme` is taken so the TUI theme is generated from the system palette
    # rather than retyping it — 26 of its hex literals were the palette by hand.
    home-manager.users.${config.features.base.system.user.name} = { pkgs, theme, ... }:
    let
      # The key's PATH goes into the store; its CONTENTS never do. opencode
      # resolves {file:…} substitutions at launch, and a missing/unreadable file
      # surfaces there as a provider error instead of an eval failure here.
      openrouterProvider = {
        npm = "@ai-sdk/openai-compatible";
        name = "OpenRouter";
        options = {
          apiKey = "{file:${cfg.openrouterApiKeyFile}}";
          baseURL = "https://openrouter.ai/api/v1";
        };
      } // lib.optionalAttrs (cfg.openrouterModels != { }) {
        models = cfg.openrouterModels;
      };

      opencodeConfig = {
        "$schema" = "https://opencode.ai/config.json";
        # Same {file:…} runtime substitution as the provider key above. Missing
        # file → opencode logs a warning and the perplexity MCP simply does not
        # initialise.
        mcp = {
          perplexity = {
            type = "local";
            command = [ "npx" "-y" "@perplexity-ai/mcp-server" ];
            environment = {
              PERPLEXITY_API_KEY = "{file:~/.config/fluteos/secrets/perplexity-api-key}";
            };
          };
        };
      }
      // lib.optionalAttrs (cfg.openrouterApiKeyFile != null) {
        provider.openrouter = openrouterProvider;
      }
      // lib.optionalAttrs (cfg.defaultModel != null) { model = cfg.defaultModel; }
      // lib.optionalAttrs (cfg.smallModel != null) { small_model = cfg.smallModel; };

      tuiConfig = {
        "$schema" = "https://opencode.ai/tui.json";
        theme = "transparent";
      };

      # The theme file, generated from the palette. See ./transparent-theme.nix.
      transparentTheme = import ./transparent-theme.nix {
        inherit lib;
        palette = theme.palette;
      };
    in
    {
      home.packages = [
        pkgs.opencode
        pkgs.nodejs  # Required for MCP servers using npx
      ];

      home.file.".config/opencode/opencode.json".text = builtins.toJSON opencodeConfig;
      home.file.".config/opencode/tui.json".text = builtins.toJSON tuiConfig;
      home.file.".config/opencode/themes/transparent.json".text = builtins.toJSON transparentTheme;
      home.file.".config/opencode/plugins/notify.js".source = ./notify-plugin.js;
    };
  };
}
