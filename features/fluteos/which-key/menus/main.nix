# Main menu (root level)
{ }:

{
  type = "key";
  items = [
    { key = "a"; label = "Applications"; action = { menu = "apps"; }; }
    { key = "b"; label = "Brain"; action = { menu = "brain"; }; }
    { key = "w"; label = "Windows"; action = { menu = "windows"; }; }
    { key = "e"; label = "File Manager"; action = { exec = [ "wezterm" "start" "--always-new-process" "--" "yazi" ]; }; }
    { key = "o"; label = "Workspace"; action = { menu = "workspace"; }; }
    { key = "r"; label = "Screencast"; action = { menu = "screencast"; }; }
    { key = "s"; label = "Screenshot"; action = { menu = "screenshot"; }; }
    { key = "p"; label = "Power"; action = { menu = "power"; }; }
  ];
}
