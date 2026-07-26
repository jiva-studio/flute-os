{ lib, config, ... }:
let
  cfg = config.features.fluteos.claude-usage;

  # Declared by features/fluteos/claude-code, which is imported next to this one
  # in the FluteOS module set. `or false` keeps this module usable on its own,
  # for a consumer who imports features individually.
  claudeCodeEnabled = config.features.fluteos.claude-code.enable or false;
in
{
  options.features.fluteos.claude-usage = {
    enable = lib.mkEnableOption "AI usage widget for Waybar (Claude + OpenRouter)";

    openrouterApiKeyFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "/home/you/fluteos-personal/secrets/openrouter-api-key";
      description = ''
        Absolute path, on the running machine, of a file containing the
        OpenRouter API key used to read the credit balance. Null (the default)
        means the widget's OpenRouter half has nothing to query and says so;
        Claude mode is unaffected.

        A string and not a `types.path`: anything Nix addresses as a path is
        copied into the world-readable /nix/store, and `builtins.readFile` would
        put the key itself into a store script. Only the path is written to the
        store — the widget reads the file at runtime, and passes the key to curl
        via stdin so it never appears in the process table either.

        This module deliberately owns its own option instead of borrowing
        features/fluteos/opencode's key: a feature must not reach into another
        feature's directory for a secret.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # Warnings, not assertions: a fresh install has no keys at all and must
    # still build. Every missing piece degrades to a visible "?" in the bar.
    warnings =
      lib.optional (cfg.openrouterApiKeyFile == null) ''
        features.fluteos.claude-usage is enabled but openrouterApiKeyFile is null
        — the widget's OpenRouter mode will render "?" with "no API key
        configured". Set features.fluteos.claude-usage.openrouterApiKeyFile to the
        absolute path of a file holding the key (a string path read at runtime;
        never a Nix path, which would copy the key into /nix/store).
      ''
      ++ lib.optional (!claudeCodeEnabled) ''
        features.fluteos.claude-usage is enabled without
        features.fluteos.claude-code — Claude mode reads the OAuth token from
        ~/.claude/.credentials.json, which only exists once Claude Code has been
        installed and logged in. The widget still works (it reports "?" for
        Claude, and OpenRouter mode is independent), so this is not fatal.
      '';

    home-manager.users.${config.features.base.system.user.name} = { pkgs, ... }:
    let
      claudeUsagePkg = pkgs.python3Packages.buildPythonApplication {
        pname = "fluteos-claude-usage";
        version = "1.0.0";
        src = ./.;
        format = "setuptools";
        doCheck = false;
      };

      claudeUsageWidget = pkgs.writeShellScriptBin "fluteos-claude-usage" ''
        export PATH="${pkgs.curl}/bin:$PATH"
        export CLAUDE_USAGE_BIN="${claudeUsagePkg}/bin/claude-usage"
        # PATH of the key, never its contents: this script lives in the
        # world-readable /nix/store. The reporter reads the file at runtime.
        export OPENROUTER_API_KEY_FILE="${lib.optionalString (cfg.openrouterApiKeyFile != null) cfg.openrouterApiKeyFile}"
        export JQ="${pkgs.jq}/bin/jq"
        export MODE_FILE="$HOME/.cache/ai-usage/mode"
        export CACHE_DIR="$HOME/.cache/fluteos/claude-usage"
        # The API is polled far less often than the bar redraws; see the script.
        export USAGE_TTL=300
        # Agent statuses are merged into this module. Bare name, resolved from
        # PATH: the agents feature is optional and owns its own wrapper, so no
        # cross-module store plumbing here.
        export AGENTS_WIDGET="fluteos-agents-widget"
        # Inherited by that wrapper, which needs niri to tell which agent window
        # is focused. Harmless when the agents feature is disabled.
        export NIRI="${pkgs.niri}/bin/niri"
        bash ${./fluteos-claude-usage.sh} "$@"
      '';

      aiUsageToggle = pkgs.writeShellScriptBin "fluteos-ai-usage-toggle" ''
        bash ${./fluteos-ai-usage-toggle.sh}
      '';
    in
    {
      home.packages = [ claudeUsageWidget aiUsageToggle ];
    };
  };
}
