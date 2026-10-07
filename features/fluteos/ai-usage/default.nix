{ lib, config, ... }:
let
  cfg = config.features.fluteos.ai-usage;

  # Declared by features/fluteos/claude-code, which is imported next to this one
  # in the FluteOS module set. `or false` keeps this module usable on its own,
  # for a consumer who imports features individually.
  claudeCodeEnabled = config.features.fluteos.claude-code.enable or false;

  # Backends that read a local source — a token file, a session transcript, a
  # loopback RPC — and so have no API key to configure.
  keylessBackends = [ "claude-oauth" "codex" "antigravity" ];

  # One entry on the bar. `backend` names the code that knows how to ask a given
  # service what is left; everything else is presentation and the path of the
  # credential.
  providerType = lib.types.submodule ({ name, ... }: {
    options = {
      backend = lib.mkOption {
        type = lib.types.enum [ "claude-oauth" "openrouter" "zai" "codex" "antigravity" ];
        description = ''
          Which reporter to use:

          - `claude-oauth` — an Anthropic subscription, read through the OAuth
            token Claude Code's login writes. Needs no key file.
          - `openrouter` — the OpenRouter credit balance.
          - `zai` — a z.ai GLM coding plan: its rolling 5-hour and weekly quotas.
          - `codex` — an OpenAI Codex plan. Codex has no "what is left" endpoint;
            the numbers ride along on every turn and are recorded in the session
            transcript, so this reads the newest one back from
            `~/.codex/sessions`. Needs no key file, and costs no API call.
          - `antigravity` — a Google Antigravity plan, read from the language
            server Antigravity runs on loopback. Needs no key file, but reports
            "not running" while Antigravity is closed.
        '';
      };
      name = lib.mkOption {
        type = lib.types.str;
        default = name;
        description = "Full name, shown as the tooltip's heading for this provider.";
      };
      label = lib.mkOption {
        type = lib.types.str;
        default = lib.toUpper (builtins.substring 0 3 name);
        example = "CLD";
        description = ''
          The short tag this provider wears on the bar, ahead of its number.
          Three letters by convention — every provider is on the bar at once, so
          this is what tells them apart, and anything longer stops being
          readable at a glance. Defaults to the first three letters of the
          attribute key.
        '';
      };
      order = lib.mkOption {
        type = lib.types.int;
        default = 50;
        description = "Position on the bar, left to right; ties break on name.";
      };
      process = lib.mkOption {
        type = lib.types.str;
        default = "antigravity";
        description = ''
          For the `antigravity` backend: the process name whose loopback ports
          are searched for the language server. Ignored by every other backend.
        '';
      };
      apiKeyFile = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "/home/you/fluteos-personal/secrets/openrouter.key";
        description = ''
          Absolute path, on the running machine, of a file holding this
          provider's API key. Null is correct for the keyless backends
          (${lib.concatStringsSep ", " keylessBackends}) and an error for the
          others, which then render "?" with a tooltip saying so.

          A string and not a `types.path`: anything Nix addresses as a path is
          copied into the world-readable /nix/store. Only the path is written to
          the store — the reporter opens the file at runtime and passes the key
          to curl on stdin, so it never appears in the process table either.
        '';
      };
    };
  });

  # The legacy option feeds the provider that used to be the widget's other
  # half, so an existing configuration keeps working having set only that.
  providers = lib.mapAttrs
    (_: p: p // lib.optionalAttrs (p.apiKeyFile == null && p.backend == "openrouter") {
      apiKeyFile = cfg.openrouterApiKeyFile;
    })
    cfg.providers;

  needsKey = lib.filterAttrs
    (_: p: !(lib.elem p.backend keylessBackends) && p.apiKeyFile == null)
    providers;
