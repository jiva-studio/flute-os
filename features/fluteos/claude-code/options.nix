# features.fluteos.claude-code — options.
#
# Split out of default.nix along the same line as features/fluteos/ptt: schema
# here, assembly there. The MCP registry is the reason — it used to be 194 lines
# of copy-pasted activation shell, one `if [ -s secret ]; then jq -n --argjson
# base … ` block per server, which meant an eighth server cost twenty lines of
# shell and a host could contribute none at all. Worse, the servers themselves
# were the author's: six marketing accounts every user was told to skip on every
# activation, and a code-search server hardwired to two loopback ports that only
# exist on one laptop.
{ lib, ... }:
let
  mcpServerType = lib.types.submodule {
    options = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Register this server. Set false to drop one the product ships.";
      };

      command = lib.mkOption {
        type = lib.types.str;
        default = "npx";
        description = "Executable Claude Code launches for this server.";
      };

      args = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        example = [ "-y" "acme-mcp-server" ];
        description = "Arguments passed to `command`.";
      };

      env = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = { };
        example = { ACME_API_KEY = "%{acme-api-key}"; };
        description = ''
          Environment for the server process. A value may reference a secret as
          `%{<file>}`, naming a file under `secretsDir`; the substitution happens
          at activation time with the file's contents, so a credential is never
          part of a /nix/store path. Multi-line values (a PEM key) are safe —
          the value is passed through `jq --arg`, not through the shell.
        '';
      };

      secrets = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        example = [ "acme-client-id" "acme-client-secret" ];
        description = ''
          Files under `secretsDir` that must ALL exist and be non-empty for this
          server to register. A server missing its secrets is skipped with a
          warning and takes nothing else down with it.

          Every `%{…}` used in `env` should be listed here; one that is not will
          substitute as empty rather than skipping the server.
        '';
      };

      hint = lib.mkOption {
        type = lib.types.str;
        default = "";
        example = "Mint a token at https://acme.example/settings/tokens.";
        description = "Extra line printed after the skip warning, for how to obtain the credential.";
      };
    };
  };
in
{
  options.features.fluteos.claude-code = {
    enable = lib.mkEnableOption "Claude Code CLI with MCP servers";

    extraSkills = lib.mkOption {
      type = lib.types.attrsOf lib.types.path;
      default = { };
      example = lib.literalExpression ''
        { my-server = ../../claude-skills/my-server/SKILL.md; }
      '';
      description = ''
        Additional user-global Claude skills, as skill name → SKILL.md path.
        Installed to ~/.claude/skills/<name>/SKILL.md and available in every
        session.

        The product ships only skills that document FluteOS itself. A skill
        describing your own machines — host names, addresses, accounts, checkout
        paths — is personal configuration and belongs here; one such runbook used
        to be installed into every user's skill directory.
      '';
    };


    marketplaces = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        freeformType = lib.types.anything;
        options.source = lib.mkOption {
          type = lib.types.anything;
          example = lib.literalExpression ''{ source = "github"; repo = "owner/repo"; }'';
          description = "Marketplace source, in Claude Code's own shape — a github repo, a git url, or a local path.";
        };
      });
      default = { };
      example = lib.literalExpression ''
        {
          revdiff = {
            source = { source = "github"; repo = "umputun/revdiff"; };
            autoUpdate = true;
          };
        }
      '';
      description = ''
        Plugin marketplaces registered in ~/.claude/settings.json
        (`extraKnownMarketplaces`), keyed by marketplace name. Freeform, so any
        key Claude Code understands on an entry — `autoUpdate` and whatever
        follows it — passes through without this module tracking its schema.

        Registering a marketplace only makes its catalogue known; enabling one of
        its plugins is `plugins` below, and a plugin from an external source is
        still fetched by `claude plugin install` on first use.
      '';
    };

    plugins = lib.mkOption {
      type = lib.types.attrsOf lib.types.bool;
      default = { };
      example = lib.literalExpression ''{ "revdiff@revdiff" = true; }'';
      description = ''
        Plugins to enable or disable, keyed `<plugin>@<marketplace>`, written to
        `enabledPlugins`. A marketplace they come from must be in `marketplaces`
        above, or Claude Code has nowhere to look them up.
      '';
    };
    secretsDir = lib.mkOption {
      type = lib.types.str;
      default = "$HOME/.config/fluteos/secrets";
      description = ''
        Directory holding MCP credentials, one file per secret, mode 0600. Read
        at activation time; never a Nix path, so nothing here reaches
        /nix/store. Shell expansions such as `$HOME` are allowed.
      '';
    };

    mcpServers = lib.mkOption {
      type = lib.types.attrsOf mcpServerType;
      default = { };
      example = lib.literalExpression ''
        {
          acme = {
            args = [ "-y" "acme-mcp-server" ];
            env.ACME_API_KEY = "%{acme-api-key}";
            secrets = [ "acme-api-key" ];
            hint = "Key from https://acme.example/api-keys.";
          };
        }
      '';
      description = ''
        MCP servers registered into ~/.claude.json on activation, keyed by the
        name Claude Code will show.

        FluteOS ships the two that are about writing software — semantic code
        search and web research. Anything tied to an account of yours (a social
        network, an analytics property, a company API) is configuration, not
        product: declare it here from your own host or overlay.
      '';
    };

    codeSearch = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Register the `claude-context` MCP: semantic code search across every
          project, keyed per repository by path hash, so one registration serves
          all checkouts. Needs an Ollama endpoint for embeddings and a Milvus
          endpoint to store them — both may be remote.
        '';
      };
      ollamaHost = lib.mkOption {
        type = lib.types.str;
        default = "http://127.0.0.1:11434";
        example = "http://127.0.0.1:18001";  # a loopback forwarder to another host
        description = ''
          Ollama endpoint that computes the embeddings. Defaults to a local
          Ollama on its standard port. This used to be hardcoded to a loopback
          forwarder that exists on exactly one machine, so every other install
          got a permanently broken MCP with no option to fix it.
        '';
      };
      milvusAddress = lib.mkOption {
        type = lib.types.str;
        default = "127.0.0.1:19530";
        example = "127.0.0.1:18002";
        description = "Milvus endpoint storing the vectors. Defaults to a local Milvus on its standard port.";
      };
      embeddingModel = lib.mkOption {
        type = lib.types.str;
        default = "nomic-embed-text";
        example = "code-embed";
        description = ''
          Ollama model used for embeddings, and it must be pulled on that Ollama.
          The default is a public model anyone can `ollama pull`; a locally
          derived one (`ollama create`) is a value for a host to state.
        '';
      };
      embeddingDimension = lib.mkOption {
        type = lib.types.ints.positive;
        default = 768;
        description = "Vector width `embeddingModel` produces. Must match the model, or Milvus rejects the inserts.";
      };
      embeddingBatchSize = lib.mkOption {
        type = lib.types.ints.positive;
        default = 64;
        description = "Chunks per embedding request.";
      };
    };
  };
}
