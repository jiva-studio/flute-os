{ lib, config, pkgs, ... }:

let
  cfg = config.features.base.nas;

  deviceType = lib.types.submodule {
    options = {
      id = lib.mkOption {
        type = lib.types.str;
        description = "Syncthing device ID (long base32 string).";
      };
      autoAcceptFolders = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Automatically accept folders shared by this device.";
      };
    };
  };

  versioningType = lib.types.submodule {
    options = {
      type = lib.mkOption { type = lib.types.str; };
      params = lib.mkOption { type = lib.types.attrsOf lib.types.str; default = {}; };
    };
  };

  folderType = lib.types.submodule {
    options = {
      relPath = lib.mkOption {
        type = lib.types.str;
        description = "Folder path relative to the user's home directory (e.g. \"Documents\").";
      };
      devices = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        description = "Names of devices (keys in `features.base.nas.devices`) to share with.";
      };
      ignorePerms = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Whether to ignore permission changes (recommended for cross-OS sync).";
      };
      versioning = lib.mkOption {
        type = lib.types.nullOr versioningType;
        default = null;
        description = "Optional Syncthing versioning policy.";
      };
      extraIgnores = lib.mkOption {
        type = lib.types.lines;
        default = "";
        description = "Extra lines to append to this folder's .stignore (in addition to defaults).";
      };
    };
  };
in
{
  options.features.base.nas = {
    enable = lib.mkEnableOption "NAS and Syncthing";
    syncthing.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Run Syncthing. Off leaves the NFS auto-mounts in place.";
    };
    nasHostname = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "NAS hostname for NFS auto-mount. Empty disables auto-mounting.";
    };
    nasVolume = lib.mkOption {
      type = lib.types.str;
      default = "/volume1";
    };
    shares = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "NFS share names to mount under /mnt/nas/. Empty disables auto-mounting.";
    };
    devices = lib.mkOption {
      type = lib.types.attrsOf deviceType;
      default = {};
      description = "Syncthing peer devices.";
    };
    folders = lib.mkOption {
      type = lib.types.attrsOf folderType;
      default = {};
      description = "Syncthing folders. Path is relative to the user's home directory.";
    };
  };

  config = lib.mkIf cfg.enable (let
    nfsOptions = "nfsvers=4.1,soft,timeo=50,retrans=2,rw,_netdev,noatime";
    autofsMapContent =
      if cfg.nasHostname != "" && cfg.shares != []
      then builtins.concatStringsSep "\n" (
        map (share: "${share} -fstype=nfs4,${nfsOptions} ${cfg.nasHostname}:${cfg.nasVolume}/${share}") cfg.shares
      )
      else "";

    defaultIgnoreLines = ''
      # JS/TS
      **/node_modules
      **/.next
      **/.nuxt
      **/.output
      **/.svelte-kit
      **/.angular
      **/.parcel-cache
      **/.turbo
      **/.cache
      # Python
      **/venv
      **/.venv
      **/__pycache__
      **/.pytest_cache
      **/.mypy_cache
      **/.ruff_cache
      **/*.egg-info
      **/.tox
      # Rust
      **/target
      # Go
      **/vendor
      # .NET
      **/bin
      **/obj
      # Elixir
      **/_build
      **/deps
      # Dart/Flutter
      **/.dart_tool
      # IDE
      **/.idea
      **/.vscode
      # Build/Dist
      **/dist
      **/build
      **/out
      **/coverage
      # Git
      **/.git
      # OS
      **/.DS_Store
      **/Thumbs.db
      # Misc
      **/*.log
      **/*.tmp
      **/*~
      **/*.swp
      # Synology NAS
      **/@eaDir
    '';

    # The "Projects" folder gets the heavy default ignore set; everything else
    # gets a minimal default plus per-folder extras.
    isProjectsFolder = relPath: relPath == "Projects";
  in {
    # NFS auto-mount only if hostname + shares configured
    services.avahi = lib.mkIf (cfg.nasHostname != "") { enable = true; nssmdns4 = true; };
    environment.systemPackages = lib.mkIf (cfg.nasHostname != "") (with pkgs; [ nfs-utils ]);
    boot.supportedFilesystems = lib.mkIf (cfg.nasHostname != "") [ "nfs" "nfs4" ];
    services.autofs = lib.mkIf (cfg.nasHostname != "" && cfg.shares != []) {
      enable = true;
      timeout = 300;
      autoMaster = ''
        /mnt/nas /etc/autofs/auto.nas --timeout=300 --ghost
      '';
    };
    environment.etc = lib.mkIf (cfg.nasHostname != "" && cfg.shares != []) {
      "autofs/auto.nas".text = autofsMapContent;
    };
    systemd.tmpfiles.rules = lib.mkIf (cfg.nasHostname != "" && cfg.shares != []) [
      "d /mnt/nas 0755 root root -"
    ];

    # Syncthing (Home Manager). Folders/devices come from cfg.{folders,devices}
    # and may legitimately be empty.
    home-manager.users.${config.features.base.system.user.name} = { config, ... }:
      lib.mkIf cfg.syncthing.enable {
        services.syncthing = {
          enable = true;
          tray.enable = false;
          settings = {
            options = {
              globalAnnounceEnabled = true;
              localAnnounceEnabled = true;
              relaysEnabled = true;
              natEnabled = true;
              urAccepted = -1;
            };
            devices = lib.mapAttrs (_: d: {
              inherit (d) id autoAcceptFolders;
            }) cfg.devices;
            folders = lib.mapAttrs (_: f: {
              path = "${config.home.homeDirectory}/${f.relPath}";
              inherit (f) devices ignorePerms;
            } // lib.optionalAttrs (f.versioning != null) { inherit (f) versioning; }) cfg.folders;
          };
          overrideDevices = true;
          overrideFolders = true;
        };

        # Per-folder .stignore: minimal default + per-folder extras.
        # Projects folder gets the full build-artifact ignore list.
        home.file = lib.mapAttrs' (_: f: {
          name = "${f.relPath}/.stignore";
          value.text =
            (if isProjectsFolder f.relPath then defaultIgnoreLines else "**/@eaDir\n")
            + lib.optionalString (f.extraIgnores != "") "\n${f.extraIgnores}";
        }) cfg.folders;
      };
  });
}
