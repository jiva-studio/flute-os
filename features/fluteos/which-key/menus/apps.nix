# Applications menu.
#
# The item list is DERIVED from features.fluteos.apps.resolved, the same list the
# launcher's fuzzy search uses. It used to be seven hardcoded lines — Firefox,
# Neovim, VS Code, Obsidian, Telegram, Responsively — so the product shipped one
# person's software to every install, and `responsively` was a package that
# existed nowhere but the author's private overlay: pressing `r` on any other
# machine raised FileNotFoundError and popped a critical notification.
#
# This is the same defect features/fluteos/apps was rewritten to fix (see its
# header); the key menu was the half that got missed while the fuzzy search was
# already reading the resolved list.
{ lib, hostConfig }:

let
  # An app entry may pin its own key (`key = "b"`). Those are claimed first, in
  # one pass over the whole list, so a pinned key wins over a letter a
  # higher-up app would otherwise have derived. "/" belongs to the search entry.
  reserved = lib.foldl'
    (taken: app: taken // lib.optionalAttrs (app ? key) { ${app.key} = true; })
    { "/" = true; }
    hostConfig.apps;

  # Everything else gets the first character of its label that is still free.
  # Derived rather than assigned by hand, because the list itself is derived — a
  # fixed key table cannot stay in step with what a machine installs.
  #
  # An app whose every letter is taken keeps no key and is reachable through
  # `/` (fuzzy search), which lists everything unconditionally.
  # An entry may point its chord at a submenu instead of launching. Firefox does:
  # its chord opens the profile picker, which is the whole reason to press it.
  # `action.exec` stays on the entry for the fuzzy search and the voice router.
  itemFor = key: app: {
    inherit key;
    inherit (app) label;
    action = if app ? menu then { menu = app.menu; } else app.action;
  };

  assign = acc: app:
    if app ? key then acc // {
      items = acc.items ++ [ (itemFor app.key app) ];
    }
    else
      let
        free = lib.filter
          (ch: builtins.match "[a-z0-9]" ch != null && !(acc.taken ? ${ch}))
          (lib.stringToCharacters (lib.toLower app.label));
      in
      if free == [ ] then acc
      else
        let key = builtins.head free; in {
          taken = acc.taken // { ${key} = true; };
          items = acc.items ++ [ (itemFor key app) ];
        };

  assigned = lib.foldl' assign { taken = reserved; items = [ ]; } hostConfig.apps;
in
{
  apps = {
    type = "key";
    items = assigned.items ++ [
      { key = "/"; label = "Search..."; action = { menu = "apps-search"; }; }
    ];
  };

  apps-search = {
    type = "fuzzy";
    items = hostConfig.apps;
  };
}
