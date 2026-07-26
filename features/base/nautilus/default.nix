{ lib, config, ... }:
{
  options.features.base.nautilus = {
    enable = lib.mkEnableOption "Nautilus (GNOME Files) GUI file manager";
  };

  config = lib.mkIf config.features.base.nautilus.enable {
    # GVFS backends: trash, recent, network shares (SMB/SFTP), MTP, etc.
    # Without it Nautilus loses trash and remote mounts.
    services.gvfs.enable = true;

    home-manager.users.${config.features.base.system.user.name} = { pkgs, ... }: {
      home.packages = [ pkgs.nautilus ];
    };
  };
}
