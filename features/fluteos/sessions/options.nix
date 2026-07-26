{ lib, ... }:
let
  sessionAppType = lib.types.submodule {
    options = {
      name = lib.mkOption { type = lib.types.str; };
      appId = lib.mkOption { type = lib.types.str; };
      command = lib.mkOption { type = lib.types.listOf lib.types.str; };
      column = lib.mkOption { type = lib.types.int; default = 0; };
      width = lib.mkOption { type = lib.types.nullOr lib.types.str; default = null; };
      focus = lib.mkOption { type = lib.types.bool; default = false; };
      tag = lib.mkOption { type = lib.types.nullOr lib.types.int; default = null; };
    };
  };
in
{
  options.sessions.personal = lib.mkOption {
    type = lib.types.attrsOf (lib.types.submodule {
      options = {
        displayName = lib.mkOption { type = lib.types.str; };
        apps = lib.mkOption { type = lib.types.listOf sessionAppType; default = []; };
      };
    });
    default = {};
  };
}
