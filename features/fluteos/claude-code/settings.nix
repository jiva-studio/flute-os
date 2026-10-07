# The settings Claude Code is launched with, and the activation script that puts
# them in ~/.claude/settings.json.
#
# Not a home.file symlink, deliberately. Claude Code writes to its own user
# settings — /effort, /model, /config, the statusline picker — and a symlink into
# the read-only store turns every one of those into an EROFS error inside the
# session. So the declared settings are merged into a real, writable file at
# activation time: the keys below win on every rebuild, anything the CLI put
# there itself survives.
#
# The cost of a merge is that nothing records which keys used to be ours, so
# removing one here no longer removes it from the file. Delete it by hand.
{ lib, pkgs, nixosCfg, claudeNotify }:

let
  jq = "${pkgs.jq}/bin/jq";

  settings = {
    "$schema" = "https://json.schemastore.org/claude-code-settings.json";
    tui = "fullscreen";
    # No in-app agent view (Claude Code's own "fleet": several sessions
    # multiplexed inside one window, dispatched and replied to from a list).
    # FluteOS runs its fleet a level up — one real WezTerm window per agent,
    # launched by fluteos-agent-launch and driven by fluteos-agent-send, so
    # the compositor, the waybar widget and the agent registry all see it and
    # anything on the machine can address a session by pane id. The in-app
    # one is visible only to itself. Same switch as the
    # CLAUDE_CODE_DISABLE_AGENT_VIEW environment variable.
    disableAgentView = true;
    # Plain attrset arithmetic, not mkMerge — this is fed straight to
    # builtins.toJSON, where module-system combinators would serialise as
    # garbage rather than merging.
    hooks =
      let
        agentsOn = nixosCfg.features.fluteos.agents.enable;
        # Agent status registry (features.fluteos.agents): every session
        # reports its own state so the waybar widget can show what is
        # running, what is blocked on you, and what is idle — across all
        # workspaces. Observer only; never blocks a tool call.
        agentHook = event: {
          matcher = "";
          hooks = [{
            type = "command";
            command = "fluteos-agent-hook ${event}";
          }];
        };
        agentEvents = [ "SessionStart" "SessionEnd" "UserPromptSubmit" "PreToolUse" "Notification" ];
      in
      {
        # Stop already carries the urgency notifier; the registry hook is
        # appended so both run on turn end.
        Stop = [{
          matcher = "";
          hooks = [{
            type = "command";
            command = "${claudeNotify}";
          }];
        }] ++ lib.optional agentsOn (agentHook "Stop");
      }
      # Each event maps to a LIST of matcher groups — genAttrs hands the
      # bare attrset back, so wrap it.
      // lib.optionalAttrs agentsOn (lib.genAttrs agentEvents (e: [ (agentHook e) ]));
    # Read-only tools, plus the research MCP FluteOS registers itself. Kept in
    # step with mcpServers: a permission for a server the product does not
    # ship would be a permission for somebody else's account.
    permissions.allow = [
      "Read"
      "WebFetch"
      "WebSearch"
    ] ++ lib.optionals (nixosCfg.features.fluteos.claude-code.mcpServers ? perplexity) [
      "mcp__perplexity__perplexity_ask"
      "mcp__perplexity__perplexity_search"
      "mcp__perplexity__perplexity_research"
      "mcp__perplexity__perplexity_reason"
    ];
  }
  # Plugin marketplaces and the plugins enabled from them. Omitted entirely when
  # empty rather than written as `{}`: this file is MERGED into on every rebuild,
  # so an empty declaration would keep flattening whatever the /plugin panel put
  # there.
  // lib.optionalAttrs (nixosCfg.features.fluteos.claude-code.marketplaces != { }) {
    extraKnownMarketplaces = nixosCfg.features.fluteos.claude-code.marketplaces;
  }
  // lib.optionalAttrs (nixosCfg.features.fluteos.claude-code.plugins != { }) {
    enabledPlugins = nixosCfg.features.fluteos.claude-code.plugins;
  };

  declared = pkgs.writeText "claude-settings.json" (builtins.toJSON settings);
in
''
  SETTINGS="$HOME/.claude/settings.json"

  mkdir -p "$HOME/.claude"

  # A symlink here is a leftover from the generation that still used home.file;
  # it points into the store and cannot be written through. Drop it and start
  # from the declared settings.
  if [ -L "$SETTINGS" ]; then
    rm -f "$SETTINGS"
  fi

  # An unreadable or corrupt file is replaced rather than merged into — a failed
  # jq would otherwise leave the session with no settings at all.
  if [ -s "$SETTINGS" ] && ${jq} -e . "$SETTINGS" >/dev/null 2>&1; then
    ${jq} -s '.[0] * .[1]' "$SETTINGS" ${declared} > "$SETTINGS.tmp" \
      && mv "$SETTINGS.tmp" "$SETTINGS"
  else
    cp ${declared} "$SETTINGS"
  fi

  chmod 600 "$SETTINGS"
''
