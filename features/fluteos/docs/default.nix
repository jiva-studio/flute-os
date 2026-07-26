# Internal documentation feature: docsify-based docs/ folder per project.
#
# A docsify server runs per workspace as a declarative `systemd --user`
# service (defined here, started at login). The user-facing scripts
# (`fluteos-docs-open`, `fluteos-docs-pages`, …) just resolve the URL from
# the registry — they do not start, stop, or own the server lifecycle.
{ lib, config, ... }:
{
  options.features.fluteos.docs = {
    enable = lib.mkEnableOption "Per-project documentation (docsify) tooling";
  };

  config = lib.mkIf config.features.fluteos.docs.enable {
    home-manager.users.${config.features.base.system.user.name} = { pkgs, config, lib, ... }:
    let
      runtimeDeps = lib.makeBinPath [ pkgs.python3 pkgs.jq pkgs.iproute2 pkgs.systemd pkgs.git pkgs.xdg-utils pkgs.niri ];

      resolveHelper = ./_resolve-workspace.sh;

      mkDocsBin = name: scriptPath: pkgs.writeShellScriptBin name ''
        export PATH="${runtimeDeps}:$PATH"
        export JQ="${pkgs.jq}/bin/jq"
        export NIRI="${pkgs.niri}/bin/niri"
        export REGISTRY="$(fluteos-workspaces-registry-path)"
        export RESOLVE_HELPER="${resolveHelper}"
        bash ${scriptPath} "$@"
      '';

      docsInit  = mkDocsBin "fluteos-docs-init"  ./fluteos-docs-init.sh;
      docsServe = mkDocsBin "fluteos-docs-serve" ./fluteos-docs-serve.sh;
      docsOpen  = mkDocsBin "fluteos-docs-open"  ./fluteos-docs-open.sh;
      docsPages = mkDocsBin "fluteos-docs-pages" ./fluteos-docs-pages.sh;
      docsCheck = mkDocsBin "fluteos-docs-check" ./fluteos-docs-check.sh;

      # Build one systemd --user unit per workspace that declares a docsPort.
      # Naming matches the SAFEID used elsewhere: ":" and "/" → "-".
      # `or { }` because features.fluteos.projects is optional: with it off, its
      # home-manager half is not imported at all and `config.features` does not
      # exist here — enabling docs without projects used to fail evaluation
      # outright, with an "attribute 'features' missing" that named neither
      # feature. No projects simply means no docs servers.
      docsServers = lib.filterAttrs (_: eff: eff.workspace && eff.docsPort != null)
        (config.features.fluteos.projects.effective or { });

      mkDocsUnit = pId: eff:
        let safeId = lib.replaceStrings [ ":" "/" ] [ "-" "-" ] "${eff.group.name}:${eff.name}";
        in {
          name = "fluteos-docs-${safeId}";
          value = {
            Unit = {
              Description = "docsify server for ${eff.group.name}:${eff.name}";
              ConditionPathExists = "${eff.docsDir}/index.html";
            };
            Service = {
              ExecStart = "${pkgs.python3}/bin/python3 -m http.server ${toString eff.docsPort} --bind 127.0.0.1";
              WorkingDirectory = eff.docsDir;
              Restart = "on-failure";
              RestartSec = 2;
            };
            Install.WantedBy = [ "default.target" ];
          };
        };
    in
    {
      home.packages = [
        docsInit
        docsServe
        docsOpen
        docsPages
        docsCheck
      ];

      systemd.user.services = lib.listToAttrs (lib.mapAttrsToList mkDocsUnit docsServers);
    };
  };
}
