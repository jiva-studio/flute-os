# Push-to-talk: packaging and wiring.
{ lib, config, ... }:
let
  cfg = config.features.fluteos.ptt;

  runtimeConfig = {
    version = 1;
    holdKey = cfg.holdKey;
    stt = {
      inherit (cfg.stt) api endpoint model language;
      credential = if cfg.stt.apiKeyFile != null then "stt" else null;
    };
  };
in
{
  imports = [ ./options.nix ];

  config = lib.mkIf cfg.enable {
    home-manager.users.${config.features.base.system.user.name} = { pkgs, lib, config, ... }:
    let
      pythonEnv = pkgs.python3.withPackages (ps: [
        ps.evdev
        ps.websocket-client
        ps.pyaudio
        ps.pyudev
      ]);

      configFile = pkgs.writeText "fluteos-ptt.json" (builtins.toJSON runtimeConfig);

      pttScript = pkgs.stdenv.mkDerivation {
        pname = "fluteos-ptt";
        version = "1.0.0";
        src = lib.cleanSourceWith {
          src = ./.;
          filter = path: type:
            let base = baseNameOf (toString path); in
            if type == "directory" then base != "__pycache__"
            else lib.hasSuffix ".py" base;
        };

        nativeBuildInputs = [ pkgs.makeWrapper ];

        installPhase = ''
          mkdir -p $out/lib/ptt
          cp -r $src/* $out/lib/ptt/

          makeWrapper ${pythonEnv}/bin/python3 $out/bin/fluteos-ptt \
            --add-flags "-m ptt.main" \
            --set PYTHONPATH $out/lib
        '';
      };

    in
    {
      options.ptt.daemon = lib.mkOption {
        type = lib.types.path; default = pttScript;
        description = "The push-to-talk daemon itself; run by the systemd user unit.";
      };

      config = {
        home.packages = [ pttScript pkgs.wl-clipboard pkgs.wtype pkgs.portaudio pkgs.wireplumber ];

        systemd.user.services.fluteos-ptt = {
          Unit = {
            Description = "PTT";
            After = [ "niri-session.target" "pipewire.service" ];
            Requires = [ "niri-session.target" ];
            Wants = [ "pipewire.service" ];
          };
          Service = {
            ExecStart = "${pttScript}/bin/fluteos-ptt";
            Restart = "on-failure";
            Environment = [
              "PYTHONUNBUFFERED=1"
              "PYTHONPATH=${pttScript}/lib"
              "WTYPE_PATH=${pkgs.wtype}/bin/wtype"
              "NOTIFY_SEND_PATH=${pkgs.libnotify}/bin/notify-send"
              "FLUTEOS_PTT_CONFIG=${configFile}"
            ];
          }
          // lib.optionalAttrs (cfg.stt.apiKeyFile != null) {
            LoadCredential = [ "stt:${cfg.stt.apiKeyFile}" ];
            SetCredential = [ "stt:" ];
          };
          Install.WantedBy = [ "niri-session.target" ];
        };
      };
    };
  };
}
