# Screencast menu
{
  type = "key";
  items = [
    { key = "r"; label = "Record Screen"; action = { exec = [ "screencast-record" "screen" ]; }; }
    { key = "s"; label = "Record Region"; action = { exec = [ "screencast-record" "region" ]; }; }
    { key = "q"; label = "Stop Recording"; action = { exec = [ "screencast-record" "stop" ]; }; }
  ];
}
