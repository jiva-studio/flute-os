# Niri session environment setup - systemd target and env variable import
{ lib, config, ... }:

{
  config = lib.mkIf config.features.base.niri.enable {
    home-manager.users.${config.features.base.system.user.name} = { pkgs, ... }: {
      systemd.user.services.niri-session-env = {
        Unit.Description = "Import Niri session environment variables";
        Service = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = pkgs.writeShellScript "niri-session-env" ''
            export SYSTEMCTL="${pkgs.systemd}/bin/systemctl"
            export DBUS_UPDATE="${pkgs.dbus}/bin/dbus-update-activation-environment"
            bash ${./session-env.sh}
          '';
        };
      };

      systemd.user.targets.niri-session = {
        Unit = {
          Description = "Niri Wayland session is ready";
          BindsTo = [ "graphical-session.target" ];
          After = [ "graphical-session.target" ];
        };
      };
    };
  };
}
