# Per-project Claude Code agent context. Bootstraps <project>/agent/ with
# CLAUDE.md (fluteos-managed) + 5 default skills (namespace-action format).
{ lib, config, ... }:
{
  options.features.fluteos.agent-context = {
    enable = lib.mkEnableOption "Per-project agent context bootstrap (CLAUDE.md + skills)";
  };

  config = lib.mkIf config.features.fluteos.agent-context.enable {
    home-manager.users.${config.features.base.system.user.name} = { pkgs, lib, ... }:
    let
      runtimeDeps = lib.makeBinPath [ pkgs.git pkgs.coreutils pkgs.gnused pkgs.gawk pkgs.findutils pkgs.gnugrep ];

      # Skill templates live as separate .md files. Bootstrap copies them into
      # <project>/agent/.claude/skills/<name>/SKILL.md if not already present.
      skillsDir = ./skills;

      bootstrap = pkgs.writeShellScriptBin "fluteos-agent-context-bootstrap" ''
        export PATH="${runtimeDeps}:$PATH"
        export SKILLS_SRC_DIR="${skillsDir}"
        bash ${./fluteos-agent-context-bootstrap.sh} "$@"
      '';

      # Move a project's agent skills/docs/MCP into a source/<repo> git tree
      # (standard conventions) and symlink them back, so they become trackable.
      link = pkgs.writeShellScriptBin "fluteos-agent-link" ''
        export PATH="${runtimeDeps}:$PATH"
        bash ${./fluteos-agent-link.sh} "$@"
      '';
    in
    {
      home.packages = [ bootstrap link ];
    };
  };
}
