{ lib, config, osConfig ? null, ... }:
let
  systemUser =
    if osConfig != null
    then osConfig.features.base.system.user or { realName = ""; email = ""; }
    else { realName = ""; email = ""; };

  rootDir = config.features.fluteos.projects.rootDir;
  defaultBrowserProfile = config.features.fluteos.projects.defaultBrowserProfile;

  sessionAppType = lib.types.submodule {
    options = {
      name = lib.mkOption { type = lib.types.str; };
      appId = lib.mkOption { type = lib.types.str; };
      command = lib.mkOption { type = lib.types.listOf lib.types.str; };
      column = lib.mkOption {
        type = lib.types.int;
        default = 0;
        description = "Column index. Same column = stacked windows.";
      };
      width = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Column width: '50%', 'fixed 800', 'proportion 0.3'";
      };
      focus = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Focus this window after session restore";
      };
      tag = lib.mkOption {
        type = lib.types.nullOr lib.types.int;
        default = null;
        description = "Window tag (1-4) to assign after launch";
      };
    };
  };

  repoType = lib.types.submodule ({ name, ... }: {
    options = {
      name = lib.mkOption {
        type = lib.types.str;
        default = name;
        description = "Repo directory name under <project>/source/. Defaults to attribute key.";
      };
      url = lib.mkOption {
        type = lib.types.str;
        description = "Git remote URL (required).";
      };
      branch = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Optional branch to check out after clone.";
      };
      sparse = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        description = "Sparse-checkout paths. Empty = full clone.";
      };
      primary = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Marks the 'main' repo for ambiguous defaults (e.g., python venv location).";
      };
      devTools = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Per-repo direnv snippet. If set, source/<name>/.envrc is generated with this content (after source_up). Null = no per-repo .envrc.";
      };
    };
  });

  # A Tailscale "network" a project/group belongs to. Consumed by
  # features/fluteos/tailnets (registry + waybar switcher).
  tailnetType = lib.types.submodule {
    options = {
      account = lib.mkOption {
        type = lib.types.str;
        description = "Profile id for `tailscale switch <account>` (the locally-named login profile for this tailnet).";
      };
      domain = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Tailnet MagicDNS domain (e.g. tailf2f3a5.ts.net), used to verify the active profile.";
      };
      displayName = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Label for the switcher menu/widget; null → project/group displayName.";
      };
      icon = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Icon for the switcher; null → project/group icon.";
      };
    };
  };

  groupType = lib.types.submodule ({ name, ... }: {
    options = {
      name = lib.mkOption {
        type = lib.types.str;
        default = name;
        description = "Group directory name (kebab-case). Defaults to attribute key.";
      };
      displayName = lib.mkOption {
        type = lib.types.str;
        default = name;
        description = "Human-readable name for menus";
      };
      gitUserName = lib.mkOption {
        type = lib.types.str;
        default = systemUser.realName;
        description = "Git user.name for this group. Defaults to features.base.system.user.realName.";
      };
      gitUserEmail = lib.mkOption {
        type = lib.types.str;
        default = systemUser.email;
        description = "Git user.email for this group. Defaults to features.base.system.user.email.";
      };
      logo = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "ASCII art logo printed on direnv load";
      };
      icon = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Icon (emoji or Nerd Font glyph) shown in waybar / which-key";
      };
      firefoxProfile = lib.mkOption {
        type = lib.types.nullOr (lib.types.submodule {
          freeformType = lib.types.attrs;
          options = {
            iconAssets = lib.mkOption {
              type = lib.types.attrsOf lib.types.path;
              default = {};
              description = "Icons placed under ~/.mozilla/firefox/<groupKey>/chrome/icons/";
            };
          };
        });
        default = null;
        description = "If non-null, a Firefox profile is created for this group; the value is merged into programs.firefox.profiles.<key>.";
      };
      sshKeySource = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "projects/acme/credentials/id_ed25519";
        description = ''
          SSH private key for this group's git remotes, as a STRING path —
          absolute, or relative to `features.fluteos.projects.secretsRoot`.

          Deliberately not `types.path`: a Nix path would be copied into
          /nix/store, which is world-readable, so the key would be published to
          every user of the machine. The file is read at activation time instead
          and never enters the store.
        '';
      };
      sshKeySourcePub = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "projects/acme/credentials/id_ed25519.pub";
        description = "Public half of `sshKeySource`. Same string-path rule.";
      };
      devTools = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Group-wide direnv snippet (e.g., 'use nix -p ...'). Inherited by projects via direnv source_up.";
      };
      agentCommand = lib.mkOption {
        type = lib.types.enum [ "opencode" "claude" ];
        default = "claude";
        description = "Default agent binary for projects in this group";
      };
      extraEnvrc = lib.mkOption {
        type = lib.types.lines;
        default = "";
        description = "Extra direnv lines appended to the group .envrc (after devTools and dotenv loading). Inherited by projects via direnv source_up_if_exists.";
      };
      tailnet = lib.mkOption {
        type = lib.types.nullOr tailnetType;
        default = null;
        description = "Tailscale network shared by this group's projects (inherited unless a project overrides). Null = none.";
      };
    };
  });

  projectType = lib.types.submodule ({ name, ... }: {
    options = {
      name = lib.mkOption {
        type = lib.types.str;
        default = name;
        description = "Project directory name (kebab-case). Defaults to attribute key.";
      };
      displayName = lib.mkOption {
        type = lib.types.str;
        default = name;
        description = "Human-readable name for menus";
      };
      group = lib.mkOption {
        type = lib.types.str;
        description = "Key of the group this project belongs to (must reference an existing groups.<g>).";
      };

      repos = lib.mkOption {
        type = lib.types.attrsOf repoType;
        default = {};
        description = "Repos that live under <project>/source/<repo-name>/. Single-repo projects: one entry. Empty = no clone, project is workspace-only.";
      };

      # Subfolders — created by activation if true
      agent = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Scaffold agent/ folder with CLAUDE.md and .claude/skills/";
      };
      docs = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Scaffold docs/ folder (docsify root)";
      };
      resources = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Scaffold resources/ folder (empty, for user assets)";
      };

      # Tooling — null = inherit from group
      devTools = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Project-level direnv snippet. Null inherits from group. Project value REPLACES group's (does not append).";
      };
      python = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Auto-create .venv at source/<primaryRepo>/.venv and source-activate it via direnv";
      };
      extraEnvrc = lib.mkOption {
        type = lib.types.lines;
        default = "";
        description = "Extra direnv lines appended to project .envrc";
      };
      docsPort = lib.mkOption {
        type = lib.types.nullOr lib.types.int;
        default = null;
        description = "Port for the per-project docsify server (fluteos-docs-serve). Null = no docs server.";
      };

      # Workspace
      workspace = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "If true, project appears as <group>:<project> workspace";
      };
      sessionApps = lib.mkOption {
        type = lib.types.listOf sessionAppType;
        default = [];
        description = "Apps to launch on workspace open. Empty → just open a terminal in cwd.";
      };
      browserProfile = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Firefox profile override; null inherits from group (group displayName) or default";
      };
      agentCommand = lib.mkOption {
        type = lib.types.nullOr (lib.types.enum [ "opencode" "claude" ]);
        default = null;
        description = "Project-level agent binary; null inherits from group";
      };
      icon = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Icon override; null inherits from group";
      };
      logo = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "ASCII-art logo override; null inherits from group";
      };
      tailnet = lib.mkOption {
        type = lib.types.nullOr tailnetType;
        default = null;
        description = "Tailscale network bound to this project; null inherits from group. Switching to this project's workspace auto-switches to this tailnet.";
      };
    };
  });

  # Compute effective merge (group defaults + project overrides) for one project
  mkEffective = pId: p:
    let
      groups = config.features.fluteos.projects.groups;
      # Throw early with a helpful message — the assertion in `config.assertions`
      # also catches this, but assertions only fire after evaluation, so without
      # this throw the user sees a raw `attribute 'foo' missing` instead.
      g =
        if groups ? "${p.group}"
        then groups.${p.group}
        else throw "Project '${pId}' references undefined group '${p.group}'. Defined groups: ${
          lib.concatStringsSep ", " (lib.attrNames groups)
        }";
      projectDir = "${rootDir}/${g.name}/${p.name}";
      repoNames = lib.attrNames p.repos;
      primaryByFlag = lib.findFirst (n: p.repos.${n}.primary) null repoNames;
      effPrimaryRepo =
        if lib.length repoNames == 1 then lib.head repoNames
        else primaryByFlag;
    in {
      pId = pId;
      name = p.name;
      displayName = p.displayName;
      group = g;
      repos = p.repos;
      primaryRepo = effPrimaryRepo;

      gitUserName  = g.gitUserName;
      gitUserEmail = g.gitUserEmail;
      devTools     = if p.devTools     != null then p.devTools     else g.devTools;
      agentCommand = if p.agentCommand != null then p.agentCommand else g.agentCommand;
      icon         = if p.icon         != null then p.icon         else g.icon;
      logo         = if p.logo         != null then p.logo         else g.logo;
      tailnet      = if p.tailnet      != null then p.tailnet      else g.tailnet;
      browserProfile =
        if p.browserProfile != null then p.browserProfile
        else if g.firefoxProfile != null then g.displayName
        else defaultBrowserProfile;

      python = p.python;
      extraEnvrc = p.extraEnvrc;
      docsPort = p.docsPort;
      workspace = p.workspace;
      sessionApps = p.sessionApps;
      agent = p.agent;
      docs = p.docs;
      resources = p.resources;

      dir          = projectDir;
      sourceDir    = "${projectDir}/source";
      agentDir     = "${projectDir}/agent";
      docsDir      = "${projectDir}/docs";
      resourcesDir = "${projectDir}/resources";
    };
