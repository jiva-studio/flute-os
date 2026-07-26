# Workspace submenu — second-level under Mod+Space → o.
# Bundles "open workspace", "launch agent in current workspace", and "open docs
# of current workspace" together since they all act on a workspace context.
{
  type = "key";
  items = [
    { key = "o"; label = "Open workspace…"; icon = "󰆍"; action = { menu = "projects"; }; }
    { key = "g"; label = "Agent";           icon = "󰚩"; action = { menu = "agent"; }; enabledCmd = [ "fluteos-agent-check" ]; }
    { key = "d"; label = "Docs";            icon = "󰈙"; action = { menu = "docs"; }; enabledCmd = [ "fluteos-docs-check" ]; }
    { key = "q"; label = "Close workspace"; icon = "󰅖"; action = { exec = [ "niri-workspace-close" ]; }; }
  ];
}
