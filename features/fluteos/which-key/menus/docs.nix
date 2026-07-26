# Project documentation menu (docsify-based docs/ in the current workspace).
# Visible only when the current workspace has docs initialized.
{
  type = "key";
  items = [
    { key = "o"; label = "Open docs (root)"; icon = "󰈙"; action = { exec = [ "fluteos-docs-open" ]; }; }
    { key = "f"; label = "Find heading…";    icon = "󰍉"; action = { menu = "docs-find"; }; }
    { key = "i"; label = "Init / rescan";    icon = "󰦗"; action = { exec = [ "fluteos-docs-init" "--rescan" ]; }; }
  ];
}
