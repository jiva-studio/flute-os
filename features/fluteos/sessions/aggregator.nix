{ config, lib, ... }:
let
  # Per-project sessions, keyed by "<group>:<project>" (the workspace ID).
  projectSessions = lib.mapAttrs' (pId: eff: {
    name = "${eff.group.name}:${eff.name}";
    value = {
      displayName = "${eff.group.displayName} : ${eff.displayName}";
      apps = eff.sessionApps;
    };
  }) (lib.filterAttrs
    (_: eff: eff.sessionApps != [])
    (config.features.fluteos.projects.effective or {}));

  personalSessions = config.sessions.personal;
in
{
  options.sessions.all = lib.mkOption {
    type = lib.types.attrs;
    readOnly = true;
  };
  config.sessions.all = projectSessions // personalSessions;
}
