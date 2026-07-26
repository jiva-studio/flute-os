# Firefox profile menu
{ config, lib }:

let
  profileList = lib.mapAttrsToList (key: profile: {
    inherit key;
    id = profile.id;
    name = profile.name;
  }) config.programs.firefox.profiles;

  sortedProfiles = lib.sort (a: b: a.id < b.id) profileList;

  items = lib.imap1 (i: p: {
    key = toString i;
    label = p.name;
    action = { exec = [ "firefox" "-P" p.name "--new-window" ]; };
  }) sortedProfiles;
in
{
  type = "key";
  inherit items;
}
