"""Generic which-key/fuzzy menu for Wayland. Config passed via JSON file.

Runs as a long-lived GtkApplication service: Python + GTK4 init happens once,
each Cmd+Space hit activates the existing instance over D-Bus and presents the
already-built window.
"""
import gi
import subprocess
import json
import sys

gi.require_version('Gtk', '4.0')
from gi.repository import Gtk, Gdk, GLib, Gio


def _fuzzy_score(query, label):
    """Subsequence fuzzy match with bonuses. Both args lowercased.

    Returns 0 for no match, higher for better. Substring matches dominate
    subsequence-only matches; word-boundary matches outrank mid-word ones.
    """
    if not query:
        return 0
    if not label:
        return 0
    # Cheap fast paths: prefix wins, then substring.
    if label.startswith(query):
        return 1000 - len(label)
    idx = label.find(query)
    if idx >= 0:
        # word-boundary substring → big bonus
        boundary = idx == 0 or label[idx - 1] in ' /-_·.>'
        return (700 if boundary else 500) - idx - len(label) // 4
    # Subsequence: every query char appears in order somewhere in label.
    li = 0
    matched = 0
    last_pos = -1
    boundary_hits = 0
    for ch in query:
        found = label.find(ch, li)
        if found < 0:
            return 0
        if found > 0 and label[found - 1] in ' /-_·.>':
            boundary_hits += 1
        # Penalty for gaps between matched chars
        if last_pos >= 0:
            matched -= (found - last_pos - 1)
        matched += 2
        last_pos = found
        li = found + 1
    return max(1, 200 + matched + boundary_hits * 10 - len(label) // 8)


class Menu(Gtk.Application):
    def __init__(self, config_path):
        super().__init__(
            application_id='com.fluteos.WhichKey',
            flags=Gio.ApplicationFlags.IS_SERVICE,
        )
        with open(config_path) as f:
            self.config = json.load(f)
        self.menu_stack = ['main']
        self.menu_items = []
        self.filtered_items = []
        self.selected_index = 0
        self.search_entry = None
        self.win = None
        self._css_loaded = False
        # Keep the service alive across window hides; without hold() the app
        # would exit once the last window closes (or after the IS_SERVICE
        # idle timer fires).
        self.hold()

    def do_activate(self):
        # Recreate the window each activation. GTK4 caches realized size on a
        # reused ApplicationWindow, so previous menu's geometry leaked into the
        # next one (narrow when prior was a small key menu, short when prior
        # was a key menu but new is fuzzy with hundreds of items, etc.).
        # Building a fresh window every activation is cheap — Python + GTK
        # init already happened once at service start.
        self.menu_stack = ['main']
        if self.win is not None:
            self.win.destroy()
            self.win = None
        self._create_window()
        self.show_menu()
        self.win.present()

    def _create_window(self):
        self.win = Gtk.ApplicationWindow(application=self)
        self.win.add_css_class('menu-window')
        # Default size — show_menu may tighten/extend per menu type. Without
        # this, GTK shrinks the window to its content's minimum, which makes
        # FlowBox key menus too narrow (items overlap) and search results too
        # short (last few rows clipped).
        self.win.set_default_size(640, -1)
        self.win.set_resizable(False)

        key_ctrl = Gtk.EventControllerKey()
        key_ctrl.connect('key-pressed', self.on_key)
        self.win.add_controller(key_ctrl)

        # Window-manager close (e.g. middle-click on title) hides instead of
        # destroying, so the next activation can re-present the same window.
        self.win.connect('close-request', self._on_close_request)

        if not self._css_loaded:
            self.load_css()
            self._css_loaded = True

    def _on_close_request(self, win):
        win.hide()
        return True

    def hide_menu(self):
        if self.win is not None:
            self.win.hide()

    def load_css(self):
        css = self.config.get('css', '')
        provider = Gtk.CssProvider()
        provider.load_from_string(css)
        Gtk.StyleContext.add_provider_for_display(
            Gdk.Display.get_default(),
            provider,
            Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
        )

    def current_menu(self):
        return self.config['menus'].get(self.menu_stack[-1], {})

    def show_menu(self):
        menu = self.current_menu()
        menu_type = menu.get('type', 'key')

        # Dynamic items via itemsCmd (with error handling and timeout)
        if 'itemsCmd' in menu:
            try:
                result = subprocess.run(
                    menu['itemsCmd'],
                    capture_output=True,
                    text=True,
                    timeout=2.0  # 2 seconds max
                )
                items = json.loads(result.stdout) if result.returncode == 0 else []
            except (subprocess.TimeoutExpired, json.JSONDecodeError):
                items = []
        else:
            items = menu.get('items', [])

        if self.win.get_child():
            self.win.set_child(None)

        main_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        main_box.set_margin_top(16)
        main_box.set_margin_bottom(16)
        main_box.set_margin_start(20)
        main_box.set_margin_end(20)

        # Check enabledCmd for key menu items. Items live in self.config and
        # are reused across activations, so always overwrite — never just set
        # True on failure, or a one-time disable would stick until daemon
        # restart.
        for item in items:
            if 'enabledCmd' in item:
                try:
                    result = subprocess.run(
                        item['enabledCmd'],
                        capture_output=True,
                        timeout=0.5
                    )
                    item['_disabled'] = result.returncode != 0
                except (subprocess.TimeoutExpired, OSError):
                    item['_disabled'] = True

        self.menu_items = items  # store for search filtering
        self.filtered_items = items[:]
        self.selected_index = 0
        self.search_entry = None

        if menu_type == 'fuzzy':
            self.search_entry = Gtk.SearchEntry()
            self.search_entry.set_placeholder_text('Type to search...')
            self.search_entry.add_css_class('search-entry')
            self.search_entry.connect('search-changed', self.on_search_changed)
            self.search_entry.connect('activate', self.on_search_activate)
            self.search_entry.connect('stop-search', self.on_stop_search)
            main_box.append(self.search_entry)
            # Fuzzy uses a vertical list inside a ScrolledWindow so menus with
            # hundreds of items cap height instead of overflowing the screen.
            self.items_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
            scroller = Gtk.ScrolledWindow()
            scroller.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
            scroller.set_min_content_height(480)
            scroller.set_max_content_height(560)
            scroller.set_child(self.items_box)
            main_box.append(scroller)
            # Wider + taller for fuzzy: long heading-like labels need room.
            self.win.set_default_size(720, 620)
        else:
            # Key menus use multi-column flow layout. Min children-per-line = 1
            # so 1-3 item menus don't get squeezed (e.g. workspace submenu);
            # max = 4 caps width even when many items.
            self.items_box = Gtk.FlowBox()
            self.items_box.set_selection_mode(Gtk.SelectionMode.NONE)
            self.items_box.set_homogeneous(True)
            self.items_box.set_min_children_per_line(1)
            self.items_box.set_max_children_per_line(4)
            self.items_box.set_row_spacing(8)
            self.items_box.set_column_spacing(12)
            main_box.append(self.items_box)
            # Width fixed at 640; height autos so the window hugs content.
            self.win.set_default_size(640, -1)

        self.render_items()
        self.win.set_child(main_box)

        if self.search_entry:
            self.search_entry.grab_focus()

            # Prefilled search text
            if 'prefillCmd' in menu:
                try:
                    result = subprocess.run(
                        menu['prefillCmd'],
                        capture_output=True,
                        text=True,
                        timeout=0.5
                    )
                    prefill = result.stdout.strip() if result.returncode == 0 else ''
                except subprocess.TimeoutExpired:
                    prefill = ''

                if prefill:  # only if workspace has a name
                    self.search_entry.set_text(prefill)
                    if menu.get('prefillSelect', False):
                        # Select all text so user can replace or continue
                        self.search_entry.select_region(0, -1)
                    else:
                        self.search_entry.set_position(-1)  # cursor at end
                    self.on_search_changed(self.search_entry)  # trigger filtering!

    def get_dynamic_label(self, item):
        """Get label with dynamic status substitution if statusCmd is present."""
        label = item.get('label', '')
        if 'statusCmd' not in item:
            return label
        try:
            result = subprocess.run(
                item['statusCmd'],
                capture_output=True,
                text=True,
                timeout=0.5
            )
            status = result.stdout.strip()
            return label.replace('{status}', status)
        except Exception:
            return label.replace('{status}', '')

    def render_items(self):
        menu = self.current_menu()
        menu_type = menu.get('type', 'key')

        # Clear items
        if menu_type == 'key':
            self.items_box.remove_all()
        else:
            while child := self.items_box.get_first_child():
                self.items_box.remove(child)

        self._selected_row = None
        for i, item in enumerate(self.filtered_items):
            row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
            row.add_css_class('menu-item')

            if item.get('_disabled'):
                row.add_css_class('disabled')

            if menu_type == 'fuzzy' and i == self.selected_index:
                row.add_css_class('selected')
                self._selected_row = row

            if menu_type == 'key':
                # Key first, then label
                key_label = Gtk.Label(label=item.get('key', ''))
                key_label.add_css_class('item-key')
                row.append(key_label)

                text_label = Gtk.Label(label=self.get_dynamic_label(item))
                text_label.add_css_class('item-label')
                text_label.set_xalign(0)
                row.append(text_label)
            else:
                # Fuzzy: icon, then label
                icon_label = Gtk.Label(label=item.get('icon', ''))
                icon_label.add_css_class('item-icon')
                icon_label.set_width_chars(2)
                row.append(icon_label)

                text_label = Gtk.Label(label=item.get('label', ''))
                text_label.add_css_class('item-label')
                text_label.set_xalign(0)
                row.append(text_label)

            self.items_box.append(row)

        if menu_type == 'fuzzy' and self._selected_row is not None:
            # Defer until after layout so compute_bounds returns real coords.
            GLib.idle_add(self._scroll_selected_into_view)

    def _scroll_selected_into_view(self):
        row = getattr(self, '_selected_row', None)
        if row is None:
            return False
        scroller = self.items_box.get_parent()
        if not isinstance(scroller, Gtk.ScrolledWindow):
            return False
        ok, bounds = row.compute_bounds(self.items_box)
        if not ok:
            return False
        adj = scroller.get_vadjustment()
        row_top = bounds.get_y()
        row_bottom = row_top + bounds.get_height()
        page_top = adj.get_value()
        page_size = adj.get_page_size()
        page_bottom = page_top + page_size
        if row_top < page_top:
            adj.set_value(row_top)
        elif row_bottom > page_bottom:
            adj.set_value(row_bottom - page_size)
        return False  # don't repeat

    def on_search_changed(self, entry):
        menu = self.current_menu()
        search_text = entry.get_text()
        search_lower = search_text.lower().strip()
        items = self.menu_items  # use stored items (supports dynamic itemsCmd)

        if search_lower:
            scored = []
            for item in items:
                score = _fuzzy_score(search_lower, item.get('label', '').lower())
                if score > 0:
                    scored.append((score, item))
            # Higher score first; cap to 25 so the list stays scannable.
            scored.sort(key=lambda x: -x[0])
            self.filtered_items = [it for _, it in scored[:25]]
        else:
            self.filtered_items = items[:]

        # Add virtual item for custom input if inputAction exists
        if search_text.strip() and 'inputAction' in menu:
            # Check if exact match already exists
            has_exact = any(
                item.get('label', '').lower() == search_lower
                for item in self.filtered_items
            )
            if not has_exact:
                virtual_item = {
                    'icon': '+',
                    'label': search_text.strip(),
                    '_virtual': True  # marker for inputAction
                }
                self.filtered_items.append(virtual_item)

        self.selected_index = 0
        self.render_items()

    def on_search_activate(self, entry):
        if self.filtered_items and 0 <= self.selected_index < len(self.filtered_items):
            self.execute_action(self.filtered_items[self.selected_index])
        elif not entry.get_text().strip():
            menu = self.current_menu()
            if menu.get('inputOptional') and 'inputAction' in menu:
                input_action = menu['inputAction']
                if 'exec' in input_action:
                    self.win.hide()
                    GLib.timeout_add(50, self._spawn_action, input_action['exec'])

    def on_stop_search(self, entry):
        if len(self.menu_stack) > 1:
            self.menu_stack.pop()
            self.show_menu()
        else:
            self.hide_menu()

    def on_key(self, controller, keyval, keycode, state):
        menu = self.current_menu()
        menu_type = menu.get('type', 'key')
        key_name = Gdk.keyval_name(keyval)

        if key_name == 'Escape':
            if len(self.menu_stack) > 1:
                self.menu_stack.pop()
                self.show_menu()
            else:
                self.hide_menu()
            return True

        if menu_type == 'fuzzy':
            if key_name == 'Down':
                if self.filtered_items:
                    self.selected_index = (self.selected_index + 1) % len(self.filtered_items)
                    self.render_items()
                return True
            elif key_name == 'Up':
                if self.filtered_items:
                    self.selected_index = (self.selected_index - 1) % len(self.filtered_items)
                    self.render_items()
                return True
            # Let SearchEntry handle all other keys
            return False

        # Which-key mode - map GTK key names to config keys
        key_map = {'slash': '/', 'backslash': '\\', 'space': ' '}
        key_char = key_map.get(key_name, key_name.lower() if len(key_name) == 1 else key_name)
        for item in self.filtered_items:
            if item.get('key', '').lower() == key_char:
                if item.get('_disabled'):
                    return True  # swallow keypress, do nothing
                self.execute_action(item)
                return True
        return False

    def execute_action(self, item):
        # Handle virtual items (custom input)
        if item.get('_virtual'):
            menu = self.current_menu()
            input_action = menu.get('inputAction', {})
            if 'exec' in input_action:
                cmd = input_action['exec'] + [item['label']]
                self.win.hide()
                GLib.timeout_add(50, self._spawn_action, cmd)
            return

        action = item.get('action', {})

        if 'menu' in action:
            self.menu_stack.append(action['menu'])
            self.show_menu()
        elif 'exec' in action:
            cmd = action['exec']
            self.win.hide()
            GLib.timeout_add(50, self._spawn_action, cmd)

    def _spawn_action(self, cmd):
        # Don't let a typo in menus.nix or a missing binary kill the daemon —
        # surface the failure as a desktop notification and stay alive.
        try:
            subprocess.Popen(cmd, start_new_session=True)
        except (FileNotFoundError, PermissionError, OSError) as e:
            try:
                subprocess.Popen(
                    ['notify-send', '-u', 'critical', 'which-key',
                     f"failed to run {cmd[0] if cmd else '<empty>'}: {e}"],
                    start_new_session=True,
                )
            except Exception:
                print(f"which-key: spawn failed: {cmd!r}: {e}", file=sys.stderr)
        return False  # Don't repeat


def main():
    if len(sys.argv) < 2:
        print("Usage: fluteos-which-key <config.json>", file=sys.stderr)
        sys.exit(1)

    Menu(sys.argv[1]).run()


if __name__ == '__main__':
    main()
