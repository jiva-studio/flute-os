{ lib, config, ... }:

{
  options.features.fluteos.wallpapers = {
    enable = lib.mkEnableOption "Desktop wallpapers";
    rotation = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Cycle the wallpaper every `interval` seconds.

          This option used to be read by nothing at all: the rotation daemon was
          installed unconditionally, so setting it to false changed nothing. It
          defaults to true because that is what the code has always done — the
          fix is that it is now honoured, not that the behaviour changed.
        '';
      };
      interval = lib.mkOption {
        type = lib.types.int;
        default = 1800;
        description = "Rotation interval in seconds (default: 30 minutes)";
      };
    };
  };

  config = lib.mkIf config.features.fluteos.wallpapers.enable {
    home-manager.users.${config.features.base.system.user.name} = { pkgs, ... }@hm: let
      cfg = hm.osConfig.features.fluteos.wallpapers;

      wallpaper = pkgs.writeShellScriptBin "fluteos-wallpaper" ''
        export AWWW="${pkgs.awww}/bin/awww"
        export INTERVAL="${toString cfg.rotation.interval}"
        bash ${./fluteos-wallpaper.sh} "$@"
      '';
    in {
      home.packages = [ pkgs.awww wallpaper ];

      home.file."Pictures/Wallpapers/sample.png".source = ./sample.png;

      # The daemon that paints is unconditional; the one that CYCLES follows
      # rotation.enable. One attrset, because two `systemd.user.services.*`
      # assignments in the same literal collide.
      systemd.user.services = {
        awww-daemon = {
          Unit = {
            Description = "awww wallpaper daemon";
            After = [ "niri-session.target" ];
            PartOf = [ "niri-session.target" ];
          };
          Service = {
            ExecStart = "${pkgs.awww}/bin/awww-daemon";
            Restart = "on-failure";
            RestartSec = 2;
          };
          Install = {
            WantedBy = [ "niri-session.target" ];
          };
        };
      } // lib.optionalAttrs cfg.rotation.enable {
        fluteos-wallpaper = {
          Unit = {
            Description = "Wallpaper rotation daemon";
            After = [ "niri-session.target" "awww-daemon.service" ];
            Requires = [ "awww-daemon.service" ];
            PartOf = [ "niri-session.target" ];
          };
          Service = {
            ExecStart = "${wallpaper}/bin/fluteos-wallpaper";
            Restart = "always";
            RestartSec = 5;
          };
          Install = {
            WantedBy = [ "niri-session.target" ];
          };
        };
      };
    };
  };
}
