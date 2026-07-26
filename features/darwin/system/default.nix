{ lib, config, pkgs, ... }:
let cfg = config.features.darwin.system; in
{
  options.features.darwin.system = {
    enable = lib.mkEnableOption "Base nix-darwin system configuration";
    hostname = lib.mkOption {
      type = lib.types.str;
      example = "workbench";
      description = ''
        System hostname. Required, with no default: the default used to be the
        owner's own machine name, which every other Mac would then silently
        inherit. Same reasoning as `primaryUser` below.
      '';
    };

    timeZone = lib.mkOption {
      type = lib.types.str;
      default = "UTC";
      example = "Europe/Berlin";
      description = "System time zone. UTC by default — the OS has no opinion on where you live.";
    };
    primaryUser = lib.mkOption {
      type = lib.types.str;
      example = "akd";
      description = ''
        macOS user account that owns this machine. Required (no default) —
        each host explicitly states which login user this is. NOT necessarily
        the same as the daily-driver personal user; on a CI builder it may
        be a dedicated runner account.
      '';
    };
    trustedUsers = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "@admin" ];
      description = ''
        Users (or @groups) trusted by the Nix daemon. Default is just
        @admin; extend per-host to grant additional accounts.
      '';
    };
    power = lib.mkOption {
      type = lib.types.enum [ "always-on" "wake-on-network" ];
      default = "always-on";
      description = ''
        Sleep/wake policy:
        - "always-on": never sleeps (caffeinate + `pmset disablesleep 1`), even
          with the lid closed; display still sleeps. Required for the CI host —
          the self-hosted runner long-polls GitHub and must stay awake.
        - "wake-on-network": sleeps after idle, wakes on a network/magic packet
          (`pmset womp 1`). For idle/personal hosts. NOTE: waking on an arbitrary
          incoming connection needs a Bonjour Sleep Proxy on the LAN (or a
          tailscale-WoL from a LAN peer); plain WoL needs a magic packet, and on
          laptops `womp` typically works only on AC power.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    networking.hostName = cfg.hostname;
    networking.computerName = cfg.hostname;
    networking.localHostName = cfg.hostname;

    # We install Nix via the Determinate installer, which runs its own daemon and
    # manages /etc/nix/nix.conf itself (flakes + nix-command are on by default and
    # the installing user is trusted). nix-darwin must NOT also manage Nix or it
    # aborts activation ("Determinate detected"). So disable nix-darwin's Nix
    # management; the nix.* settings/gc below would be no-ops under Determinate.
    nix.enable = false;

    nixpkgs.config = {
      allowUnfree = true;
      allowUnfreePredicate = _: true;
    };

    time.timeZone = cfg.timeZone;

    # Base CLI tooling shared by every Mac. CI/iOS build tools (rclone, ruby,
    # bundler, cocoapods) live in features/darwin/github-runner — they're runner
    # dependencies and should not land on non-CI hosts.
    environment.systemPackages = with pkgs; [
      git
      git-crypt
      gh
      jq
      curl
      ripgrep
      fd
      bat
      eza
      fzf
      htop
    ];

    # --- Power / sleep policy (see features.darwin.system.power) -------------

    # always-on: keep the machine awake for the lifetime of the system so the
    # CI runner never misses a job (it long-polls GitHub).
    launchd.daemons.caffeinate = lib.mkIf (cfg.power == "always-on") {
      command = "${pkgs.coreutils}/bin/env caffeinate -i -s";
      serviceConfig = {
        KeepAlive = true;
        RunAtLoad = true;
        StandardOutPath = "/var/log/caffeinate.log";
        StandardErrorPath = "/var/log/caffeinate.err";
      };
    };

    # Display always allowed to sleep; computer sleep depends on the mode.
    power.sleep.display = 5;
    power.sleep.computer = if cfg.power == "always-on" then "never" else 20;

    # `disablesleep` / `womp` have no nix-darwin option → set via pmset. Idempotent.
    system.activationScripts.extraActivation.text = lib.mkAfter (
      if cfg.power == "always-on"
      then ''
        # Never sleep, even with the lid closed (clamshell).
        /usr/bin/pmset -a disablesleep 1
      ''
      else ''
        # Allow sleep; wake on magic packet / network access.
        /usr/bin/pmset -a disablesleep 0
        /usr/bin/pmset -a womp 1
      ''
    );

    system.stateVersion = 5;
    system.primaryUser = cfg.primaryUser;
  };
}
