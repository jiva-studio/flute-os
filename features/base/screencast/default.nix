{ lib, config, ... }:
{
  options.features.base.screencast = {
    enable = lib.mkEnableOption "Screen recording";
  };

  config = lib.mkIf config.features.base.screencast.enable {
    home-manager.users.${config.features.base.system.user.name} = { pkgs, ... }: let
      screencastRecord = pkgs.writeShellScriptBin "screencast-record" ''
        bash ${./screencast-record.sh} "$@"
      '';
    in {
      home.packages = [ screencastRecord pkgs.wf-recorder pkgs.slurp ];
      xdg.desktopEntries.screencast-record = {
        name = "Screencast"; exec = "screencast-record screen";
        icon = "video-x-generic"; comment = "Record screen or region";
        categories = [ "Utility" ];
      };
    };
  };
}
