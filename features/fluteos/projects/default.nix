{ lib, config, pkgs, personalRoot ? null, ... }:
let
  cfg = config.features.fluteos.projects;
  projectsRoot = if personalRoot != null then personalRoot + "/projects" else null;

  # Discover group subdirectories under personal/projects/.
  # A "group dir" is any directory under projects/ whose name doesn't start with "_"
  # (reserved for templates, _backup, etc.).
  discoveredGroups =
    if projectsRoot == null || !builtins.pathExists projectsRoot then []
    else lib.attrNames (lib.filterAttrs
      (n: t: t == "directory" && !(lib.hasPrefix "_" n))
      (builtins.readDir projectsRoot));

  selectedGroups =
    if cfg.enabledGroups == [] then discoveredGroups else cfg.enabledGroups;

  # Recursively find all *.nix files in a directory, excluding the entry default.nix.
  # Returns absolute paths.
  findNixFiles = dir:
    let
      entries = builtins.readDir dir;
      handle = name: type:
        if type == "directory" && !(lib.hasPrefix "_" name) && name != "credentials"
        then findNixFiles (dir + "/${name}")
        # The `_` prefix skips FILES as well as directories. It only skipped
        # directories before, so there was no way to put a shared helper next to
        # the project files in a group: it would be imported as a module and fail.
        else if type == "regular" && lib.hasSuffix ".nix" name
             && name != "default.nix" && !(lib.hasPrefix "_" name)
        then [ (dir + "/${name}") ]
        else [];
    in
    lib.concatLists (lib.mapAttrsToList handle entries);

  # For each selected group:
  #   - import <group>/default.nix (the group definition)
  #   - import every other *.nix recursively (project definitions)
  groupModules = map (g: projectsRoot + "/${g}") selectedGroups;
  projectModules = lib.concatLists (map
    (g:
      let dir = projectsRoot + "/${g}";
      in if builtins.pathExists dir then findNixFiles dir else [])
    selectedGroups);
in
{
  options.features.fluteos.projects = {
    enable = lib.mkEnableOption "Project management with group + flat-projects schema";
    enabledGroups = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = ''
        Allow-list of group directory names (read from ${"\${personalRoot}"}/projects/).
        Empty list (default) auto-discovers all non-"_"-prefixed subdirectories.
      '';
    };
    secretsRoot = lib.mkOption {
      type = lib.types.str;
      default = "";
      example = "/home/you/fluteos-personal";
      description = ''
        Absolute path, on the running machine, of the directory holding group
        credentials (SSH keys and the like). Set by the host; forwarded to the
        home-manager side, which resolves relative `sshKeySource` values against
        it at activation time.

        A string rather than a path deliberately: anything Nix addresses as a
        path is copied into the world-readable /nix/store, which would publish
        the keys to every local user.
      '';
    };
    defaultBrowserProfile = lib.mkOption {
      type = lib.types.str;
      default = "Default";
      example = "AKD";
      description = ''
        Name shown on the Firefox profile that is not tied to a project group.
        Set by the host and forwarded to the home-manager side.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    home-manager.users.${config.features.base.system.user.name} = { ... }: {
      imports = [
        ./options.nix
        ./group-setup.nix
        ./project-setup.nix
      ] ++ groupModules ++ projectModules;

      features.fluteos.projects.secretsRoot = cfg.secretsRoot;
      features.fluteos.projects.defaultBrowserProfile = cfg.defaultBrowserProfile;
    };
  };
}
