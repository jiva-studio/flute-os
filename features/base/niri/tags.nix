# Niri window tags - assign tags to windows and quickly switch between them
{ lib, config, ... }:

{
  config = lib.mkIf config.features.base.niri.enable {
    home-manager.users.${config.features.base.system.user.name} = { pkgs, ... }:
    let
      niri-tags = pkgs.writeShellScriptBin "niri-tags" ''
        export JQ="${pkgs.jq}/bin/jq"
        export NIRI="${pkgs.niri}/bin/niri"
        export NOTIFY_SEND="${pkgs.libnotify}/bin/notify-send"
        bash ${./tags.sh} "$@"
      '';
    in
    {
      home.packages = [ niri-tags ];
    };
  };
}
