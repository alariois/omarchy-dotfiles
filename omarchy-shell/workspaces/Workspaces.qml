// Workspace indicators that know which monitor they are on.
//
// A clone of Omarchy's omarchy.workspaces (see setup/targets.sh for why a
// clone rather than an edit in place). Stock renders one marker, on
// Hyprland.focusedWorkspace -- a single global value -- so every bar on a
// multi-monitor desk draws the identical row. The laptop bar then claims the
// workspace that is focused on the *external* monitor is the current one,
// while saying nothing about the workspace that laptop is actually showing.
//
// A bar surface exists per monitor, so each instance can answer for its own
// screen instead. Three orthogonal channels carry three independent facts:
//
//   shape    what is on screen        filled square = this monitor is showing it
//                                     outline square = another monitor is
//                                     digit = not on screen anywhere
//   colour   where the keyboard is    accent = this monitor's workspace, and
//                                     this monitor has focus
//   opacity  which monitor owns it    full = this monitor's, faint = another
//                                     monitor's, faintest = does not exist yet
//
// So a glance at any one bar says which workspaces live on that screen, which
// one it is showing, which the other screens are showing, and which of them has
// the keyboard. On a single monitor it reduces to stock, plus the accent:
// nothing is foreign, so nothing is dimmed for ownership.
//
// Nothing here counts or names monitors, so a monitor plugged in later needs no
// restart -- the bar host instantiates a surface per Quickshell.screens entry
// and every lookup below is a scan of Hyprland's own live monitor list.
// Verified against `hyprctl output create headless`: the new bar came up with
// its own marker and the existing bars grew a second outline marker for it.
//
// Accent comes from Color.accent, which Commons/Color.qml loads from the
// theme's colors.toml and rebinds on a theme switch, so this follows
// `omarchy theme set` for free. Deliberately not Color.bar.active: that is
// shell.toml's `active`, documented as the colour for "modules calling
// attention to themselves" (recording, alerts, updates) and red in most
// themes, which is the wrong thing to say about the workspace you are on.
//
// Editing note: this directory is a symlink into the dotfiles repo, and the
// shell's plugin watcher does not see writes through it. Saving here does NOT
// hot-reload, and `omarchy-shell shell rescanPlugins` is not enough either --
// run `omarchy restart shell`.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import qs.Commons
import qs.Ui

