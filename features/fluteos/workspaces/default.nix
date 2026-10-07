{ lib, config, ... }:
let
  theme = config.features.fluteos.theme.resolved;
  # The home-manager submodule below shadows `config` with its own, so the
  # NixOS-level options have to be captured out here.
  nixosCfg = config;

  # One entry of the agent catalogue: what the picker offers on the agent
  # keybinding. An agent is a command plus the environment it needs, so the same
  # binary can appear several times under different backends — Claude on the
  # subscription, Claude against an Anthropic-compatible gateway, opencode on
  # whichever provider — without this module knowing any of them by name.
  profileType = lib.types.submodule ({ name, ... }: {
    options = {
      name = lib.mkOption {
        type = lib.types.str;
        default = name;
        description = "Display name in the agent picker. Defaults to the attribute key.";
      };
      icon = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Nerd Font glyph shown before the name.";
      };
      command = lib.mkOption {
        type = lib.types.str;
        example = "claude --model opus";
        description = ''
          The command line to run, as fish sees it: a binary and optionally its
          arguments. Run under `direnv exec <agentDir>`, so the project's own
          environment still applies.
        '';
      };
      order = lib.mkOption {
        type = lib.types.int;
        default = 50;
        description = "Sort key in the picker; ties break on display name.";
      };
      env = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = { };
        example = { ANTHROPIC_BASE_URL = "https://example.invalid/anthropic"; };
        description = ''
          Environment exported before the agent starts. For values that are not
          secret — endpoints, timeouts, a per-profile CLAUDE_CONFIG_DIR.
        '';
      };
      envFiles = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = { };
        example = { ANTHROPIC_AUTH_TOKEN = "/home/you/secrets/zai.key"; };
        description = ''
          Environment whose value is the contents of a file, read at launch and
          stripped of surrounding whitespace. This is where API keys go: only the
          path reaches /nix/store, never the key. A path that cannot be read is
          skipped, and the agent starts without that variable — which surfaces as
          the provider's own auth error rather than an eval failure here.
        '';
      };
    };
  });
