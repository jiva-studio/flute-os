{ config, pkgs, lib, ... }:
let
  groups = config.features.fluteos.projects.groups;
  rootDir = config.features.fluteos.projects.rootDir;
  secretsRoot = config.features.fluteos.projects.secretsRoot;
  defaultBrowserProfile = config.features.fluteos.projects.defaultBrowserProfile;

  # Activation names must be safe shell identifiers; attribute keys may contain dashes.
  safeId = lib.replaceStrings [ "-" ] [ "_" ];

  # Generate logo files for groups that have logos
  logoFiles = lib.mapAttrs' (id: g: {
    name = "Projects/${g.name}/.config/logo.txt";
    value.text = g.logo;
  }) (lib.filterAttrs (_: g: g.logo != "") groups);

  # Generate .envrc content for groups (identity + SSH + browser + group devTools).
  # Project-level .envrc inherits via direnv source_up_if_exists.
  mkEnvrcContent = g: ''
${lib.optionalString (g.devTools != "") "${g.devTools}\n"}
# Workspace identity (group-level; project .envrc adds WORKSPACE_PROJECT/ID/CWD/...)
export WORKSPACE_GROUP="${g.name}"
# Where this machine keeps its credentials. Group snippets read secrets from
# here at runtime; nothing secret may be addressed as a Nix path.
export FLUTEOS_SECRETS_ROOT="${secretsRoot}"
export WORKSPACE_BROWSER_PROFILE="${if g.firefoxProfile != null then g.displayName else defaultBrowserProfile}"

# Git config via environment variables
export GIT_CONFIG_COUNT=2
export GIT_CONFIG_KEY_0=user.name
export GIT_CONFIG_VALUE_0="${g.gitUserName}"
export GIT_CONFIG_KEY_1=user.email
export GIT_CONFIG_VALUE_1="${g.gitUserEmail}"

# SSH key (if exists)
SSH_KEY=$(find "${rootDir}/${g.name}/.config/ssh" -name "id_*" ! -name "*.pub" 2>/dev/null | head -1)
if [ -n "$SSH_KEY" ] && [ -f "$SSH_KEY" ]; then
  export GIT_SSH_COMMAND="ssh -i $SSH_KEY -o IdentitiesOnly=yes"
fi

# Load group secrets (if exists)
dotenv_if_exists .config/secrets.env

${lib.optionalString (g.extraEnvrc != "") "${g.extraEnvrc}\n"}
# Print logo only when this .envrc is the one the user cd'd into directly
# (not when source_up_if_exists is loading us from a deeper project/repo).
# direnv exposes DIRENV_DIR with a leading "-" prefix.
if [ "''${DIRENV_DIR#-}" = "${rootDir}/${g.name}" ]; then
  cat "${rootDir}/${g.name}/.config/logo.txt" 2>/dev/null || true
fi
'';

  # Write .envrc as regular file (not symlink) so direnv can update mtime
  envrcActivations = lib.mapAttrs' (id: g: {
    name = "writeEnvrcGroup_${safeId id}";
    value = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      mkdir -p "${rootDir}/${g.name}"
      [ -L "${rootDir}/${g.name}/.envrc" ] && rm "${rootDir}/${g.name}/.envrc"
      cat > "${rootDir}/${g.name}/.envrc" << 'ENVRC_EOF'
${mkEnvrcContent g}
ENVRC_EOF
    '';
  }) groups;

  # Resolve a group credential to an absolute path on the running machine.
  # Never a Nix path: /nix/store is world-readable, so a key addressed as a path
  # would be copied there in plaintext and published to every local user.
  resolveSecret = rel:
    if lib.hasPrefix "/" rel then rel else "${secretsRoot}/${rel}";

  # Install one credential at activation time, reading it from disk. Absent file
  # or unset secretsRoot is reported, not fatal — a machine that has not been
  # given its secrets yet must still activate.
  installSecret = groupName: rel: mode: ''
    ${if secretsRoot == "" && !(lib.hasPrefix "/" rel) then ''
      echo "  [${groupName}] SSH key '${rel}': skipped — features.fluteos.projects.secretsRoot is not set" >&2
    '' else ''
      _src="${resolveSecret rel}"
      if [ -r "$_src" ]; then
        install -m ${mode} "$_src" "${rootDir}/${groupName}/.config/ssh/$(basename "$_src")"
      else
        echo "  [${groupName}] SSH key '$_src': not readable — skipped" >&2
      fi
      unset _src
    ''}
  '';

  # SSH key setup activations
  sshActivations = lib.mapAttrs' (id: g: {
    name = "setupGroup_${safeId id}";
    value = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      echo "  [${g.name}] Creating .config/ssh directory"
      mkdir -p "${rootDir}/${g.name}/.config/ssh"
      ${lib.optionalString (g.sshKeySource != null) (installSecret g.name g.sshKeySource "600")}
      ${lib.optionalString (g.sshKeySourcePub != null) (installSecret g.name g.sshKeySourcePub "644")}
    '';
  }) groups;

  # Direnv allow activations
  direnvActivations = lib.mapAttrs' (id: g: {
    name = "allowDirenvGroup_${safeId id}";
    value = lib.hm.dag.entryAfter [ "writeEnvrcGroup_${safeId id}" ] ''
      echo "  [${g.name}] Allowing direnv"
      ${pkgs.direnv}/bin/direnv allow "${rootDir}/${g.name}" 2>/dev/null || true
    '';
  }) groups;
in
{
  home.file = logoFiles;
  home.activation = sshActivations // envrcActivations // direnvActivations;
}
