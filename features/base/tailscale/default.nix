{ lib, config, pkgs, ... }:
let
  cfg = config.features.base.tailscale;
in
{
  options.features.base.tailscale = {
    enable = lib.mkEnableOption "Tailscale VPN";

    ssh = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable Tailscale SSH (`tailscale set --ssh`).";
    };

    operator = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      # No `or null` fallback: features.base.system always declares user.name, so
      # the guard could never fire and the "null disables it" case below is only
      # reachable by stating null explicitly.
      default = config.features.base.system.user.name;
      description = ''
        User granted operator rights (`tailscale set --operator=<user>`) so
        `tailscale up`/`switch` and the tailnet-switcher widget run without sudo.
        Null disables setting an operator.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    services.tailscale.enable = true;

    # Declarative `tailscale set` flags. NOTE: deliberately NO `authKeyFile` here
    # — yoga holds two profiles (personal + a project tailnet) and fast-switches
    # between them; an auth key would re-`up` the personal tailnet on rebuild
    # whenever the personal context is Stopped/NeedsLogin (i.e. while switched to
    # the project profile) and clobber the active profile. Both accounts are
    # added once manually via `tailscale login`.
    services.tailscale.extraSetFlags =
      lib.optionals cfg.ssh [ "--ssh" ]
      ++ lib.optionals (cfg.operator != null) [ "--operator=${cfg.operator}" ];

    environment.systemPackages = [ pkgs.tailscale ];
  };
}
