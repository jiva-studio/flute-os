# Power management menu
{ lib, hostConfig }:

{
  type = "key";
  items = [
    { key = "s"; label = "Suspend"; action = { exec = [ "systemctl" "suspend" ]; }; }
    { key = "h"; label = "Hibernate"; action = { exec = [ "systemctl" "hibernate" ]; }; }
    { key = "r"; label = "Reboot"; action = { exec = [ "systemctl" "reboot" ]; }; }
    { key = "q"; label = "Shutdown"; action = { exec = [ "systemctl" "poweroff" ]; }; }
    { key = "1"; label = "Performance {status}";
      statusCmd = [ "sh" "-c" "fluteos-power-control is-profile performance && echo '[✓]' || echo ''" ];
      action = { exec = [ "fluteos-power-control" "profile-performance" ]; }; }
    { key = "2"; label = "Balanced {status}";
      statusCmd = [ "sh" "-c" "fluteos-power-control is-profile balanced && echo '[✓]' || echo ''" ];
      action = { exec = [ "fluteos-power-control" "profile-balanced" ]; }; }
    { key = "3"; label = "Power Saver {status}";
      statusCmd = [ "sh" "-c" "fluteos-power-control is-profile power-saver && echo '[✓]' || echo ''" ];
      action = { exec = [ "fluteos-power-control" "profile-power-saver" ]; }; }
    { key = "c"; label = "Caffeine {status}";
      statusCmd = [ "sh" "-c" "systemd-inhibit --list 2>/dev/null | grep -q Caffeine && echo '[✓]' || echo ''" ];
      action = { exec = [ "fluteos-power-control" "caffeine-toggle" ]; }; }
  ] ++ lib.optionals (hostConfig.hasTurboBoost or false) [
    { key = "t"; label = "{status} Turbo";
      statusCmd = [ "sh" "-c" "fluteos-power-control is-boost-on && echo 'Disable' || echo 'Enable'" ];
      action = { exec = [ "fluteos-power-control" "boost-toggle" ]; }; }
  ];
}