BarWidget {
  id: root

  // Left as the built-in id on purpose: omarchy-plugin-clone keeps it so the
  // shell can route this widget's IPC through the manifest's `clonedFrom`.
  moduleName: "omarchy.workspaces"

  // Nerd Font md-square_rounded and md-square_rounded_outline (U+F14FB and
  // U+F14FC), as surrogate pairs. Consecutive codepoints in the same icon
  // family, so the filled and outline markers share their metrics and sit on
  // the same baseline. The filled one is what stock draws.
  readonly property string markerFilled: "󱓻"
  readonly property string markerOutline: "󱓼"

  // The ownership channel, in one place because it is the thing most worth
  // tuning by eye. Turn foreignOpacity down for a quieter bar; it is the only
  // number here that is a matter of taste rather than of meaning.
  readonly property real ownOpacity: 1.0
  readonly property real foreignOpacity: 0.45
  readonly property real ownerlessOpacity: 0.28

  // The monitor this bar surface is on. QsWindow.window is the panel window
  // the widget was instantiated into, and Hyprland.monitorFor maps its screen
  // onto the compositor's own monitor object.
  readonly property var barWindow: QsWindow.window
  readonly property var monitor: barWindow && barWindow.screen ? Hyprland.monitorFor(barWindow.screen) : null

  // Fall back to the global focused workspace when the monitor cannot be
  // resolved -- before Hyprland has reported its outputs, or on a screen it
  // does not know about. That is exactly stock behaviour, which is the right
  // thing to degrade to: a bar with no marker at all would look broken.
  readonly property bool monitorKnown: monitor !== null && monitor.activeWorkspace !== null
  readonly property int shownId: monitorKnown
    ? monitor.activeWorkspace.id
    : (Hyprland.focusedWorkspace !== null ? Hyprland.focusedWorkspace.id : -1)
  readonly property bool monitorFocused: monitorKnown ? monitor.focused === true : true
  readonly property string monitorName: monitorKnown ? String(monitor.name) : ""

  function workspaceById(id) {
    var values = Hyprland.workspaces.values
    for (var i = 0; i < values.length; i++) {
      if (values[i].id === id) return values[i]
    }

    return null
  }

  function workspaceIds() {
    var ids = [1, 2, 3, 4, 5]
    var values = Hyprland.workspaces.values

    for (var i = 0; i < values.length; i++) {
      var id = values[i].id
      if (id > 0 && id <= 10 && ids.indexOf(id) === -1) ids.push(id)
    }

    ids.sort(function(left, right) { return left - right })
    return ids
  }

  // Is some monitor other than this one showing this workspace? Reading
  // Hyprland.monitors and each activeWorkspace here is what registers the
  // dependency, so the delegate bindings that call this re-evaluate when a
  // workspace moves -- QML tracks property reads through function calls.
  function shownElsewhere(id) {
    if (id === root.shownId) return false

    var monitors = Hyprland.monitors.values
    for (var i = 0; i < monitors.length; i++) {
      var active = monitors[i].activeWorkspace
      if (active !== null && active.id === id) return true
    }

    return false
  }

  function focusWorkspace(id) {
    if (!root.bar) return
    root.bar.run("hyprctl dispatch " + Util.shellQuote("hl.dsp.focus({ workspace = \"" + id + "\" })"))
  }

  readonly property real trailingGap: root.vertical ? 0 : Style.spaceReal(1.5)

  implicitWidth: grid.implicitWidth + trailingGap
  implicitHeight: grid.implicitHeight

  GridLayout {
    id: grid
    anchors.fill: parent
    anchors.rightMargin: root.trailingGap
    columns: root.vertical ? 1 : root.workspaceIds().length
    columnSpacing: root.vertical ? 0 : Style.space(1)
    rowSpacing: root.vertical ? Style.space(2) : 0

    Repeater {
      model: root.workspaceIds()

      WidgetButton {
        required property int modelData

        readonly property var workspace: root.workspaceById(modelData)

        // Shown on this monitor, versus shown on one of the others. Mutually
        // exclusive by shownElsewhere's first line.
        readonly property bool shownHere: modelData === root.shownId
        readonly property bool shownAway: root.shownElsewhere(modelData)

        // Which monitor this workspace lives on. Hyprland binds a workspace to
        // the output it was created on, and that is what decides where pressing
        // the number takes you -- so it is worth saying out loud on every bar,
        // not just on the one that owns it.
        //
        // A workspace with no owner is one that does not exist yet: the widget
        // always draws 1-5 whether or not Hyprland has them, and Hyprland drops
        // an empty workspace as soon as it stops being shown. Pressing one of
        // those creates it on whichever monitor has focus, so it belongs to no
        // screen in particular and is dimmed hardest.
        readonly property var owner: workspace !== null ? workspace.monitor : null
        readonly property bool owned: owner !== null
        readonly property bool foreign: root.monitorName !== "" && owned && String(owner.name) !== root.monitorName

        bar: root.bar
        text: shownHere ? root.markerFilled : (shownAway ? root.markerOutline : (modelData === 10 ? "0" : String(modelData)))

        // WidgetButton paints activeColor when `active`, so the accent is only
        // ever asked for on the one marker that earns it: this monitor's
        // workspace, on the monitor holding focus. Everything else keeps the
        // bar's own foreground, which is the grey it has always been.
        active: shownHere && root.monitorFocused
        activeColor: Color.accent

        // Opacity is the ownership channel, and nothing else -- what is on
        // screen is the shape's job. `shownHere` leads so this monitor's own
        // marker is never dimmed, and so the fallback path (monitorName empty,
        // nothing foreign) still lights the one marker it draws.
        //
        // Foreign is the brighter of the two faint steps on purpose. A
        // workspace another screen is holding is more real than one that does
        // not exist, and the other way round reads as though an empty slot
        // mattered more than a screenful of windows.
        opacity: shownHere
          ? root.ownOpacity
          : (foreign ? root.foreignOpacity : (owned ? root.ownOpacity : root.ownerlessOpacity))

        horizontalMargin: 6
        verticalPadding: 6
        fixedWidth: root.vertical ? root.barSize : Style.space(20)
        fixedHeight: root.barSize
        onPressed: function() { root.focusWorkspace(modelData) }
      }
    }
  }
}