in
{
  options.features.fluteos.ai-usage = {
    enable = lib.mkEnableOption "AI plan usage widget for Waybar";

    providers = lib.mkOption {
      type = lib.types.attrsOf providerType;
      default = {
        claude = { backend = "claude-oauth"; name = "Claude"; label = "CLD"; order = 10; };
        openrouter = { backend = "openrouter"; name = "OpenRouter"; label = "ORT"; order = 20; };
      };
      example = lib.literalExpression ''
        {
          claude      = { backend = "claude-oauth"; name = "Claude";      label = "CLD"; order = 10; };
          antigravity = { backend = "antigravity";  name = "Antigravity"; label = "ANT"; order = 20; };
          codex       = { backend = "codex";        name = "Codex";       label = "COD"; order = 30; };
          glm = {
            backend = "zai";
            name = "GLM coding plan";
            label = "GLM";
            order = 40;
            apiKeyFile = "/home/you/secrets/zai.key";
          };
        }
      '';
      description = ''
        Every provider the bar reports on. All of them are shown at once, each
        behind its `label`, ordered by `order`.

        Setting this REPLACES the default pair rather than adding to it, so list
        every provider you want — including `claude`.

        Which services a machine has accounts on is not something a distribution
        can know, so the product ships the two it can configure itself and no
        opinion about the rest.
      '';
    };

    openrouterApiKeyFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "/home/you/fluteos-personal/secrets/openrouter-api-key";
      description = ''
        Key file for the default `openrouter` provider — a shorthand kept from
        when the widget was Claude-and-OpenRouter and nothing else. Equivalent
        to setting that provider's `apiKeyFile`, and ignored once a provider
        names its own.

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
      lib.mapAttrsToList (id: p: ''
        features.fluteos.ai-usage provider "${id}" (backend ${p.backend}) has no
        apiKeyFile — it will render "?" with "no API key configured". Set its
        apiKeyFile to the absolute path of a file holding the key (a string path
        read at runtime; never a Nix path, which would copy the key into
        /nix/store).
      '') needsKey
      ++ lib.optional
        (!claudeCodeEnabled && lib.any (p: p.backend == "claude-oauth") (lib.attrValues providers)) ''
        features.fluteos.ai-usage has a claude-oauth provider but
        features.fluteos.claude-code is off — that provider reads the OAuth token
        from ~/.claude/.credentials.json, which only exists once Claude Code has
        been installed and logged in. The widget still works (it reports "?" for
        that provider, and the others are independent), so this is not fatal.
      '';

    home-manager.users.${config.features.base.system.user.name} = { pkgs, ... }:
    let
      aiUsagePkg = pkgs.python3Packages.buildPythonApplication {
        pname = "fluteos-ai-usage";
        version = "2.0.0";
        src = ./.;
        format = "setuptools";
        doCheck = false;
      };

      # Paths of the keys, never their contents: this file is world-readable in
      # /nix/store. The reporter opens them at runtime.
      providersFile = pkgs.writeText "ai-usage-providers.json" (builtins.toJSON providers);

      aiUsageWidget = pkgs.writeShellScriptBin "fluteos-ai-usage" ''
        export PATH="${pkgs.curl}/bin:$PATH"
        export AI_USAGE_BIN="${aiUsagePkg}/bin/ai-usage"
        export PROVIDERS_FILE="${providersFile}"
        export JQ="${pkgs.jq}/bin/jq"
        export CACHE_DIR="$HOME/.cache/fluteos/ai-usage"
        # The APIs are polled far less often than the bar redraws; see the
        # script. All providers are fetched in one parallel run.
        export USAGE_TTL=300
        # Agent statuses are merged into this module. Bare name, resolved from
        # PATH: the agents feature is optional and owns its own wrapper, so no
        # cross-module store plumbing here.
        export AGENTS_WIDGET="fluteos-agents-widget"
        # Inherited by that wrapper, which needs niri to tell which agent window
        # is focused. Harmless when the agents feature is disabled.
        export NIRI="${pkgs.niri}/bin/niri"
        bash ${./fluteos-ai-usage.sh} "$@"
      '';
    in
    {
      home.packages = [ aiUsageWidget ];
    };
  };
}
