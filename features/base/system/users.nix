{ lib, config, pkgs, ... }:
let
  cfg = config.features.base.system;
in
{
  options.features.base.system.user = {
    name = lib.mkOption {
      type = lib.types.str;
      default = "user";
      description = "Primary user account name (UNIX login name).";
    };
    description = lib.mkOption {
      type = lib.types.str;
      default = "User";
      description = "Display name shown by login managers.";
    };
    realName = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "Full real name (used as global git user.name when non-empty).";
    };
    email = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "Primary email (used as global git user.email when non-empty).";
    };
    initialPassword = lib.mkOption {
      type = lib.types.str;
      default = "changeme";
      description = "Password used on first boot before the user changes it.";
    };
    extraGroups = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "wheel" "networkmanager" "video" "audio" "input" "uinput" "docker" ];
      description = "UNIX groups the primary user belongs to.";
    };
  };

  config = lib.mkIf cfg.enable {
    users.users.${cfg.user.name} = {
      isNormalUser = true;
      description = cfg.user.description;
      extraGroups = cfg.user.extraGroups;
      shell = pkgs.fish;
      initialPassword = cfg.user.initialPassword;
    };
    programs.fish.enable = true;
  };
}
