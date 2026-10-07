"""The meeting as it is being said: a floating window, split by speaker.

    fluteos-record-live-window <recording-dir>

Reads what fluteos-record-live writes — live.jsonl for finalised turns,
.live-interim for the line still being spoken — and nothing else. It holds no
connection, owns no audio, and can be closed and reopened mid-meeting without
touching the recording: everything on screen is rebuilt from the two files.

Polled rather than watched. An append every few seconds does not justify a
file monitor, and a poll cannot miss the case that matters here — a rewritten
interim file — which is exactly what inotify coalescing makes fiddly.

The window is a plain GtkApplicationWindow with a stable application id, so
niri addresses it by app-id and the floating rule lives with the other window
rules rather than as a special case in here.
"""
import gi
import json
import os
import sys

gi.require_version('Gtk', '4.0')
from gi.repository import Gtk, Gdk, GLib, Gio

APP_ID = 'com.fluteos.RecordLive'
POLL_MS = 250

# Falls back to something readable if the theme did not reach us: the window is
# for reading a live conversation, and unstyled-but-legible beats not opening.
DEFAULTS = {
    'bg': '#1e1e2e',
    'fg': '#cdd6f4',
    'dim': '#6c7086',
    'speakers': ['#89b4fa', '#a6e3a1', '#f9e2af', '#f38ba8', '#cba6f7', '#94e2d5'],
}


def theme():
    palette = dict(DEFAULTS)
    for key in ('bg', 'fg', 'dim'):
        value = os.environ.get('LIVE_' + key.upper(), '').strip()
        if value:
            palette[key] = value
    speakers = os.environ.get('LIVE_SPEAKERS', '').strip()
    if speakers:
        palette['speakers'] = [c.strip() for c in speakers.split(',') if c.strip()]
    return palette


def hhmmss(seconds):
    seconds = int(seconds or 0)
    return f'{seconds // 3600:02d}:{(seconds % 3600) // 60:02d}:{seconds % 60:02d}'


