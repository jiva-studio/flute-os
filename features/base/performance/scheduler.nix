{ lib, config, pkgs, ... }:
{
  config = lib.mkIf config.features.base.performance.enable {
    services.ananicy = {
      enable = true;
      package = pkgs.ananicy-cpp;
      rulesProvider = pkgs.ananicy-rules-cachyos;
    };
  };
}
