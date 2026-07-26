# features.darwin.vector-backend — local semantic-search backend for
# claude-context (the MCP that gives the agent codebase/doc search).
#
# Runs entirely inside the personal contour on this Mac — nothing leaves to
# OpenRouter/Zilliz:
#   * Ollama   — embeddings (Metal-accelerated), bound on the LAN at :11434.
#   * Milvus   — vector store, standalone (milvus+etcd+minio) inside a colima
#                Linux VM. colima forwards its published 19530 to the mac host
#                loopback; a socat relay re-exposes it on the LAN at :19531.
#
# The claude-context MCP itself runs on the Linux box (yoga), reads the repo
# there, and connects here over the LAN — mirroring the denoiser/transcriber
# pattern. yoga's .mcp.json points at:
#   OLLAMA_HOST   = http://<mac-lan-ip>:11434
#   MILVUS_ADDRESS= <mac-lan-ip>:19531
#
# Everything is a launchd *user* agent (not a daemon) so Ollama gets a GUI
# session for Metal and colima runs as the login user. The mac sleeps when
# idle (features.darwin.system.power = "wake-on-network"); the backend is
# session-time, not 24/7 — the index is rebuildable, so that's fine.
{ lib, config, pkgs, ... }:
let
  cfg = config.features.darwin.vector-backend;

  binPath = lib.makeBinPath [
    pkgs.ollama pkgs.colima pkgs.docker pkgs.docker-compose
    pkgs.socat pkgs.curl pkgs.coreutils pkgs.gnugrep
  ];
  # colima/lima shell out to system ssh; keep /usr/bin & /bin on PATH.
  fullPath = "${binPath}:/usr/bin:/bin:/usr/sbin:/sbin";

  ollamaServe = pkgs.writeShellScript "vb-ollama-serve" ''
    exec ${pkgs.ollama}/bin/ollama serve
  '';

  ollamaModel = pkgs.writeShellScript "vb-ollama-model" ''
    export OLLAMA_HOST="127.0.0.1:${toString cfg.ollamaPort}"
    OLLAMA="${pkgs.ollama}/bin/ollama"
    GREP="${pkgs.gnugrep}/bin/grep"
    # wait for the server, then ensure the embedding model is present
    for _ in $(seq 1 60); do
      "$OLLAMA" list >/dev/null 2>&1 && break
      sleep 2
    done
    ${if cfg.baseModel == null then ''
      # Plain registry model — pull it.
      if ! "$OLLAMA" list | "$GREP" -q '${cfg.model}'; then
        "$OLLAMA" pull '${cfg.model}'
      fi
    '' else ''
      # Derived model (e.g. code-embed): pull the base, then `ollama create`
      # '${cfg.model}' from a Modelfile that widens num_ctx so large chunks embed.
      if ! "$OLLAMA" list | "$GREP" -q '${cfg.baseModel}'; then
        "$OLLAMA" pull '${cfg.baseModel}'
      fi
      if ! "$OLLAMA" list | "$GREP" -q '${cfg.model}'; then
        MF="$(${pkgs.coreutils}/bin/mktemp)"
        printf 'FROM ${cfg.baseModel}\n${lib.optionalString (cfg.numCtx != null) "PARAMETER num_ctx ${toString cfg.numCtx}"}\n' > "$MF"
        "$OLLAMA" create '${cfg.model}' -f "$MF"
        ${pkgs.coreutils}/bin/rm -f "$MF"
      fi
    ''}
  '';

  milvusUp = pkgs.writeShellScript "vb-milvus-up" ''
    set -eu
    export PATH="${fullPath}"
    : "''${HOME:=/Users/${cfg.user}}"
    # 1. Bring up the colima VM (vz = Apple Virtualization, native on M-series).
    if ! colima status >/dev/null 2>&1; then
      colima start \
        --vm-type vz --mount-type virtiofs \
        --cpu ${toString cfg.colimaCpu} \
        --memory ${toString cfg.colimaMemory} \
        --disk ${toString cfg.colimaDisk}
    fi
    # 2. Talk to colima's docker, bring up Milvus standalone.
    export DOCKER_HOST="unix://$HOME/.colima/default/docker.sock"
    docker-compose -f ${./milvus-compose.yml} -p milvus up -d
  '';

  # Re-expose Milvus (forwarded by colima to host loopback :19530) on the LAN.
  # Listens on a *different* port to avoid colliding with the loopback forward.
  milvusRelay = pkgs.writeShellScript "vb-milvus-relay" ''
    exec ${pkgs.socat}/bin/socat \
      TCP-LISTEN:${toString cfg.lanPort},fork,reuseaddr \
      TCP:127.0.0.1:${toString cfg.milvusPort}
  '';

  logDir = "/Users/${cfg.user}/Library/Logs/vector-backend";
  agentEnv = { PATH = fullPath; };
