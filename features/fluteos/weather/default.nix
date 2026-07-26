{ lib, config, ... }:
{
  options.features.fluteos.weather = {
    enable = lib.mkEnableOption "Weather widget for Waybar using Open-Meteo API";
  };

  config = lib.mkIf config.features.fluteos.weather.enable {
    home-manager.users.${config.features.base.system.user.name} = { pkgs, ... }:
    let
      weatherScript = pkgs.writeShellScriptBin "fluteos-weather" ''
        export CURL="${pkgs.curl}/bin/curl"
        export JQ="${pkgs.jq}/bin/jq"
        bash ${./fluteos-weather.sh}
      '';
    in
    {
      home.packages = [ weatherScript ];
    };
  };
}
