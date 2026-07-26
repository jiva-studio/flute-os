from evdev import InputDevice, ecodes, list_devices
import pyudev


def is_keyboard(device: InputDevice) -> bool:
    """Check if device is a keyboard (can type letters)."""
    try:
        caps = device.capabilities()
        return ecodes.EV_KEY in caps and ecodes.KEY_A in caps[ecodes.EV_KEY]
    except:
        return False


def find_keyboards() -> list[InputDevice]:
    """Find all currently connected keyboard devices."""
    kbs = []
    for path in list_devices():
        try:
            dev = InputDevice(path)
            if is_keyboard(dev):
                kbs.append(dev)
        except:
            pass
    return kbs


class KeyboardMonitor:
    """Monitors for keyboard connect/disconnect events via udev."""

    def __init__(self):
        self.context = pyudev.Context()
        self.monitor = pyudev.Monitor.from_netlink(self.context)
        self.monitor.filter_by(subsystem='input')
        self.monitor.start()

    def fileno(self) -> int:
        """Return file descriptor for use with selectors."""
        return self.monitor.fileno()

    def poll(self) -> tuple[str, any] | None:
        """Poll for device events. Non-blocking."""
        device = self.monitor.poll(timeout=0)
        if device is None:
            return None

        dev_node = device.device_node
        if not dev_node or '/event' not in dev_node:
            return None

        if device.action == 'add':
            try:
                input_dev = InputDevice(dev_node)
                if is_keyboard(input_dev):
                    return ('add', input_dev)
            except:
                pass
        elif device.action == 'remove':
            return ('remove', dev_node)

        return None
