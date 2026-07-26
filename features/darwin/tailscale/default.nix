# Tailscale on nix-darwin.
#
# nix-darwin's `services.tailscale` only installs the package and runs the
# `tailscaled` daemon — it does NOT `tailscale up` / authenticate / set the
# hostname / enable SSH. So this module adds:
#   1. an activation step that installs a git-crypted reusable auth key to an
#      absolute root-owned path (NOT interpolated into a script — that would
#      leak it into the world-readable /nix/store), mirroring the
#      github-runner secret-install pattern;
#   2. a system launchd daemon that waits for tailscaled, then idempotently
#      brings the node up with that key (retried on failure via SuccessfulExit).
#
# Single-tailnet hosts only (the Macs join the personal tailnet). yoga keeps
# the richer NixOS module and manual fast-switch login.
{ lib, config, pkgs, ... }:
let
  cfg = config.features.darwin.tailscale;
  ts = config.services.tailscale.package;
  authKeyDest = "/etc/tailscale/authkey";

  upScript = pkgs.writeShellScript "tailscale-up" ''
    set -u
    # Wait for tailscaled to answer (daemon up; --json returns even when logged out).
    until ${ts}/bin/tailscale status --json >/dev/null 2>&1; do sleep 2; done

    # Already authenticated → nothing to do.
    if ${ts}/bin/tailscale status --json | ${pkgs.jq}/bin/jq -e '.BackendState == "Running"' >/dev/null 2>&1; then
      echo "tailscale already up — skipping"
      exit 0
    fi

    # Only bring up with a REAL key. On a clean git checkout nix copies the
    # git-crypt CIPHERTEXT (flakes read git blobs, not the smudged working tree),
    # so the key may be binary garbage — never `up` with that, it would log out an
    # already-authenticated node. A node, once up, stays up across rebuilds.
    if [ ! -r ${authKeyDest} ] || ! head -c6 ${authKeyDest} 2>/dev/null | grep -q '^tskey-'; then
      echo "no valid auth key at ${authKeyDest} — skipping (run 'tailscale up' manually once)"
      exit 0
    fi

    # Exit code propagates → launchd retries (KeepAlive.SuccessfulExit = false).
    ${ts}/bin/tailscale up \
      --authkey="$(cat ${authKeyDest})" \
      --hostname="${cfg.hostname}" \
      ${lib.optionalString (cfg.tags != []) "--advertise-tags=${lib.concatStringsSep "," cfg.tags}"} \
      ${lib.optionalString cfg.ssh "--ssh"} \
      --accept-routes=false
  '';
in
{
  options.features.darwin.tailscale = {
    enable = lib.mkEnableOption "Tailscale on this Mac (joins the personal tailnet)";

    authKeyPath = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        Path to a git-crypted file holding a reusable, pre-approved Tailscale
        auth key. Installed to ${authKeyDest} (mode 600, root) at activation and
        used for an unattended `tailscale up`. Null → no automated bring-up
        (log in manually with `tailscale up`).
      '';
    };

    hostname = lib.mkOption {
      type = lib.types.str;
      default = config.features.darwin.system.hostname;
      description = "Tailscale node name (defaults to the system hostname).";
    };

    ssh = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable Tailscale SSH (`tailscale up --ssh`) on this node.";
    };

    tags = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "tag:ci" ];
      description = ''
        ACL tags advertised by this node (`--advertise-tags`). Used for in-tailnet
        segmentation: e.g. tag:ci for the untrusted CI host, tag:personal for
        personal machines — ACLs then isolate them. The auth key must be allowed
        to advertise these tags (tagged key, or tagOwners grants the key's owner).
        Tagging also disables node-key expiry for the device.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    services.tailscale.enable = true;

    # Install the auth key off the Nix store (absolute, root-owned) — but ONLY if
    # the source is a real key. On a clean git checkout nix copies the git-crypt
    # CIPHERTEXT (flakes read git blobs, not the smudged working tree), so the
    # source can be binary garbage; never clobber a good /etc/tailscale/authkey
    # (or a live login) with that. Real keys start with "tskey-".
    system.activationScripts.extraActivation.text = lib.mkAfter (
      lib.optionalString (cfg.authKeyPath != null) ''
        install -d -m 700 -o root -g wheel /etc/tailscale
        if head -c6 ${cfg.authKeyPath} 2>/dev/null | grep -q '^tskey-'; then
          install -m 600 -o root -g wheel ${cfg.authKeyPath} ${authKeyDest}
        else
          echo "tailscale: source auth key is not plaintext (git-crypt locked / clean checkout) — leaving ${authKeyDest} untouched" >&2
        fi
      ''
    );

    launchd.daemons.tailscale-autoconnect = {
      command = "${upScript}";
      serviceConfig = {
        RunAtLoad = true;
        # Retry only while the bring-up fails; stop once it exits 0.
        KeepAlive = { SuccessfulExit = false; };
        StandardOutPath = "/var/log/tailscale-autoconnect.log";
        StandardErrorPath = "/var/log/tailscale-autoconnect.err";
      };
    };

    environment.systemPackages = [ ts ];
  };
}
