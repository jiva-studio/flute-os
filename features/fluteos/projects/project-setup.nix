# Reads features.fluteos.projects.effective and emits home.activation entries:
# - Scaffold <projectDir>/{agent,docs,resources,source}/
# - For each repo in repos: clone to source/<repo>/, optional repo .envrc
# - Write project .envrc at <projectDir>/.envrc, direnv allow
# - Write per-project logo to <projectDir>/.config/logo.txt
# - Bootstrap agent context (idempotent) and docsify (if missing)
{ pkgs, config, lib, ... }:
let
  projects = config.features.fluteos.projects.effective;

  # Activation names must be safe shell identifiers; attribute keys may contain dashes.
  safeId = lib.replaceStrings [ "-" ] [ "_" ];

  # Per-project activation set
  mkProjectActivations = pId: eff:
    let
      sPid = safeId pId;
      sGid = safeId eff.group.name;

      projectDir = eff.dir;
      sourceDir = eff.sourceDir;
      agentDir = eff.agentDir;
      docsDir = eff.docsDir;
      resourcesDir = eff.resourcesDir;
      sshKeyDir = "${config.features.fluteos.projects.rootDir}/${eff.group.name}/.config/ssh";

      # Guard explicitly: assertions ensure primaryRepo != null when python=true,
      # but if that ever loosens we'd hit a Nix eval error on the interpolation
      # below (the `or` operator only triggers on missing attrs, not null).
      # With this guard, a misconfigured project just gets no venv block.
      pythonEnvrc = lib.optionalString (eff.python && eff.primaryRepo != null) ''

        # Add native libs to LD_LIBRARY_PATH for Python packages with C extensions
        export LD_LIBRARY_PATH="${pkgs.stdenv.cc.cc.lib}/lib:$LD_LIBRARY_PATH"

        # Python virtual environment (lives in source/<primaryRepo>/.venv)
        if [ -d "source/${eff.primaryRepo}" ]; then
          if [ ! -d "source/${eff.primaryRepo}/.venv" ]; then
            (cd "source/${eff.primaryRepo}" && python -m venv .venv)
          fi
          # shellcheck disable=SC1091
          source "source/${eff.primaryRepo}/.venv/bin/activate"
        fi
      '';

      hasLogo = eff.logo != "";

      # Project .envrc — workspace identity + project devTools + bootstrap.
      # Logo is printed only when this .envrc is the deepest one direnv loaded
      # ($DIRENV_DIR matches our path). No state flags needed.
      projectEnvrcContent = ''
        source_up_if_exists

        # Workspace identity (project-level; overrides/extends group-level)
        export WORKSPACE_PROJECT="${eff.name}"
        export WORKSPACE_ID="${eff.group.name}:${eff.name}"
        export WORKSPACE_CWD="${projectDir}"
        export WORKSPACE_SOURCE_DIR="${sourceDir}"
        export WORKSPACE_AGENT_DIR="${agentDir}"
        export WORKSPACE_DOCS_DIR="${docsDir}"
        export WORKSPACE_RESOURCES_DIR="${resourcesDir}"
        # Re-export so a per-project override beats the group-level value from
        # source_up. Terminal-clicked links and direct fluteos-workspace-browser
        # invocations both pick this up.
        export WORKSPACE_BROWSER_PROFILE="${eff.browserProfile}"

        ${lib.optionalString (eff.devTools != "") "${eff.devTools}"}${pythonEnvrc}

        # Project secrets (if exists)
        dotenv_if_exists .config/secrets.env

        # Print logo only at direct project entry (not when a deeper .envrc sourced us).
        ${lib.optionalString hasLogo ''
          if [ "''${DIRENV_DIR#-}" = "${projectDir}" ]; then
            cat "${projectDir}/.config/logo.txt" 2>/dev/null || true
          fi
        ''}

        # Bootstrap agent context if agent/CLAUDE.md missing (idempotent, silent on success).
        # Stderr is appended to a per-user log so failures are diagnosable instead
        # of swallowed by /dev/null. `|| true` keeps direnv from failing the cd.
        ${lib.optionalString eff.agent ''
          BOOTSTRAP_LOG="''${XDG_STATE_HOME:-$HOME/.local/state}/fluteos/bootstrap.log"
          mkdir -p "$(dirname "$BOOTSTRAP_LOG")"
          fluteos-agent-context-bootstrap >/dev/null 2>>"$BOOTSTRAP_LOG" || true
        ''}
        ${lib.optionalString (eff.extraEnvrc != "") "\n${eff.extraEnvrc}"}
      '';

      # Per-repo .envrc generated only if repo.devTools != null. No logo.
      mkRepoEnvrcContent = repoName: repo: ''
        source_up_if_exists

        ${repo.devTools}
      '';

      # === Activations ===

      # 1. Scaffold subfolders
      scaffoldActivation = {
        "scaffoldProject_${sPid}" = lib.hm.dag.entryAfter [ "writeBoundary" "setupGroup_${sGid}" ] ''
          mkdir -p "${sourceDir}"
          ${lib.optionalString eff.agent ''mkdir -p "${agentDir}/.claude/skills"''}
          ${lib.optionalString eff.docs ''mkdir -p "${docsDir}"''}
          ${lib.optionalString eff.resources ''mkdir -p "${resourcesDir}"''}
        '';
      };

      # 2. Clone each repo if missing. Failures (network, auth, missing repo on
      # remote) propagate via non-zero exit so the user sees them in the
      # nixos-rebuild output instead of finding an empty directory hours later.
      cloneActivations = lib.mapAttrs' (repoName: repo: {
        name = "cloneRepo_${sPid}_${safeId repoName}";
        value = lib.hm.dag.entryAfter [ "scaffoldProject_${sPid}" ] ''
          if [ ! -d "${sourceDir}/${repoName}/.git" ]; then
            mkdir -p "${sourceDir}"
            SSH_KEY=$(find "${sshKeyDir}" -name "id_*" ! -name "*.pub" 2>/dev/null | head -1)
            if [ -n "$SSH_KEY" ]; then
              export GIT_SSH_COMMAND="${pkgs.openssh}/bin/ssh -i $SSH_KEY -o IdentitiesOnly=yes"
            fi
            if ! ${pkgs.git}/bin/git clone "${repo.url}" "${sourceDir}/${repoName}"; then
              echo "  [${pId}/${repoName}] git clone failed: ${repo.url}" >&2
              echo "  → check network, SSH key (${sshKeyDir}/id_*), and repo access" >&2
              exit 1
            fi
            ${lib.optionalString (repo.branch != null) ''
              if ! ${pkgs.git}/bin/git -C "${sourceDir}/${repoName}" checkout "${repo.branch}"; then
                echo "  [${pId}/${repoName}] checkout failed: branch '${repo.branch}'" >&2
                exit 1
              fi
            ''}
            ${lib.optionalString (repo.sparse != []) ''
              # Don't overwrite a user-customised sparse-checkout file.
              if [ -s "${sourceDir}/${repoName}/.git/info/sparse-checkout" ]; then
                echo "  [${pId}/${repoName}] sparse-checkout already configured — leaving as-is" >&2
              else
                ${pkgs.git}/bin/git -C "${sourceDir}/${repoName}" sparse-checkout init --cone
                ${pkgs.git}/bin/git -C "${sourceDir}/${repoName}" sparse-checkout set ${lib.concatStringsSep " " repo.sparse}
              fi
            ''}
          fi
        '';
      }) eff.repos;

      # 3. Per-repo .envrc generation (only if devTools set)
      repoEnvrcActivations = lib.mapAttrs' (repoName: repo:
        let sRid = safeId repoName; in {
          name = "writeRepoEnvrc_${sPid}_${sRid}";
          value = lib.hm.dag.entryAfter [ "cloneRepo_${sPid}_${sRid}" ] ''
            if [ -d "${sourceDir}/${repoName}" ]; then
              [ -L "${sourceDir}/${repoName}/.envrc" ] && rm "${sourceDir}/${repoName}/.envrc"
              cat > "${sourceDir}/${repoName}/.envrc" << 'ENVRC_EOF'
${mkRepoEnvrcContent repoName repo}
ENVRC_EOF
              ${pkgs.direnv}/bin/direnv allow "${sourceDir}/${repoName}" 2>/dev/null || true
            fi
          '';
        }
      ) (lib.filterAttrs (_: r: r.devTools != null) eff.repos);

      # 4. Write project .envrc + direnv allow
      projectEnvrcActivation = {
        "writeEnvrcProject_${sPid}" = lib.hm.dag.entryAfter
          ([ "scaffoldProject_${sPid}" ]
            ++ lib.mapAttrsToList (n: _: "cloneRepo_${sPid}_${safeId n}") eff.repos) ''
          mkdir -p "${projectDir}"
          [ -L "${projectDir}/.envrc" ] && rm "${projectDir}/.envrc"
          cat > "${projectDir}/.envrc" << 'ENVRC_EOF'
${projectEnvrcContent}
ENVRC_EOF
        '';

        "allowDirenvProject_${sPid}" = lib.hm.dag.entryAfter [ "writeEnvrcProject_${sPid}" ] ''
          ${pkgs.direnv}/bin/direnv allow "${projectDir}" 2>/dev/null || true
        '';
      };
    in
    scaffoldActivation // cloneActivations // repoEnvrcActivations // projectEnvrcActivation;

  allActivations = lib.foldl' (acc: pId:
    acc // mkProjectActivations pId projects.${pId}
  ) {} (lib.attrNames projects);

  # Per-project logo files (project effective logo, falls back to group logo via mkEffective).
  logoFiles = lib.mapAttrs' (pId: eff: {
    name = "Projects/${eff.group.name}/${eff.name}/.config/logo.txt";
    value.text = eff.logo;
  }) (lib.filterAttrs (_: eff: eff.logo != "") projects);
in
{
  home.activation = allActivations;
  home.file = logoFiles;
}