in
{
  options.features.darwin.vector-backend = {
    enable = lib.mkEnableOption "Local Ollama + Milvus backend for claude-context";

    user = lib.mkOption {
      type = lib.types.str;
      example = "akd";
      description = "Login user that owns the launchd agents (needs a GUI session for Metal).";
    };

    model = lib.mkOption {
      type = lib.types.str;
      default = "bge-m3";
      description = "Ollama embedding model name to ensure on start (multilingual — good for RU docs). When `baseModel` is set this is the *derived* model created locally.";
    };

    baseModel = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        If set, `model` is built locally via `ollama create` from a Modelfile
        `FROM <baseModel>` instead of pulled directly. Use for custom aliases
        such as `code-embed` (FROM nomic-embed-text). Null → plain `ollama pull`.
      '';
    };

    numCtx = lib.mkOption {
      type = lib.types.nullOr lib.types.int;
      default = null;
      description = ''
        `num_ctx` PARAMETER baked into the derived model (only with `baseModel`).
        e.g. 8192 to widen nomic-embed-text's 2048 default so large code chunks
        embed without truncation.
      '';
    };

    ollamaPort = lib.mkOption { type = lib.types.port; default = 11434; };
    milvusPort = lib.mkOption {
      type = lib.types.port; default = 19530;
      description = "Milvus gRPC port as forwarded by colima onto the host loopback.";
    };
    lanPort = lib.mkOption {
      type = lib.types.port; default = 19531;
      description = "LAN-facing port the socat relay listens on (-> 127.0.0.1:milvusPort).";
    };

    colimaCpu = lib.mkOption { type = lib.types.int; default = 4; };
    colimaMemory = lib.mkOption { type = lib.types.int; default = 6; description = "colima VM RAM, GB."; };
    colimaDisk = lib.mkOption { type = lib.types.int; default = 30; description = "colima VM disk, GB."; };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      pkgs.ollama pkgs.colima pkgs.docker pkgs.docker-compose pkgs.socat
    ];

    # Ollama server — bound on the LAN so yoga can reach it.
    launchd.user.agents.vb-ollama = {
      serviceConfig = {
        ProgramArguments = [ "${ollamaServe}" ];
        EnvironmentVariables = agentEnv // {
          OLLAMA_HOST = "0.0.0.0:${toString cfg.ollamaPort}";
        };
        KeepAlive = true;
        RunAtLoad = true;
        StandardOutPath = "${logDir}/ollama.log";
        StandardErrorPath = "${logDir}/ollama.err";
      };
    };

    # One-shot: ensure the embedding model exists once the server is up.
    launchd.user.agents.vb-ollama-model = {
      serviceConfig = {
        ProgramArguments = [ "${ollamaModel}" ];
        EnvironmentVariables = agentEnv;
        RunAtLoad = true;
        KeepAlive = false;
        StandardOutPath = "${logDir}/ollama-model.log";
        StandardErrorPath = "${logDir}/ollama-model.err";
      };
    };

    # colima VM + Milvus standalone bring-up (idempotent, runs at login/wake).
    launchd.user.agents.vb-milvus = {
      serviceConfig = {
        ProgramArguments = [ "${milvusUp}" ];
        EnvironmentVariables = agentEnv;
        RunAtLoad = true;
        KeepAlive = false;
        # colima first-run pulls a VM image + Milvus images — can take minutes.
        StandardOutPath = "${logDir}/milvus.log";
        StandardErrorPath = "${logDir}/milvus.err";
      };
    };

    # LAN relay for Milvus.
    launchd.user.agents.vb-milvus-relay = {
      serviceConfig = {
        ProgramArguments = [ "${milvusRelay}" ];
        EnvironmentVariables = agentEnv;
        KeepAlive = true;
        RunAtLoad = true;
        StandardOutPath = "${logDir}/milvus-relay.log";
        StandardErrorPath = "${logDir}/milvus-relay.err";
      };
    };

    # Ensure the log dir exists before the agents start.
    #
    # `extraActivation`, not a key of our own: nix-darwin's activation script
    # interpolates a FIXED list of slots (preActivation, extraActivation, users,
    # …, launchd, postActivation). The option type accepts any name, so
    # `vectorBackendLogs` evaluated fine and was never executed — meaning the
    # directory did not exist, and launchd, which opens StandardOutPath before
    # exec'ing, could not spawn any of the four agents on a fresh machine.
    #
    # extraActivation also runs BEFORE the launchd slot, which is what matters:
    # a mkdir inside the runner scripts would be too late.
    system.activationScripts.extraActivation.text = lib.mkAfter ''
      install -d -m 755 -o ${cfg.user} -g staff ${logDir}
    '';
  };
}
