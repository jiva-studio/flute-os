{ lib, config, personalRoot ? null, ... }:
let
  personalSessionsPath = if personalRoot != null then personalRoot + "/sessions" else null;
in
{
  options.features.fluteos.sessions = {
    enable = lib.mkEnableOption "Session management (personal and company sessions)";
  };

  config = lib.mkIf config.features.fluteos.sessions.enable {
    home-manager.users.${config.features.base.system.user.name} = { ... }: {
      imports = [ ./options.nix ./aggregator.nix ]
        ++ lib.optional (personalSessionsPath != null && builtins.pathExists personalSessionsPath)
             personalSessionsPath;
    };
  };
}
