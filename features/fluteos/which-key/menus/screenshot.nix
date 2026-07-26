# Screenshot menu
{
  type = "key";
  items = [
    { key = "s"; label = "Select Region"; action = { exec = [ "niri" "msg" "action" "screenshot" ]; }; }
    { key = "f"; label = "Full Screen"; action = { exec = [ "bash" "-c" "sleep 1 && niri msg action screenshot-screen" ]; }; }
    { key = "w"; label = "Window"; action = { exec = [ "bash" "-c" "sleep 1 && niri msg action screenshot-window" ]; }; }
  ];
}
