# Webcam (Video4Linux) tooling + Logitech MX Brio control.
#
# The MX Brio (046d:0944) is a UVC 4K cam. Two facts drive this module:
#   - Zoom is a device-side control (`zoom_absolute`, 100..400 = 1x..4x). It
#     lives on the *capture* node (index 0 = /dev/video4 here; the index-1 node
#     is metadata-only and has no controls). The value persists on the device
#     until unplug, so a udev rule can set a default when the cam appears.
#   - Resolution/4K is negotiated by whatever app opens the camera, not set
#     globally — pick 3840x2160 (MJPG) in Zoom/OBS/browser. `brio 4k` verifies
#     the cam actually delivers a 4K frame.
{ lib, config, pkgs, ... }:
let
  cfg = config.features.base.webcam;

  # Applied by udev on plug-in ($1 = the capture /dev/videoN).
  brioDefaults = pkgs.writeShellScript "brio-apply-defaults" ''
    dev="$1"
    ${pkgs.v4l-utils}/bin/v4l2-ctl -d "$dev" \
      --set-ctrl=zoom_absolute=${toString cfg.brio.zoom} \
      ${lib.optionalString (cfg.brio.autofocus != null)
        "--set-ctrl=focus_automatic_continuous=${if cfg.brio.autofocus then "1" else "0"}"} \
      || true
  '';

  # `brio` — auto-detects the MX Brio capture node and drives its controls.
  brioCli = pkgs.writeShellScriptBin "brio" ''
    set -euo pipefail
    v4l2ctl=${pkgs.v4l-utils}/bin/v4l2-ctl

    find_dev() {
      for d in /dev/video*; do
        [ -e "$d" ] || continue
        name=$($v4l2ctl -d "$d" --info 2>/dev/null \
                 | sed -n 's/.*Card type\s*:\s*//p') || true
        case "$name" in
          *"MX Brio"*)
            if $v4l2ctl -d "$d" --list-ctrls 2>/dev/null | grep -q zoom_absolute; then
              echo "$d"; return 0
            fi ;;
        esac
      done
      echo "brio: MX Brio capture node not found" >&2; return 1
    }

    dev=$(find_dev)

    case "''${1:-status}" in
      zoom)
        [ -n "''${2:-}" ] || { echo "usage: brio zoom <100-400>  (100=1x wide, 400=4x)"; exit 1; }
        $v4l2ctl -d "$dev" --set-ctrl=zoom_absolute="$2"
        echo "zoom -> $2 on $dev" ;;
      4k)
        out="''${2:-/tmp/brio-4k.jpg}"
        echo "grabbing one 3840x2160 MJPG frame from $dev ..."
        ${pkgs.ffmpeg}/bin/ffmpeg -hide_banner -loglevel error \
          -f v4l2 -input_format mjpeg -video_size 3840x2160 -i "$dev" \
          -frames:v 1 -y "$out"
        echo "wrote $out"
        ${pkgs.ffmpeg}/bin/ffprobe -hide_banner -loglevel error \
          -show_entries stream=width,height -of csv=p=0 "$out" ;;
      gui)
        exec ${pkgs.cameractrls}/bin/cameractrlsgtk ;;
      status|"")
        echo "device: $dev"
        $v4l2ctl -d "$dev" --get-ctrl=zoom_absolute
        $v4l2ctl -d "$dev" --get-fmt-video | sed -n 's/^\s*//; /Width\/Height\|Pixel Format/p' ;;
      *)
        exec $v4l2ctl -d "$dev" "$@" ;;
    esac
  '';
in
{
  options.features.base.webcam = {
    enable = lib.mkEnableOption "Webcam (v4l2) tooling + MX Brio control";

    brio.zoom = lib.mkOption {
      type = lib.types.ints.between 100 400;
      default = 100;
      description = "Default MX Brio zoom applied on plug-in (100 = 1x wide, 400 = 4x).";
    };

    brio.autofocus = lib.mkOption {
      type = lib.types.nullOr lib.types.bool;
      default = null;
      description = "Force continuous autofocus on/off on plug-in (null = leave the cam's own setting).";
    };
  };

  config = lib.mkIf cfg.enable {
    # v4l2-ctl (CLI), cameractrls (GTK sliders for zoom/pan/tilt), and `brio`.
    environment.systemPackages = [ pkgs.v4l-utils pkgs.cameractrls brioCli ];

    # Apply defaults on the capture node (index 0) whenever the Brio appears.
    services.udev.extraRules = ''
      SUBSYSTEM=="video4linux", ATTRS{idVendor}=="046d", ATTRS{idProduct}=="0944", ATTR{index}=="0", RUN+="${brioDefaults} $devnode"
    '';
  };
}
