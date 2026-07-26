# Niri session restore - launch apps with layout for sessions
{ lib, config, ... }:

{
  config = lib.mkIf config.features.base.niri.enable {
    home-manager.users.${config.features.base.system.user.name} = { pkgs, config, lib, ... }:
    let
      # Build JSON config from all sessions (projects + personal)
      sessionsJson = builtins.toJSON (lib.mapAttrs (name: session: {
        displayName = session.displayName;
        apps = map (app: {
          inherit (app) name appId command column focus;
          width = app.width;
          tag = app.tag;
        }) session.apps;
      # `sessions` is declared by features.fluteos.sessions. Base niri must not
      # require that layer, so an absent option means "no sessions to restore"
      # rather than an eval error.
      }) (config.sessions.all or { }));

      configFile = pkgs.writeText "niri-sessions.json" sessionsJson;

      # Main session restore script
      sessionRestore = pkgs.writeShellScriptBin "niri-session-restore" ''
        export JQ="${pkgs.jq}/bin/jq"
        export NIRI="${pkgs.niri}/bin/niri"
        export NOTIFY_SEND="${pkgs.libnotify}/bin/notify-send"
        export CONFIG_FILE="${configFile}"
        bash ${./session-restore.sh} "$@"
      '';

      # List sessions for fuzzy menu
      sessionsList = pkgs.writeShellScriptBin "niri-sessions-list" ''
        export JQ="${pkgs.jq}/bin/jq"
        export CONFIG_FILE="${configFile}"
        bash ${./sessions-list.sh}
      '';
    in
    {
      home.packages = [ sessionRestore sessionsList ];
    };
  };
}
