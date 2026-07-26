{ ... }:
{
  features.fluteos.projects.projects.project-name = {
    group = "group-name";              # references groups.<g> defined in group.nix
    displayName = "Project Name";

    repos = {
      project-name = {                 # source/<r>/ folder name
        url = "git@github.com:org/repo.git";
        # branch = "main";              # checkout this branch after clone
        # sparse = [ "subdir1" "subdir2" ];  # sparse-checkout these paths only
        # primary = true;               # for multi-repo projects: where python venv lives, etc.
        # devTools = "use nix -p nodejs_20";  # generates source/<r>/.envrc
      };
    };

    # devTools = "use nix -p nodejs";   # project-level direnv snippet (overrides group's)
    # python = true;                    # auto-create .venv at source/<primaryRepo>/.venv
    # workspace = true;                 # default true: appears as "<group>:<project>" workspace
    # extraEnvrc = '' export FOO=bar; '';
    # icon = "📚";
    # logo = ''…'';
    # agent = false;                    # default true: scaffold agent/CLAUDE.md + .claude/skills/
    # docs = false;                     # default true: scaffold docs/ for docsify
    # resources = false;                # default true: scaffold resources/ folder
    # sessionApps = [ /* see options.nix sessionAppType */ ];
    # agentCommand = "claude";          # overrides group default
    # browserProfile = null;            # null inherits from group's firefoxProfile, or default
  };
}
