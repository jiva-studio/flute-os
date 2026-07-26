{ lib, config, ... }:
let theme = config.features.fluteos.theme.resolved; in
{
  options.features.fluteos.workspaces = {
    enable = lib.mkEnableOption "Unified workspace open / browser routing";
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
        ${theme.fuzzel.env}bash ${./fluteos-agent-prompt.sh}
      '';

      # Helper: print path to the registry file. Useful for migrations and debugging.
      workspacesRegistryPath = pkgs.writeShellScriptBin "fluteos-workspaces-registry-path" ''
        echo "${registryFile}"
      '';
    in
    {
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
