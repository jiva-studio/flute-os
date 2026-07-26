{ lib, config, ... }:

let
  cfg = config.features.base.wifi;
in
{
  options.features.base.wifi = {
    enable = lib.mkEnableOption "WiFi support";
    locations = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "WiFi locations to enable (e.g., home, mobile)";
    };
    profiles = lib.mkOption {
      type = lib.types.attrsOf (lib.types.attrsOf lib.types.anything);
      default = {};
      description = ''
        WiFi profiles grouped by location key (e.g. "home", "mobile").
        Each location holds an attrset of NetworkManager profile definitions.
        Real PSKs/SSIDs are populated by personal/wifi.nix; the default {}
        is intentional so that the distributable repo contains no credentials.
      '';
    };
  };

  config = lib.mkIf cfg.enable (let
    enabledLocations = if cfg.locations == [] then lib.attrNames cfg.profiles else cfg.locations;
    enabledProfiles = lib.foldl' lib.mergeAttrs {}
      (map (loc: cfg.profiles.${loc} or {}) enabledLocations);
  in {
    networking.networkmanager.ensureProfiles.profiles = enabledProfiles;
  });
}