in
{
  options.features.fluteos.projects = {
    rootDir = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/Projects";
      description = "Root directory under which group/project clones live.";
    };

    secretsRoot = lib.mkOption {
      type = lib.types.str;
      default = "";
      example = "/home/you/fluteos-personal";
      description = ''
        Absolute path, on the running machine, of the directory holding group
        credentials. Relative `sshKeySource` values are resolved against it.

        A string and not a path on purpose: everything Nix addresses as a path
        is copied into the world-readable /nix/store, so secrets must be located
        at activation time instead. Empty (the default) means no credentials are
        installed — a warning is printed for each group that wanted one.
      '';
    };

    defaultBrowserProfile = lib.mkOption {
      type = lib.types.str;
      default = "Default";
      example = "AKD";
      description = ''
        Firefox profile name shown when no group/project profile applies. The
        default used to be the owner's initials, so every stranger's browser
        displayed a profile named after someone else.
      '';
    };

    groups = lib.mkOption {
      type = lib.types.attrsOf groupType;
      default = {};
      description = "Lightweight defaults provider. Projects reference a group via projects.<p>.group.";
    };

    projects = lib.mkOption {
      type = lib.types.attrsOf projectType;
      default = {};
      description = "Flat list of projects. Each references a group and lists one or more repos.";
    };

    effective = lib.mkOption {
      type = lib.types.attrsOf lib.types.attrs;
      readOnly = true;
      description = "Computed per-project merge of group defaults + project overrides + path resolution. Single source of truth for all consumers (workspaces registry, sessions, etc.).";
    };
  };

  config = {
    # Materialize effective view
    features.fluteos.projects.effective =
      lib.mapAttrs mkEffective config.features.fluteos.projects.projects;

    # Schema-level invariants
    assertions =
      let
        groups = config.features.fluteos.projects.groups;
        projects = config.features.fluteos.projects.projects;
      in
      # Every project's group must exist
      (lib.mapAttrsToList (pId: p: {
        assertion = groups ? "${p.group}";
        message = "Project '${pId}' references undefined group '${p.group}'. Defined groups: ${
          lib.concatStringsSep ", " (lib.attrNames groups)
        }";
      }) projects)
      ++
      # At most one repo per project may have primary=true
      (lib.mapAttrsToList (pId: p: {
        assertion = lib.length (lib.filter (r: r.primary) (lib.attrValues p.repos)) <= 1;
        message = "Project '${pId}' has more than one repo with primary=true.";
      }) projects)
      ++
      # python venv needs an unambiguous host repo: exactly one repo, or one
      # repo flagged primary=true.
      (lib.mapAttrsToList (pId: p:
        let
          repoCount = lib.length (lib.attrNames p.repos);
          hasPrimary = (lib.length (lib.filter (r: r.primary) (lib.attrValues p.repos))) >= 1;
        in {
          assertion = !p.python || repoCount == 1 || hasPrimary;
          message = "Project '${pId}' has python=true with ${toString repoCount} repos and none marked primary=true. Mark one repo with primary=true.";
        }) projects);
  };
}
