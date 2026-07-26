# Niri input configuration: keyboard, touchpad, mouse
{ lib, modKey, keyboard }:

let
  # Emit only the xkb lines that are actually set: an unset variant or options
  # must not leave a blank line in the generated config. The separator carries
  # the indentation the `${xkbLines}` placeholder sits at below.
  xkbLines = lib.concatStringsSep "\n            " (
    [ ''layout "${keyboard.layout}"'' ]
    ++ lib.optional (keyboard.variant != "") ''variant "${keyboard.variant}"''
    ++ lib.optional (keyboard.options != "") ''options "${keyboard.options}"''
  );
in
''
  input {
      mod-key "${modKey}"

      keyboard {
          xkb {
              ${xkbLines}
          }
      }

      touchpad {
          tap
          natural-scroll
          scroll-factor 0.5
      }

      mouse {
      }

      focus-follows-mouse max-scroll-amount="0%"
  }

  gestures {
      hot-corners {
          off
      }
  }
''
