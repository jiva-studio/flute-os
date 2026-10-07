{ lib, config, pkgs, ... }:
{
  imports = [
    ./boot.nix
    ./networking.nix
    ./users.nix
    ./console.nix
    ./packages.nix
  ];

  options.features.base.system = {
    enable = lib.mkEnableOption "Base system configuration";
    hostname = lib.mkOption {
      type = lib.types.str;
      default = "flute";
      description = "System hostname";
    };
    timeZone = lib.mkOption {
      type = lib.types.str;
      default = "UTC";
      example = "Europe/Berlin";
      description = "System time zone. UTC by default — the distribution has no opinion on where you live.";
    };
    defaultLocale = lib.mkOption {
      type = lib.types.str;
      default = "en_US.UTF-8";
      description = "Default system locale.";
    };
    extraLocaleSettings = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      example = { LC_TIME = "en_GB.UTF-8"; LC_PAPER = "en_GB.UTF-8"; };
      description = ''
        Per-category locale overrides (LC_TIME, LC_PAPER, …). Empty by default,
        so every category follows `defaultLocale`. Use this to keep an English
        interface while dates, paper size and number formats follow your own
        conventions.
      '';
    };
    flatpak = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Install Flatpak and put its exports on XDG_DATA_DIRS. Some features
        ship Flatpak applications; turn this off on a host that should stay
        Nix-only.
      '';
    };
  };

  config = lib.mkIf config.features.base.system.enable (lib.mkMerge [
   (lib.mkIf config.features.base.system.flatpak {
    services.flatpak.enable = true;
    # Flatpak asserts on a portal being present, and nothing else here provides
    # one — a host that enables the base system without niri would otherwise
    # fail to evaluate. mkDefault so a compositor's own portal config wins.
    xdg.portal.enable = lib.mkDefault true;
    environment.sessionVariables = {
      XDG_DATA_DIRS = [
        "/var/lib/flatpak/exports/share"
        "\${HOME}/.local/share/flatpak/exports/share"
      ];
    };
   })

   {
    security.sudo.extraRules = [{
      users = [ config.features.base.system.user.name ];
      commands = [
        {
          command = "/run/current-system/sw/bin/tee /sys/devices/system/cpu/cpufreq/boost";
          options = [ "NOPASSWD" ];
        }
        {
          # The other name cpufreq gives the same switch. fluteos-power-control
          # probes for `boost` then `cpb`, but only `boost` was whitelisted, so
          # on amd_pstate=active — where only `cpb` exists — the Turbo toggle
          # asked for a password with no tty to type it into and silently did
          # nothing.
          command = "/run/current-system/sw/bin/tee /sys/devices/system/cpu/cpufreq/cpb";
          options = [ "NOPASSWD" ];
        }
        {
          command = "/run/current-system/sw/bin/tee /sys/firmware/acpi/platform_profile";
          options = [ "NOPASSWD" ];
        }
      ];
    }];
    systemd.services.rfkill-unblock = {
      description = "Unblock Bluetooth and WiFi adapters";
      after = [ "bluetooth.service" "NetworkManager.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.util-linux}/bin/rfkill unblock all";
        RemainAfterExit = true;
      };
    };
    programs.nix-ld = {
      enable = true;
      libraries = with pkgs; [ stdenv.cc.cc.lib zlib ];
    };
    nix = {
      settings = {
        experimental-features = [ "nix-command" "flakes" ];
        auto-optimise-store = true;
        warn-dirty = false;
      };
      gc = { automatic = true; dates = "daily"; options = "--delete-older-than 7d"; };
    };
    nixpkgs.config = {
      allowUnfree = true;
      allowUnfreePredicate = _: true;
      android_sdk.accept_license = true;
      permittedInsecurePackages = [ ];
    };
    time.timeZone = config.features.base.system.timeZone;
    i18n.defaultLocale = config.features.base.system.defaultLocale;
    i18n.extraLocaleSettings = config.features.base.system.extraLocaleSettings;
    services.fstrim = { enable = true; interval = "weekly"; };
    # mkDefault: a downstream host states its own state version, and a plain
    # assignment here would collide with it rather than be overridden.
    system.stateVersion = lib.mkDefault "24.11";

    home-manager.users.${config.features.base.system.user.name} = { pkgs, ... }: {
      home.stateVersion = lib.mkDefault "26.05";
      programs.home-manager.enable = true;
      home.pointerCursor = {
        enable = true;
        name = "Bibata-Modern-Classic";
        package = pkgs.bibata-cursors;
        size = 24;
        gtk.enable = true;
      };
      home.packages = with pkgs; [
        ripgrep fd bat eza fzf jq yq
        zip unzip p7zip
        btop
        curl wget
      ];
      # `direnv use nix -p ...` invokes legacy nix-shell, which reads
      # ~/.config/nixpkgs/config.nix (not the flake's nixpkgs.config). Mirror
      # the system policy so unfree packages (e.g. yandex-cloud) work in
      # per-project devTools.
      home.file.".config/nixpkgs/config.nix".text = ''
        { allowUnfree = true; }
      '';
      xdg = {
        enable = true;
        userDirs = { enable = true; createDirectories = true; setSessionVariables = false; };
        configFile."autostart/blueman.desktop".text = ''
          [Desktop Entry]
          Hidden=true
        '';
      };
      programs.direnv = {
        enable = true;
        nix-direnv.enable = true;
        silent = true;
      };
      # nix-direnv writes "nix-direnv: <path>" cache-invalidation chatter via raw
      # `echo >/dev/stderr`, bypassing log_status (so direnv.silent has no effect).
      # Wrap use_nix/use_flake after nix-direnv loads (lib/ files load alphabetically
      # after stdlib) and filter those lines out of stderr.
      home.file.".config/direnv/lib/zz-silence-nix-direnv.sh".text = ''
        # shellcheck shell=bash
        _nix_direnv_info()    { :; }
        _nix_direnv_warning() { :; }

        __zz_nix_direnv_filter() {
          grep -vE '^nix-direnv: |^/[^[:space:]]+\.envrc$|^/[^[:space:]]+/direnvrc$' >&2 || true
        }

        for __fn in use_nix use_flake; do
          if declare -F "$__fn" >/dev/null; then
            eval "_orig_$__fn() $(declare -f "$__fn" | tail -n +2)"
            eval "$__fn() { _orig_$__fn \"\$@\" 2> >(__zz_nix_direnv_filter); }"
          fi
        done
        unset __fn
      '';
    };
   }
  ]);
}