in
{
  options.features.fluteos.workspaces = {
    enable = lib.mkEnableOption "Unified workspace open / browser routing";

    agentProfiles = lib.mkOption {
      type = lib.types.attrsOf profileType;
      default = {
        claude = { name = "Claude"; icon = "󰚩"; command = "claude"; order = 10; };
        opencode = { name = "OpenCode"; icon = "󰭹"; command = "opencode"; order = 20; };
      };
      example = lib.literalExpression ''
        {
          claude.command = "claude";
          claude-glm = {
            name = "Claude + GLM";
            command = "claude";
            env.ANTHROPIC_BASE_URL = "https://api.z.ai/api/anthropic";
            envFiles.ANTHROPIC_AUTH_TOKEN = "/home/you/secrets/zai.key";
          };
        }
      '';
      description = ''
        The agent catalogue the picker offers. Setting this REPLACES the default
        pair rather than adding to it, so list every profile you want — including
        plain `claude`.

        Which backends are worth having is taste and it dates fast (a gateway
        renames a model, a subscription ends), so the product ships only the two
        agents it knows how to install and no opinion about anyone's providers.

        A profile chosen here overrides the workspace's own `agentCommand` for
        that launch; picking nothing falls back to it, so the voice router and
        `fluteos-agent-launch --workspace` keep working unchanged.
      '';
    };
  };

  config = lib.mkIf config.features.fluteos.workspaces.enable {
    home-manager.users.${config.features.base.system.user.name} = { pkgs, config, lib, ... }:
    let
      # Same reason as the `or { }` below: without features.fluteos.projects this
      # attribute path does not exist. "Default" is the option's own default.
      defaultProfile = config.features.fluteos.projects.defaultBrowserProfile or "Default";

      # Build one workspace entry per (effective) project that opted into workspace=true.
      mkWorkspace = pId: eff: {
        id = "${eff.group.name}:${eff.name}";
        group = eff.group.name;
        project = eff.name;
        # "<Group> : <Project>", but collapse the redundant duplicate when a
        # group’s main project shares its name (e.g. acme:acme → "Acme",
        # acme:acme → "Acme"). Sub-projects keep both
        # halves ("Acme : Widgets").
        displayName =
          if eff.group.displayName == eff.displayName
          then eff.group.displayName
          else "${eff.group.displayName} : ${eff.displayName}";
        cwd = eff.dir;                   # project root (terminal opens here)
        sourceDir = eff.sourceDir;
        agentDir = eff.agentDir;
        docsDir = eff.docsDir;
        resourcesDir = eff.resourcesDir;
        browserProfile = eff.browserProfile;
        sessionApps = eff.sessionApps;
        agentCommand = eff.agentCommand;
        icon = eff.icon;
        docsPort = eff.docsPort;
        # Tailscale network bound to this project (null if none). Read at runtime
        # by the tailnet-switcher daemon to auto-switch on workspace focus.
        tailnet = eff.tailnet;
      };

      # `or { }` because features.fluteos.projects is optional: with it off, its
      # home-manager half is not imported at all and `config.features` does not
      # exist here — enabling workspaces without projects used to fail evaluation
      # outright, with an "attribute 'features' missing" that named neither
      # feature. No projects simply means an empty registry.
      workspaceEntries = lib.mapAttrsToList mkWorkspace
        (lib.filterAttrs (_: eff: eff.workspace)
          (config.features.fluteos.projects.effective or { }));

      # Keyed by id for O(1) lookup
      registryAttrs = lib.listToAttrs
        (map (w: { name = w.id; value = w; }) workspaceEntries);

      registryFile = pkgs.writeText "workspaces.json" (builtins.toJSON registryAttrs);

      # The agent catalogue, as the picker and the launcher read it. Keyed by
      # profile id; `command` is a fish command line, `env` and `envFiles` are
      # applied before it runs (the latter by reading the file at launch, so no
      # key is ever written into the store).
      profilesFile = pkgs.writeText "agent-profiles.json"
        (builtins.toJSON nixosCfg.features.fluteos.workspaces.agentProfiles);

      workspaceOpen = pkgs.writeShellScriptBin "fluteos-workspace-open" ''
        export JQ="${pkgs.jq}/bin/jq"
        export NIRI="${pkgs.niri}/bin/niri"
        export WEZTERM="${pkgs.wezterm}/bin/wezterm"
        export NOTIFY_SEND="${pkgs.libnotify}/bin/notify-send"
        export REGISTRY="${registryFile}"
        bash ${./fluteos-workspace-open.sh} "$@"
      '';

      workspacesList = pkgs.writeShellScriptBin "fluteos-workspaces-list" ''
        export JQ="${pkgs.jq}/bin/jq"
        export REGISTRY="${registryFile}"
        bash ${./fluteos-workspaces-list.sh}
      '';

      workspaceTerminal = pkgs.writeShellScriptBin "fluteos-workspace-terminal" ''
        export JQ="${pkgs.jq}/bin/jq"
        export NIRI="${pkgs.niri}/bin/niri"
        export WEZTERM="${pkgs.wezterm}/bin/wezterm"
        export REGISTRY="${registryFile}"
        bash ${./fluteos-workspace-terminal.sh} "$@"
      '';

      workspaceBrowser = pkgs.writeShellScriptBin "fluteos-workspace-browser" ''
        export DEFAULT_PROFILE="${defaultProfile}"
        export FIREFOX="${pkgs.firefox}/bin/firefox"
        export JQ="${pkgs.jq}/bin/jq"
        export NIRI="${pkgs.niri}/bin/niri"
        export REGISTRY="${registryFile}"
        bash ${./fluteos-workspace-browser.sh} "$@"
      '';

      agentCheck = pkgs.writeShellScriptBin "fluteos-agent-check" ''
        export JQ="${pkgs.jq}/bin/jq"
        export NIRI="${pkgs.niri}/bin/niri"
        export REGISTRY="${registryFile}"
        bash ${./fluteos-agent-check.sh}
      '';

      agentLaunch = pkgs.writeShellScriptBin "fluteos-agent-launch" ''
        export JQ="${pkgs.jq}/bin/jq"
        export NIRI="${pkgs.niri}/bin/niri"
        export WEZTERM="${pkgs.wezterm}/bin/wezterm"
        export REGISTRY="${registryFile}"
        export PROFILES="${profilesFile}"
        bash ${./fluteos-agent-launch.sh} "$@"
      '';

      workspaceDisplayName = pkgs.writeShellScriptBin "fluteos-workspace-display-name" ''
        export JQ="${pkgs.jq}/bin/jq"
        export NIRI="${pkgs.niri}/bin/niri"
        export REGISTRY="${registryFile}"
        bash ${./fluteos-workspace-display-name.sh}
      '';

      agentPrompt = pkgs.writeShellScriptBin "fluteos-agent-prompt" ''
        export FUZZEL="${pkgs.fuzzel}/bin/fuzzel"
        export JQ="${pkgs.jq}/bin/jq"
        export PROFILES="${profilesFile}"
        ${theme.fuzzel.env}bash ${./fluteos-agent-prompt.sh}
      '';

      # Helper: print path to the registry file. Useful for migrations and debugging.
      workspacesRegistryPath = pkgs.writeShellScriptBin "fluteos-workspaces-registry-path" ''
        echo "${registryFile}"
      '';
    in
    {
      # The registry path, for the long-running services that read it. They
      # resolve their helper through PATH once, at start, so a registry that
      # changed under them stays invisible until they restart: a project added
      # today would not reach the bar or the menus until the next login. Units
      # that consume this list it in Unit.X-Restart-Triggers, which makes their
      # unit file change with the registry and lets sd-switch restart exactly
      # them on activation.
      #
      # Declared through `imports` because the rest of this module is plain
      # config: mixing an `options` key with bare `home.packages` in one attrset
      # is what the module system refuses.
      imports = [
        ({ lib, ... }: {
          options.features.fluteos.workspaces.registryPath = lib.mkOption {
            type = lib.types.str;
            readOnly = true;
            description = "Store path of the generated workspaces.json registry.";
          };
        })
      ];
      features.fluteos.workspaces.registryPath = "${registryFile}";

      home.packages = [
        workspaceOpen
        workspacesList
        workspaceTerminal
        workspaceBrowser
        agentCheck
        agentLaunch
        workspaceDisplayName
        agentPrompt
        workspacesRegistryPath
      ];

      xdg.desktopEntries.fluteos-workspace-browser = {
        name = "Workspace-aware Browser";
        genericName = "Web Browser";
        exec = "fluteos-workspace-browser %U";
        icon = "firefox";
        terminal = false;
        type = "Application";
        mimeType = [
          "text/html"
          "x-scheme-handler/http"
          "x-scheme-handler/https"
          "x-scheme-handler/about"
          "x-scheme-handler/unknown"
        ];
      };

      xdg.mimeApps.defaultApplications = {
        "text/html" = "fluteos-workspace-browser.desktop";
        "x-scheme-handler/http" = "fluteos-workspace-browser.desktop";
        "x-scheme-handler/https" = "fluteos-workspace-browser.desktop";
      };
    };
  };
}