class Window(Gtk.Application):
    def __init__(self, directory):
        super().__init__(application_id=APP_ID, flags=Gio.ApplicationFlags.FLAGS_NONE)
        self.directory = directory
        self.jsonl = os.path.join(directory, 'live.jsonl')
        self.interim_path = os.path.join(directory, '.live-interim')
        self.offset = 0
        self.pending = ''
        self.last_speaker = None
        self.last_label = None
        self.last_text = ""
        self.interim_text = ''
        self.palette = theme()

    # --- window ------------------------------------------------------------

    def do_activate(self):
        self.win = Gtk.ApplicationWindow(application=self)
        self.win.set_title('Recording')
        self.win.set_default_size(620, 520)

        header = Gtk.Label(label=os.path.basename(self.directory))
        header.add_css_class('meeting')
        header.set_xalign(0)

        self.turns_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=16)
        self.turns_box.add_css_class('turns')

        self.scroller = Gtk.ScrolledWindow()
        self.scroller.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        self.scroller.set_vexpand(True)
        self.scroller.set_child(self.turns_box)

        # The line still being spoken has NO place of its own. It used to live
        # in a strip along the bottom of the window, and finalising it moved
        # the words from there up into the transcript — so the eye read a
        # sentence in one place and then had to find it again somewhere else,
        # several times a minute. It is now drawn where it will end up, dimmed,
        # at the end of the current speaker's paragraph: finalising it changes
        # its colour and nothing else.
        self.tail = None

        self.waiting = Gtk.Label(label='listening…')
        self.waiting.add_css_class('interim')
        self.waiting.set_xalign(0)

        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        box.add_css_class('root')
        box.append(header)
        box.append(self.scroller)
        self.turns_box.append(self.waiting)

        # Escape closes the window, not the recording. The two are deliberately
        # separate: this is a view, and losing sight of a meeting must never be
        # the same gesture as ending it.
        keys = Gtk.EventControllerKey()
        keys.connect('key-pressed', self.on_key)
        self.win.add_controller(keys)

        self.win.set_child(box)
        self.apply_css()
        self.win.present()

        GLib.timeout_add(POLL_MS, self.poll)

    def on_key(self, _controller, keyval, _code, _state):
        if keyval == Gdk.KEY_Escape:
            self.win.close()
            return True
        return False

    def apply_css(self):
        p = self.palette
        speaker_css = '\n'.join(
            f'.speaker-{i} {{ color: {colour}; }}'
            for i, colour in enumerate(p['speakers'])
        )
        css = f'''
        window {{ background-color: {p['bg']}; }}
        .root {{ padding: 20px; }}
        .turns {{ padding-right: 10px; }}

        /* One reading size for everything that is speech — a said line, the
           line still being said, and the note that says a piece is missing all
           sit in the same column and are read in one pass, so they are set the
           same. Only the two labels ABOUT the text, never part of it, are
           smaller: who is speaking, and which meeting this is. */
        .said, .interim, .gap {{ font-size: 19px; line-height: 1.45; }}
        .said {{ color: {p['fg']}; }}
        .interim {{ color: {p['dim']}; font-style: italic; }}
        .gap {{ color: {p['dim']}; }}

        .who {{ font-size: 14px; font-weight: bold; }}
        .meeting {{ color: {p['dim']}; font-size: 14px; }}
        {speaker_css}
        '''
        provider = Gtk.CssProvider()
        provider.load_from_data(css.encode())
        Gtk.StyleContext.add_provider_for_display(
            Gdk.Display.get_default(),
            provider,
            Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION,
        )

    # --- content -----------------------------------------------------------

    def add_turn(self, turn):
        if self.waiting is not None:
            self.turns_box.remove(self.waiting)
            self.waiting = None
        if self.tail is not None:
            self.turns_box.remove(self.tail)
            self.tail = None
        # What has just been finalised is what the preview was showing, so the
        # preview is spent. Leaving it would print the same words twice for the
        # quarter-second until the file catches up.
        self.interim_text = ''
        # And it has to be taken off the paragraph it was drawn on, HERE rather
        # than wherever the new text lands. Deepgram frequently finalises a
        # preview onto a different speaker than the one talking when it was
        # shown; the new paragraph then held the words in white while the old
        # one still held them in grey, and the same sentence appeared twice.
        if self.last_label is not None:
            self.last_label.set_markup(GLib.markup_escape_text(self.last_text))

        if turn.get('gap'):
            label = Gtk.Label(label=f"[{hhmmss(turn.get('start'))}] connection lost — "
                                    "speaker numbers restart")
            label.add_css_class('gap')
            label.set_xalign(0)
            label.set_wrap(True)
            self.turns_box.append(label)
            self.last_speaker = None
            self.last_label = None
            self.last_text = ''
            return

        speaker = int(turn.get('speaker') or 0)

        # Deepgram finalises a turn in pieces. Appending to the label already on
        # screen is what makes a paragraph grow as somebody keeps talking,
        # instead of a column of one-line fragments.
        if speaker == self.last_speaker and self.last_label is not None:
            self.last_text += ' ' + turn['text']
            self.last_label.set_markup(GLib.markup_escape_text(self.last_text))
            self.scroll_down()
            return

        row = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)

        who = Gtk.Label(label=f"Speaker {speaker} · {hhmmss(turn.get('start'))}")
        who.add_css_class('who')
        who.add_css_class(f'speaker-{speaker % len(self.palette["speakers"])}')
        who.set_xalign(0)

        said = Gtk.Label(label=turn['text'])
        said.add_css_class('said')
        said.set_xalign(0)
        said.set_wrap(True)

        row.append(who)
        row.append(said)
        self.turns_box.append(row)

        self.last_speaker = speaker
        self.last_text = turn["text"]
        self.last_label = said
        self.scroll_down()

    def scroll_down(self):
        # After the widget has been laid out, not before: the adjustment's
        # upper bound is still the old one during this frame.
        def go():
            adjustment = self.scroller.get_vadjustment()
            adjustment.set_value(adjustment.get_upper() - adjustment.get_page_size())
            return False
        GLib.idle_add(go)

    def read_new_turns(self):
        try:
            size = os.path.getsize(self.jsonl)
        except OSError:
            return
        # A recording that was restarted into the same window: the file got
        # shorter, so what we have on screen is not a prefix of it any more.
        if size < self.offset:
            self.offset = 0
            self.pending = ''
        if size == self.offset:
            return
        try:
            with open(self.jsonl, 'r', encoding='utf-8') as handle:
                handle.seek(self.offset)
                self.pending += handle.read()
                self.offset = handle.tell()
        except OSError:
            return

        lines = self.pending.split('\n')
        # The last element is whatever follows the final newline: either empty,
        # or half a line that is still being written. Either way it is kept for
        # the next poll rather than parsed now.
        self.pending = lines.pop()
        for line in lines:
            line = line.strip()
            if not line:
                continue
            try:
                self.add_turn(json.loads(line))
            except (ValueError, KeyError):
                continue

    def read_interim(self):
        text = ''
        try:
            with open(self.interim_path, encoding='utf-8') as handle:
                text = handle.read().strip()
        except OSError:
            text = ''
        if text == self.interim_text:
            return
        self.interim_text = text
        self.render_interim()

    def render_interim(self):
        """Draw the unfinished line at the end of the paragraph it belongs to.

        Attached to the current speaker's label when there is one, so the words
        do not move when they are finalised. Only when nobody has spoken yet —
        or the last thing on screen was a gap — does it need a line of its own,
        and that line sits where the next paragraph will start.
        """
        text = self.interim_text
        if self.last_label is not None:
            said = GLib.markup_escape_text(self.last_text)
            if text:
                dim = GLib.markup_escape_text(text)
                said += f' <span foreground="{self.palette["dim"]}">{dim}</span>'
            self.last_label.set_markup(said)
            self.scroll_down()
            return

        if not text:
            if self.tail is not None:
                self.turns_box.remove(self.tail)
                self.tail = None
            return

        if self.tail is None:
            if self.waiting is not None:
                self.turns_box.remove(self.waiting)
                self.waiting = None
            self.tail = Gtk.Label(label='')
            self.tail.add_css_class('interim')
            self.tail.set_xalign(0)
            self.tail.set_wrap(True)
            self.turns_box.append(self.tail)
        self.tail.set_label(text)
        self.scroll_down()

    def poll(self):
        self.read_new_turns()
        self.read_interim()
        return True


def main():
    if len(sys.argv) < 2 or not os.path.isdir(sys.argv[1]):
        print('usage: fluteos-record-live-window <recording-dir>', file=sys.stderr)
        return 2
    return Window(sys.argv[1]).run([])


if __name__ == '__main__':
    sys.exit(main())
