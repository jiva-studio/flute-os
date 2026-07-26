{ lib, config, ... }:

let
  cfg = config.features.base.yazi;
  nas = config.features.base.nas;

  bookmarkType = lib.types.submodule {
    options = {
      path = lib.mkOption {
        type = lib.types.str;
        example = "~/Downloads";
        description = "Directory to jump to. Yazi expands a leading `~`.";
      };
      desc = lib.mkOption {
        type = lib.types.str;
        default = "";
        example = "Downloads";
        description = "Label in yazi's key-hint popup. Empty shows the path itself.";
      };
    };
  };

  # "n a" -> [ "g" "n" "a" ]
  chordOf = key: [ "g" ] ++ lib.splitString " " key;

  # Optional NAS jump keys, derived rather than hardcoded: `g n n` for the mount
  # root and `g n <letter>` per share, each taking the first character of the
  # share name still unclaimed (lower case first, then upper). Deterministic but
  # not necessarily the mnemonic a human would pick — see `nasBookmarks`.
  nasDerived =
    let
      claim = acc: share:
        let
          candidates =
            lib.stringToCharacters share
            ++ lib.stringToCharacters (lib.toUpper share);
          free = lib.filter (ch: !(acc.used ? ${ch})) candidates;
        in
          if free == [ ] then acc
          else {
            used = acc.used // { ${lib.head free} = true; };
            out = acc.out // {
              "n ${lib.head free}" = { path = "/mnt/nas/${share}"; desc = share; };
            };
          };
      seed = {
        used = { n = true; };
        out = { "n n" = { path = "/mnt/nas"; desc = "NAS root"; }; };
      };
    in
      if cfg.nasBookmarks && nas.enable && nas.shares != [ ]
      then (lib.foldl' claim seed nas.shares).out
      else { };

  # Explicit bookmarks win over derived ones on key collision.
  effectiveBookmarks = nasDerived // cfg.bookmarks;

  keymapEntries = lib.mapAttrsToList (key: b: {
    on = chordOf key;
    run = "cd ${b.path}";
    desc = if b.desc != "" then b.desc else b.path;
  }) effectiveBookmarks;
in
{
  options.features.base.yazi = {
    enable = lib.mkEnableOption "Yazi file manager";

    bookmarks = lib.mkOption {
      type = lib.types.attrsOf bookmarkType;
      default = {
        h = { path = "~"; desc = "Home"; };
        c = { path = "~/.config"; desc = "Config"; };
      };
      example = lib.literalExpression ''
        {
          h = { path = "~"; desc = "Home"; };
          c = { path = "~/.config"; desc = "Config"; };
          d = { path = "~/Downloads"; desc = "Downloads"; };
          "n m" = { path = "/mnt/nas/movies"; desc = "Movies"; };
        }
      '';
      description = ''
        Directory jump keys, as attribute name -> destination. The attribute name
        is the key sequence *after* the `g` prefix, so `"d"` binds `g d` and
        `"n m"` binds `g n m`.

        The default holds only `~` and `~/.config`: a jump key to a directory
        that does not exist is worse than no jump key, and everything beyond
        those two is a guess about how you organise your disk. Add your own in
        your host or personal configuration.
      '';
    };

    nasBookmarks = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Also derive `g n …` jump keys from `features.base.nas.shares` (only when
        the NAS feature is enabled and has shares). Off by default: letters are
        assigned mechanically from each share name, so the result is stable but
        rarely the mnemonic you would have chosen — two shares starting with the
        same letter cannot both keep it. Anything set in `bookmarks` overrides a
        derived key of the same name.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    home-manager.users.${config.features.base.system.user.name} = {
      programs.yazi = {
        enable = true;
        enableZshIntegration = true;
        settings = {
          manager = { show_hidden = true; sort_by = "natural"; sort_dir_first = true; linemode = "size"; };
        };
        keymap = {
          mgr.prepend_keymap = keymapEntries;
        };
      };
      # flavour and accent come from the global catppuccin.* the theme module sets,
      # so a palette switch reaches this port too.
      catppuccin.yazi.enable = true;
    };
  };
}
