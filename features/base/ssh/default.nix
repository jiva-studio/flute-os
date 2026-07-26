{ lib, config, ... }:
{
  options.features.base.ssh = {
    enable = lib.mkEnableOption "SSH server";
  };

  config = lib.mkIf config.features.base.ssh.enable {
    services.openssh = {
      enable = true;
      settings = {
        PasswordAuthentication = false;
        PermitRootLogin = "no";
      };
    };
  };
}
