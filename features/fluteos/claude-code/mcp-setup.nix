# Generates the activation script that registers MCP servers in ~/.claude.json.
#
# One `mkServer` for every entry in features.fluteos.claude-code.mcpServers,
# replacing 194 lines of hand-written shell in which each server repeated the
# same four steps: name its secret files, test them with `[ -s ]`, build a
# `jq -n --argjson base … '$base + { … }'` merge, and echo a skip message.
#
# Two properties that the hand-written version had and this keeps:
#   - a server missing its credential is SKIPPED, with a warning naming the file.
#     It never fails the activation and never takes another server down with it.
#   - a credential is read from disk at activation time and handed to jq through
#     `--arg`, so it enters neither /nix/store nor the shell's argument list in a
#     way that would break on newlines (the GA private key is a multi-line PEM).
{ lib, pkgs, cfg }:

let
  jq = "${pkgs.jq}/bin/jq";

  # A secret file name becomes a jq variable: reddit-client-id -> $s_reddit_client_id
  varOf = name: "s_" + lib.replaceStrings [ "-" "." "/" ] [ "_" "_" "_" ] name;

  # Turn an env value into a jq expression, substituting %{secret} references.
  #   "plain"                        -> "plain"
  #   "%{tok}"                       -> "" + $s_tok + ""
  #   "ua/1.0 (by /u/%{user})"       -> "ua/1.0 (by /u/" + $s_user + ""
  # Concatenating empty strings is harmless in jq and keeps the generator simple.
  jqValue = value:
    let
      chunks = lib.splitString "%{" value;
      expand = chunk:
        let
          halves = lib.splitString "}" chunk;
          secret = builtins.head halves;
          literal = lib.concatStringsSep "}" (builtins.tail halves);
        in
        [ ("$" + varOf secret) (builtins.toJSON literal) ];
    in
    lib.concatStringsSep " + "
      ([ (builtins.toJSON (builtins.head chunks)) ]
        ++ lib.concatMap expand (builtins.tail chunks));

  envObject = env: "{ "
    + lib.concatStringsSep ", "
      (lib.mapAttrsToList (name: value: "${builtins.toJSON name}: (${jqValue value})") env)
    + " }";

  # `[ -s a ] && [ -s b ] && …`; a server with no secrets is unconditional.
  presenceTest = server:
    lib.concatStringsSep " && "
      (map (s: ''[ -s "$SECRET_DIR/${s}" ]'') server.secrets);

  argFlags = server:
    lib.concatMapStrings
      (s: '' \
            --arg ${varOf s} "$(cat "$SECRET_DIR/${s}")"'')
      server.secrets;

  mkServer = name: server:
    let
      body = ''${builtins.toJSON name}: {
              type: "stdio",
              command: ${builtins.toJSON server.command},
              args: ${builtins.toJSON server.args},
              env: ${envObject server.env}
            }'';
      merge = ''
        MCP_CONFIG="$(${jq} -n --argjson base "$MCP_CONFIG"${argFlags server} '$base + {
            ${body}
          }')"
      '';
    in
    if server.secrets == [ ] then merge
    else ''
      if ${presenceTest server}; then
      ${merge}
      else
        echo "claude-mcp: ${name} needs ${lib.concatStringsSep ", " server.secrets} under $SECRET_DIR — skipping ${name}." >&2
      ${lib.optionalString (server.hint != "") ''
        echo "  ${server.hint}" >&2
      ''}fi
    '';

  enabled = lib.filterAttrs (_: s: s.enable) cfg.mcpServers;
in
''
  CLAUDE_JSON="$HOME/.claude.json"
  SECRET_DIR="${cfg.secretsDir}"

  MCP_CONFIG='{}'

  ${lib.concatStringsSep "\n" (lib.mapAttrsToList mkServer enabled)}

  if [ -f "$CLAUDE_JSON" ]; then
    ${jq} --argjson mcp "$MCP_CONFIG" '.mcpServers = (.mcpServers // {}) + $mcp' "$CLAUDE_JSON" > "$CLAUDE_JSON.tmp" \
      && mv "$CLAUDE_JSON.tmp" "$CLAUDE_JSON"
  else
    printf '{"mcpServers": %s}\n' "$MCP_CONFIG" > "$CLAUDE_JSON"
  fi
''
