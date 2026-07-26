# features.fluteos.apps — the launcher's list of applications.
#
# The list used to be a data file (features/fluteos/apps.nix) imported directly
# by which-key and by the voice command router, with an `extraApps` option that
# could only ever APPEND. So the product shipped one person's software —
# Telegram, Teams, 1Password, DigiKam, MuseScore, Chrome — to every install, and
# a downstream user could add to it but never remove anything.
#
# The default is now DERIVED from which features are enabled: the launcher
# offers what this machine actually has, which is right for a stranger and right
# for the owner. `apps` replaces that default outright for full control;
# `extraApps` still appends, for software installed outside a feature.
{ lib, config, ... }:
let
  cfg = config.features.fluteos.apps;

  # Applications this OS can install, each paired with the feature that provides
  # it. An entry appears only when its feature is on, so no launcher entry ever
  # points at a binary that is not installed.
  #
  # `key` pins the which-key chord. The chord is stated next to the application
  # it belongs to rather than in the menu, which is what lets the menu stay
  # derived: `b` means browser here and on a machine with half these features
  # switched off, instead of shifting as the list shrinks.
  featureApps = [
    # `menu` sends the which-key chord to the profile picker instead of launching
    # straight away — Firefox is the one application here where WHICH profile is
    # the whole question. `action.exec` still opens the default profile, and is
    # what the fuzzy search and the voice router use.
    { enabled = config.features.base.firefox.enable or false;
      key = "b"; menu = "firefox"; icon = "󰈹"; label = "Firefox"; action.exec = [ "firefox" ]; }
    # `w` for wezterm, not `t`: `t` was Telegram in the menu this list replaced,
    # and silently reassigning a chord someone types without looking is worse
    # than a slightly odd mnemonic. The pins below keep every chord the previous
    # hardcoded menu had — b, v, o, t — and only add.
    { enabled = config.features.base.terminal.enable or false;
      key = "w"; icon = "󰆍"; label = "Terminal"; action.exec = [ "wezterm" ]; }
    { enabled = (config.features.base.neovim.enable or false)
             && (config.features.base.terminal.enable or false);
      key = "v"; icon = "󰕷"; label = "Neovim";
      action.exec = [ "wezterm" "start" "--always-new-process" "--" "nvim" ]; }
    { enabled = (config.features.base.yazi.enable or false)
             && (config.features.base.terminal.enable or false);
      key = "f"; icon = "󰉋"; label = "File Manager"; action.exec = [ "wezterm" "start" "--" "yazi" ]; }
    { enabled = config.features.base.nautilus.enable or false;
      key = "n"; icon = "󰝰"; label = "Files (GNOME)"; action.exec = [ "nautilus" "--new-window" ]; }
    { enabled = config.features.base.obsidian.enable or false;
      key = "o"; icon = "󱓧"; label = "Obsidian"; action.exec = [ "obsidian" ]; }
    { enabled = config.features.base.zathura.enable or false;
      key = "z"; icon = "󰈦"; label = "Zathura"; action.exec = [ "zathura" ]; }
    { enabled = config.features.base.foliate.enable or false;
      key = "e"; icon = "󰂿"; label = "Foliate"; action.exec = [ "foliate" ]; }
    { enabled = config.features.base.telegram.enable or false;
      key = "t"; icon = "󰔁"; label = "Telegram"; action.exec = [ "Telegram" ]; }
    { enabled = config.features.base.teams.enable or false;
      key = "m"; icon = "󰊻"; label = "Teams"; action.exec = [ "teams-for-linux" ]; }
    { enabled = config.features.base.onepassword.enable or false;
      key = "p"; icon = "󰢁"; label = "1Password"; action.exec = [ "1password" ]; }
    { enabled = config.features.base.digikam.enable or false;
      key = "k"; icon = "󰄀"; label = "DigiKam"; action.exec = [ "digikam" ]; }
  ];

  derivedApps = map (a: lib.removeAttrs a [ "enabled" ])
    (lib.filter (a: a.enabled) featureApps);
in
{
  options.features.fluteos.apps = {
    enable = lib.mkEnableOption "FluteOS application launcher entries";

    apps = lib.mkOption {
      type = lib.types.listOf lib.types.attrs;
      default = derivedApps;
      defaultText = lib.literalMD
        "one entry per enabled application feature (Firefox, Terminal, Obsidian, …)";
      description = ''
        The launcher's application list. Defaults to the applications this
        machine's enabled features install; assign to it to take over the list
        completely. Each entry is `{ icon; label; action.exec = [ … ]; }`.

        An entry may also carry `key = "b"` to pin its chord in the which-key
        applications menu. Unpinned entries get the first free character of
        their label, which is stable for a given list but shifts if the list
        changes — pin the few you press without thinking.

        `menu = "<name>"` points that chord at a which-key submenu rather than
        launching the app: Firefox uses it for the profile picker. `action.exec`
        is still required, and is what the fuzzy search and the voice command
        router use.
      '';
    };

    extraApps = lib.mkOption {
      type = lib.types.listOf lib.types.attrs;
      default = [ ];
      example = lib.literalExpression ''
        [ { icon = "󰎵"; label = "MuseScore"; action.exec = [ "mscore" ]; } ]
      '';
      description = ''
        Applications to append — for software installed outside a feature, e.g.
        straight from `home.packages`. To *remove* an entry instead, set `apps`.
      '';
    };

    resolved = lib.mkOption {
      type = lib.types.listOf lib.types.attrs;
      readOnly = true;
      internal = true;
      description = "`apps` ++ `extraApps` — what every consumer reads.";
    };
  };

  config = lib.mkIf cfg.enable {
    features.fluteos.apps.resolved = cfg.apps ++ cfg.extraApps;
  };
}
