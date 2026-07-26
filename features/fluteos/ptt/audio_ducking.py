import subprocess
import atexit
import re


class AudioDucker:
    DUCK_LEVEL = 0.20

    def __init__(self):
        self._original_volume = None
        self._is_ducked = False
        # atexit only — deliberately NO signal.signal(SIGTERM) here.
        #
        # This class used to install its own SIGTERM handler, which main() then
        # replaced with its own (last writer wins), so `systemctl stop` skipped
        # the restore entirely and left the user's volume pinned at 20% until
        # they noticed and fixed it by hand. Signal disposition is process-wide
        # state and belongs to main(), which now calls cleanup() -> restore()
        # from its handler. atexit stays as a second net: it also runs on the
        # SystemExit that handler raises.
        atexit.register(self._cleanup)

    def _cleanup(self):
        if self._is_ducked:
            self.restore()

    def _get_volume(self):
        try:
            result = subprocess.run(
                ["wpctl", "get-volume", "@DEFAULT_AUDIO_SINK@"],
                capture_output=True, text=True, timeout=1
            )
            # "Volume: 0.75" -> "0.75"
            match = re.search(r"Volume:\s*([\d.]+)", result.stdout)
            return match.group(1) if match else None
        except:
            return None

    def duck(self):
        if not self._is_ducked:
            self._original_volume = self._get_volume()
            # Don't raise volume if already below duck level
            if self._original_volume and float(self._original_volume) > self.DUCK_LEVEL:
                subprocess.run(["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", str(self.DUCK_LEVEL)])
            self._is_ducked = True

    def restore(self):
        if self._is_ducked and self._original_volume:
            subprocess.run(["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", self._original_volume])
        self._is_ducked = False
        self._original_volume = None
