# Windows management menu
{
  type = "key";
  items = [
    { key = "q"; label = "Close Window"; action = { exec = [ "niri" "msg" "action" "close-window" ]; }; }
    { key = "f"; label = "Fullscreen"; action = { exec = [ "niri" "msg" "action" "fullscreen-window" ]; }; }
    { key = "m"; label = "Maximize"; action = { exec = [ "niri" "msg" "action" "maximize-column" ]; }; }
    { key = "t"; label = "Toggle Tabbed"; action = { exec = [ "niri" "msg" "action" "toggle-column-tabbed-display" ]; }; }
    { key = "b"; label = "Toggle Bar"; action = { exec = [ "pkill" "-SIGUSR1" "waybar" ]; }; }
    { key = "r"; label = "Rename Workspace"; action = { menu = "workspace-rename"; }; }
  ];
}
