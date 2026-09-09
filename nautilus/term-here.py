"""Record what each Nautilus window is showing, for bin/term-here to read.

SUPER+RETURN opens a terminal in the focused *terminal's* directory -- that is
stock Omarchy, via omarchy-cmd-terminal-cwd, which reads /proc/<shell>/cwd.
There is no equivalent for a file manager: Nautilus does not publish its
location anywhere a keybinding can reach. Its D-Bus surface is
org.freedesktop.FileManager1 (ShowItems/ShowFolders -- all setters, no
getters) plus org.gtk.Actions, whose window action states carry navigation
commands and no path. The window title is the folder's display name, not a
path. So the location has to come from inside the process, which means an
extension.

This is that extension: it keeps no menu items and exists only for the
callbacks. Nautilus rebuilds its extension menus *eagerly* -- on every
selection change and every navigation, not when a context menu is opened --
so MenuProvider is a usable notification hook, and in Nautilus 50 it is the
only one left. The 4.1 API exposes MenuProvider, InfoProvider, ColumnProvider
and PropertiesModelProvider; LocationWidgetProvider, which would have been the
honest choice, is gone.

Both callbacks return [] on purpose. Adding a real menu item would be a
separate feature; nothing here should change what a right-click looks like.

Keyed by window title, because that is the one identifier both sides can see:
the callbacks carry no window handle, but Gtk.Window.list_toplevels() finds
the active one from in-process, and the title it reports is byte-identical to
the `title` Hyprland reports for the same window. Focus changes alone do not
fire these callbacks, so without the key a second window would answer with the
first one's directory.

Requires nautilus-python, which is on Omarchy's own base package list.
Nautilus loads extensions at startup, so a fresh install needs one
`nautilus -q` before this takes effect.
"""

import json
import os
import time

from gi import require_version

require_version("Nautilus", "4.1")
require_version("Gtk", "4.0")

from gi.repository import GObject, Gtk, Nautilus

# Runtime state, not config: it describes windows that exist right now, so it
# belongs on the tmpfs that dies with the session rather than in ~/.local/state.
STATE = os.path.join(
    os.environ.get("XDG_RUNTIME_DIR") or "/run/user/%d" % os.getuid(),
    "omarchy-dotfiles",
    "nautilus-location.json",
)

# Enough for every window anyone keeps open; stale titles cost nothing but are
# not worth growing the file forever either.
KEEP = 16


def _path(file_info):
    """Local filesystem path behind a Nautilus.FileInfo, or None.

    None covers the URIs that have no path at all -- trash:///, recent:///,
    a search result on a remote mount -- which a terminal cannot cd into.
    """
    location = file_info.get_location() if file_info else None
    return location.get_path() if location else None


def _active_title():
    """Title of the Nautilus window the user is actually in, or None.

    A dialog (Properties, say) can be the active toplevel, which would file the
    record under the dialog's title instead. Harmless: bin/term-here looks the
    focused window's own title up, and never asks for a title no window has.
    """
    for window in Gtk.Window.list_toplevels():
        if window.is_active():
            return window.get_title() or None
    return None


class TermHereLocation(GObject.GObject, Nautilus.MenuProvider):
    def __init__(self):
        super().__init__()
        self._windows = {}
        self._selection = []
        self._written = None

    # Fires on every selection change, including a change *to* nothing.
    def get_file_items(self, *args):
        # nautilus-python passed (window, files) before 4.0 and (files) since.
        files = args[0] if len(args) == 1 else args[1]
        paths = [p for p in (_path(f) for f in files) if p]
        self._selection = paths
        # Derive the folder from the selection so this callback alone leaves a
        # complete record, rather than depending on the order of the pair.
        self._record(os.path.dirname(paths[0]) if paths else None, paths)
        return []

    # Fires alongside the above, and on navigation.
    def get_background_items(self, *args):
        folder = args[0] if len(args) == 1 else args[1]
        self._record(_path(folder), self._selection)
        # Cleared, not kept: if a future Nautilus stops calling get_file_items
        # for an empty selection, this is what keeps a stale filename from
        # being reported for a window that no longer has one selected.
        self._selection = []
        return []

    def _record(self, folder, selection):
        title = _active_title()
        if not title:
            return

        if not folder:
            # An empty selection carries no folder to derive. Keep the one this
            # window already had; drop the record entirely if it has none yet,
            # since the paired background callback is about to supply it.
            previous = self._windows.get(title)
            folder = previous.get("folder") if previous else None
            if not folder:
                return

        self._windows[title] = {
            "folder": folder,
            "selection": selection,
            "ts": time.time(),
        }

        if len(self._windows) > KEEP:
            for stale in sorted(self._windows, key=lambda t: self._windows[t]["ts"])[
                : len(self._windows) - KEEP
            ]:
                del self._windows[stale]

        self._write()

    def _write(self):
        # The two callbacks of a pair normally compute the same state, so this
        # halves the writes -- and skips them entirely while arrowing through a
        # folder full of directories.
        payload = json.dumps({"windows": self._windows}, sort_keys=True)
        if payload == self._written:
            return

        tmp = "%s.%d.tmp" % (STATE, os.getpid())
        try:
            os.makedirs(os.path.dirname(STATE), exist_ok=True)
            with open(tmp, "w") as handle:
                handle.write(payload)
            os.replace(tmp, STATE)
        except OSError:
            # A file manager that cannot write a hint file should still be a
            # working file manager. bin/term-here falls back to stock behaviour.
            try:
                os.unlink(tmp)
            except OSError:
                pass
            return

        self._written = payload
