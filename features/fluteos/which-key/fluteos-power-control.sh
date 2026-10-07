#!/usr/bin/env bash
# Power control script for profile switching and turbo boost.
#
# Probes sysfs paths at runtime — none of these knobs is guaranteed to
# exist on every kernel/driver combo. Profile control needs the kernel
# platform_profile ABI; boost control needs cpufreq's global `boost`
# (or `cpb` on amd-pstate). Missing files surface as "n/a" rather
# than silent breakage.
#
# Dependencies: NOTIFY_SEND (set via environment).

PLATFORM_PROFILE_FILE=/sys/firmware/acpi/platform_profile
PLATFORM_PROFILE_CHOICES_FILE=/sys/firmware/acpi/platform_profile_choices

# cpufreq exposes either `boost` (acpi-cpufreq, amd_pstate=passive/guided)
# or `cpb` (amd_pstate=active) — whichever the active driver provides.
detect_boost_file() {
  for f in /sys/devices/system/cpu/cpufreq/boost /sys/devices/system/cpu/cpufreq/cpb; do
    [ -e "$f" ] && { echo "$f"; return; }
  done
}
BOOST_FILE=$(detect_boost_file)

# UI uses power-profiles-daemon naming ("power-saver"); kernel sysfs
# uses "low-power". Translate both ways.
ui_to_sysfs() {
  case "$1" in power-saver) echo "low-power" ;; *) echo "$1" ;; esac
}
sysfs_to_ui() {
  case "$1" in low-power) echo "power-saver" ;; *) echo "$1" ;; esac
}

read_profile() {
  [ -r "$PLATFORM_PROFILE_FILE" ] || { echo "n/a"; return; }
  cat "$PLATFORM_PROFILE_FILE"
}

read_boost() {
  [ -n "$BOOST_FILE" ] && [ -r "$BOOST_FILE" ] || { echo "n/a"; return; }
  cat "$BOOST_FILE"
}

notify() {
  "$NOTIFY_SEND" -h string:x-canonical-private-synchronous:power "$1" "$2"
}

show_status() {
  profile=$(sysfs_to_ui "$(read_profile)")
  boost=$(read_boost)
  case "$boost" in
    1) boost_text="ON" ;;
    0) boost_text="OFF" ;;
    *) boost_text="N/A" ;;
  esac
  freq=$(cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_cur_freq 2>/dev/null \
    | awk '{sum+=$1;n++} END {if(n)printf "%.1f GHz", sum/n/1000000; else print "N/A"}')
  notify "Power Profile" "Profile: $profile\nTurbo Boost: $boost_text\nAvg Freq: $freq"
}

set_profile() {
  local target=$1
  if [ ! -e "$PLATFORM_PROFILE_FILE" ]; then
    notify "Power Profile" "platform_profile not exposed by kernel"
    return 1
  fi
  if [ -r "$PLATFORM_PROFILE_CHOICES_FILE" ]; then
    if ! grep -qw -- "$target" "$PLATFORM_PROFILE_CHOICES_FILE"; then
      choices=$(tr '\n' ' ' < "$PLATFORM_PROFILE_CHOICES_FILE")
      notify "Power Profile" "Profile '$target' not supported (have:$choices)"
      return 1
    fi
  fi
  echo "$target" | sudo tee "$PLATFORM_PROFILE_FILE" > /dev/null
}

case "${1:-}" in
  # Pure-status helpers used by which-key statusCmd. No output, exit code only.
  is-profile)
    [ "$(read_profile)" = "$(ui_to_sysfs "${2:-}")" ]
    ;;
  is-boost-on)
    [ "$(read_boost)" = "1" ]
    ;;

  boost-toggle)
    if [ -z "$BOOST_FILE" ]; then
      notify "Turbo Boost" "Not exposed by current cpufreq driver"
      exit 1
    fi
    cur=$(read_boost)
    new=$([ "$cur" = "1" ] && echo 0 || echo 1)
    echo "$new" | sudo tee "$BOOST_FILE" > /dev/null
    show_status
    ;;
  caffeine-toggle)
    if systemd-inhibit --list 2>/dev/null | grep -q Caffeine; then
      pkill -f "systemd-inhibit.*Caffeine"
      "$NOTIFY_SEND" -h string:x-canonical-private-synchronous:caffeine \
        "Caffeine" "OFF"
    else
      systemd-inhibit --what=sleep:handle-lid-switch --who="Caffeine" --why="Keep system awake" \
        --mode=block sleep infinity &
      "$NOTIFY_SEND" -h string:x-canonical-private-synchronous:caffeine \
        "Caffeine" "ON (System sleep inhibited, display sleep allowed)"
    fi
    ;;
  profile-*)
    set_profile "$(ui_to_sysfs "${1#profile-}")" && show_status
    ;;
  *)
    echo "usage: $0 {is-profile <name>|is-boost-on|boost-toggle|caffeine-toggle|profile-<name>}" >&2
    exit 2
    ;;
esac
