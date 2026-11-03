# Separate Claude Code logins, chosen by project group.
#
# Claude keeps its login, settings, MCP list and skills in CLAUDE_CONFIG_DIR
# (~/.claude by default). An account is another such directory: the `claude`
# wrapper points CLAUDE_CONFIG_DIR at it when WORKSPACE_GROUP (exported by the
# group .envrc) is one of the account's `groups`, unless it is set already.
#
# Everything else this feature writes goes to ~/.claude. Whatever lands there —
# hooks, settings, MCP servers, skills — reaches an account only if the account
# asks for it below, so a company login does not inherit personal servers by
# accident. Which accounts exist is configuration, not product: the product
# ships none.
{ lib, config, ... }:

let
  user = config.features.base.system.user.name;
  home = config.users.users.${user}.home;
  cfg = config.features.fluteos.claude-code;
  accounts = cfg.accounts;

  accountType = lib.types.submodule ({ name, ... }: {
    options = {
      dir = lib.mkOption {
        type = lib.types.str;
        default = "${home}/.config/claude-accounts/${name}";
        description = "The account's CLAUDE_CONFIG_DIR.";
      };
      groups = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Project groups whose agents run under this account.";
      };
      shareSettings = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Merge ~/.claude/settings.json (hooks, permissions, statusline, plugins)
          over the account's own settings.json on every activation.
        '';
      };
      sharePlugins = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Use the plugins installed under ~/.claude/plugins.";
      };
      sharedSkills = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        example = [ "fluteos-agent-run" ];
        description = "Skills from ~/.claude/skills to link into the account.";
      };
      sharedMcpServers = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        example = [ "claude-context" ];
        description = "MCP servers from ~/.claude.json to copy into the account.";
      };
      skills = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = { };
        example = { review = "/home/me/Projects/acme/acme/source/app/.claude/skills/review"; };
        description = ''
          Extra skills for this account only: name → directory holding SKILL.md.
          Linked, not copied, so a skill living in a checkout follows its branch.
        '';
      };
    };
  });

  setupAccount = name: a: ''
    dir=${lib.escapeShellArg a.dir}
    mkdir -p "$dir/skills"

    ${lib.optionalString a.shareSettings ''
      if [ -s "$HOME/.claude/settings.json" ]; then
        [ -s "$dir/settings.json" ] || echo '{}' >"$dir/settings.json"
        tmp="$dir/settings.json.fluteos.$$"
        if jq -s '.[0] * .[1]' "$dir/settings.json" "$HOME/.claude/settings.json" >"$tmp"; then
          mv -f "$tmp" "$dir/settings.json"
          chmod 600 "$dir/settings.json"
        else
          rm -f "$tmp"
          echo "claude-code.accounts(${name}): settings.json is not valid JSON, skipped" >&2
        fi
      fi
    ''}

    ${lib.optionalString a.sharePlugins ''
      if [ -d "$HOME/.claude/plugins" ] && [ ! -e "$dir/plugins" ]; then
        ln -s "$HOME/.claude/plugins" "$dir/plugins"
      fi
    ''}

    # Symlinks in skills/ belong to this module; one no longer declared goes
    # away. Real directories there are the account's own and stay.
    find "$dir/skills" -maxdepth 1 -type l -lname '*' | while read -r l; do
      case " ${toString (a.sharedSkills ++ lib.attrNames a.skills)} " in
        *" $(basename "$l") "*) ;;
        *) rm -f "$l" ;;
      esac
    done
    ${lib.concatMapStrings (s: ''
      ln -sfn "$HOME/.claude/skills/${s}" "$dir/skills/${s}"
    '') a.sharedSkills}
    ${lib.concatStrings (lib.mapAttrsToList (s: path: ''
      ln -sfn ${lib.escapeShellArg path} "$dir/skills/${s}"
    '') a.skills)}

    ${lib.optionalString (a.sharedMcpServers != [ ]) ''
      if [ -s "$HOME/.claude.json" ]; then
        f="$dir/.claude.json"
        [ -s "$f" ] || echo '{}' >"$f"
        tmp="$f.fluteos.$$"
        if jq --slurpfile src "$HOME/.claude.json" \
             --argjson names ${lib.escapeShellArg (builtins.toJSON a.sharedMcpServers)} \
             '.mcpServers = ((.mcpServers // {}) + ($src[0].mcpServers // {} | with_entries(select(.key as $k | $names | index($k)))))' \
             "$f" >"$tmp"; then
          mv -f "$tmp" "$f"
          chmod 600 "$f"
        else
          rm -f "$tmp"
          echo "claude-code.accounts(${name}): .claude.json is not valid JSON, skipped" >&2
        fi
      fi
    ''}
  '';
in
{
  options.features.fluteos.claude-code.accounts = lib.mkOption {
    type = lib.types.attrsOf accountType;
    default = { };
    description = "Claude Code logins besides ~/.claude, keyed by name.";
  };

  config = lib.mkIf (cfg.enable && accounts != { }) {
    home-manager.users.${user} = { pkgs, lib, ... }: {
      home.activation.claudeAccounts =
        lib.hm.dag.entryAfter [ "writeBoundary" "claudeSettings" "claudeMcpSetup" ] ''
          PATH="${lib.makeBinPath [ pkgs.jq pkgs.coreutils pkgs.findutils ]}:$PATH"
          ${lib.concatStrings (lib.mapAttrsToList setupAccount accounts)}
        '';
    };
  };
}
