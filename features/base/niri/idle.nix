# Niri idle management - screen timeout, lock, suspend
{ lib, config, ... }:

{
  config = lib.mkIf config.features.base.niri.enable {
    home-manager.users.${config.features.base.system.user.name} = { pkgs, lib, ... }: {
      # Override WantedBy to use niri-session.target instead of graphical-session.target
      systemd.user.services.swayidle = {
        Install.WantedBy = lib.mkForce [ "niri-session.target" ];
      };

      services.swayidle = {
        enable = true;
        timeouts = [
          # Turn off screen after 5 minutes (300 sec)
          {
            timeout = 300;
            command = "${pkgs.niri}/bin/niri msg action power-off-monitors";
            resumeCommand = "${pkgs.niri}/bin/niri msg action power-on-monitors";
          }
          # Lock screen after 10 minutes (600 sec)
          {
            timeout = 600;
            command = "${pkgs.swaylock-effects}/bin/swaylock -f";
          }
          # Suspend after 15 minutes (900 sec)
          {
            timeout = 900;
            command = "${pkgs.systemd}/bin/systemctl suspend";
          }
        ];
        events = {
          # Before sleep - lock screen
          before-sleep = "${pkgs.swaylock-effects}/bin/swaylock -f";
          # On lock event - turn off monitors
          lock = "${pkgs.niri}/bin/niri msg action power-off-monitors";
        };
      };
    };
  };
}
