{ lib, config, ... }:
let
  theme = config.features.fluteos.theme.resolved;
  # The same resolved launcher list which-key shows, so the voice router and the
  # menu can never disagree about what is launchable.
  resolvedApps = config.features.fluteos.apps.resolved or [ ];
in
{
  options.features.fluteos.agents = {
    enable = lib.mkEnableOption "Cross-workspace Claude agent status registry";
  };

  config = lib.mkIf config.features.fluteos.agents.enable {
    home-manager.users.${config.features.base.system.user.name} = { pkgs, lib, config, ... }:
    let
      registryDir = "${config.home.homeDirectory}/.cache/fluteos/agents";

      # Which agent voice dictation is currently attached to. Written by
      # fluteos-agent-command, absent when detached.
      targetFile = "${config.home.homeDirectory}/.cache/fluteos/agent-target";

      # Command that prints the workspaces registry path, used to name an agent
      # after the project it runs in. Called lazily (once per session), not on
      # every hook. Optional — without it agents fall back to basename of cwd,
      # so this module stays usable on its own.
      # Fuzzel theming comes from the theme, so every picker in the system —
      # agents, workspaces, tailnets, emoji — looks the same and follows a palette
      # change. These six exports used to be pasted into four modules, which is
      # why changing the theme font changed no popup at all.
      fuzzelTheme = theme.fuzzel.env;

      agentHook = pkgs.writeShellScriptBin "fluteos-agent-hook" ''
        export JQ="${pkgs.jq}/bin/jq"
        export NIRI="${pkgs.niri}/bin/niri"
        export REGISTRY_DIR="${registryDir}"
        export WORKSPACE_REGISTRY_CMD="fluteos-workspaces-registry-path"
        bash ${./fluteos-agent-hook.sh} "$@"
      '';

      agentsWidget = pkgs.writeShellScriptBin "fluteos-agents-widget" ''
        export JQ="${pkgs.jq}/bin/jq"
        export REGISTRY_DIR="${registryDir}"
        bash ${./fluteos-agents-widget.sh}
      '';

      agentSend = pkgs.writeShellScriptBin "fluteos-agent-send" ''
        export JQ="${pkgs.jq}/bin/jq"
        export WEZTERM="${pkgs.wezterm}/bin/wezterm"
        export FUZZEL="${pkgs.fuzzel}/bin/fuzzel"
        export NOTIFY_SEND="${pkgs.libnotify}/bin/notify-send"
        export REGISTRY_DIR="${registryDir}"
        ${fuzzelTheme}
        bash ${./fluteos-agent-send.sh} "$@"
      '';

      agentsPick = pkgs.writeShellScriptBin "fluteos-agents-pick" ''
        export JQ="${pkgs.jq}/bin/jq"
        export NIRI="${pkgs.niri}/bin/niri"
        export FUZZEL="${pkgs.fuzzel}/bin/fuzzel"
        export NOTIFY_SEND="${pkgs.libnotify}/bin/notify-send"
        export REGISTRY_DIR="${registryDir}"
        ${fuzzelTheme}
        bash ${./fluteos-agents-pick.sh}
      '';

      # Launchable applications, read from the same resolved list which-key uses,
      # so a spoken "launch firefox" resolves against a fixed whitelist instead
      # of letting a misheard phrase turn into an arbitrary exec.
      appsRegistry = pkgs.writeText "fluteos-apps.json" (builtins.toJSON
        (map (a: { inherit (a) label; exec = a.action.exec; })
          (lib.filter (a: a ? action && a.action ? exec) resolvedApps)));

      # Voice command router, called by PTT in "command" mode. CLAUDE stays a
      # bare name: claude-code is installed as a user-PATH wrapper, not from
      # nixpkgs, so there is no store path to point at here.
      agentCommand = pkgs.writeShellScriptBin "fluteos-agent-command" ''
        export JQ="${pkgs.jq}/bin/jq"
        export NIRI="${pkgs.niri}/bin/niri"
        export NOTIFY_SEND="${pkgs.libnotify}/bin/notify-send"
        export CLAUDE="claude"
        export FLOCK="${pkgs.util-linux}/bin/flock"
        export REGISTRY_DIR="${registryDir}"
        export TARGET_FILE="${targetFile}"
        export APP_REGISTRY="${appsRegistry}"
        export WORKSPACE_REGISTRY_CMD="fluteos-workspaces-registry-path"
        bash ${./fluteos-agent-command.sh} "$@"
      '';
    in
    {
      # claude-code/default.nix wires the hook in by bare name, resolved from
      # PATH — cross-module store-path plumbing isn't worth it for a script
      # that is always installed alongside it.
      home.packages = [ agentHook agentsWidget agentSend agentsPick agentCommand ];
    };
  };
}
