{ lib, config, pkgs, ... }:

let
  cfg = config.features.base.bluetooth;
in
{
  options.features.base.bluetooth = {
    enable = lib.mkEnableOption "Bluetooth support";
    adapterMac = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "Bluetooth adapter MAC address for declarative pairings";
    };
    pairedDevices = lib.mkOption {
      type = lib.types.attrsOf (lib.types.attrsOf lib.types.anything);
      default = {};
      description = "Paired Bluetooth devices configuration";
    };
  };

  config = lib.mkIf cfg.enable {
    hardware.bluetooth = {
      enable = true;
      powerOnBoot = true;
      settings = {
        General = {
          FastConnectable = true;
          JustWorksRepairing = "always";
          ReconnectAttempts = 7;
          ReconnectIntervals = "1, 2, 4, 8, 16, 32, 64";
        };
        Policy = {
          AutoEnable = true;
        };
      };
    };

    services.blueman.enable = true;

    # Declarative Bluetooth pairings (if adapterMac is set)
    systemd.services.bluetooth-pairings = lib.mkIf (cfg.adapterMac != "") (let
      mkInfoFile = deviceMac: device: ''
        [General]
        Name=${device.name}
        Appearance=${device.appearance or "0x0000"}
        AddressType=${device.addressType or "static"}
        SupportedTechnologies=LE;
        Trusted=true
        Blocked=false
        WakeAllowed=true

        [IdentityResolvingKey]
        Key=${device.identityResolvingKey}

        [PeripheralLongTermKey]
        Key=${device.longTermKey.key}
        Authenticated=${toString (device.longTermKey.authenticated or 0)}
        EncSize=${toString device.longTermKey.encSize}
        EDiv=${toString device.longTermKey.eDiv}
        Rand=${toString device.longTermKey.rand}

        [SlaveLongTermKey]
        Key=${device.longTermKey.key}
        Authenticated=${toString (device.longTermKey.authenticated or 0)}
        EncSize=${toString device.longTermKey.encSize}
        EDiv=${toString device.longTermKey.eDiv}
        Rand=${toString device.longTermKey.rand}
      '';

      setupScript = pkgs.writeShellScript "setup-bluetooth-pairings" ''
        set -euo pipefail
        BT_DIR="/var/lib/bluetooth/${cfg.adapterMac}"

        mkdir -p "$BT_DIR"
        chmod 700 "$BT_DIR"

        ${lib.concatStringsSep "\n" (lib.mapAttrsToList (deviceMac: device: ''
          mkdir -p "$BT_DIR/${deviceMac}"
          chmod 700 "$BT_DIR/${deviceMac}"

          if [ ! -f "$BT_DIR/${deviceMac}/info" ]; then
            cat > "$BT_DIR/${deviceMac}/info" << 'EOF'
        ${mkInfoFile deviceMac device}
        EOF
            chmod 600 "$BT_DIR/${deviceMac}/info"
          fi
        '') cfg.pairedDevices)}
      '';
    in {
      description = "Setup declarative Bluetooth pairings";
      wantedBy = [ "bluetooth.service" ];
      before = [ "bluetooth.service" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = setupScript;
        RemainAfterExit = true;
      };
    });
  };
}
