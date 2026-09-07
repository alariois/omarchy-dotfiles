-- Personal Hyprland keybindings.
--
-- Hooked into ~/.config/hypr/bindings.lua by setup/install.sh. Omarchy ships
-- that file as pure comments -- it is the designated place for personal
-- bindings -- so our block appends a dofile of this one.
--
-- `o` and `hl` are globals set up by Omarchy's bootstrap before this runs.

-- Alt+hjkl: one motion for vim splits, tmux panes, and Hyprland windows.
--
-- Hyprland has to own these keys rather than tmux or nvim, because it is the
-- only layer that sees the keypress first. hypr-nav then decides where the
-- motion belongs by inspecting the focused window: tmux with vim in the active
-- pane gets M-hjkl through send-keys; a bare vim with no tmux gets a real
-- ALT+hjkl through send_shortcut; either way vim calls back with --from-vim
-- once the cursor is at the edge of its splits. Failing all that it moves a
-- tmux pane, and failing that a Hyprland window.
--
-- Requires:
--   * the hypr-nav binary on PATH -- built and installed to ~/.local/bin by
--     setup/install.sh, which the uwsm session picks up via Omarchy's
--     default/bash/env-bootstrap.
--   * `set -g focus-events on` in tmux, which stock Omarchy already sets.
--     hypr-nav identifies the right tmux client by its "focused" flag, since
--     multi-window terminals share one PID across every window.
--   * nvim/plugins/hypr-nav.lua for the vim half of the hand-off.
--
-- No unbind needed: Omarchy's defaults leave ALT + hjkl free.
o.bind("ALT + H", "Navigate left", "hypr-nav l")
o.bind("ALT + J", "Navigate down", "hypr-nav d")
o.bind("ALT + K", "Navigate up", "hypr-nav u")
o.bind("ALT + L", "Navigate right", "hypr-nav r")

-- SUPER + SHIFT + G: Gmail, in place of Omarchy's Signal.
--
-- The unbind is required, not tidiness. Omarchy binds this key in
-- default/hypr/bindings/applications.lua, and its o.bind() throws away the
-- handle hl.bind() returns -- so unlike Omarchy's own examples there is no
-- object here to call :set_enabled(false) on. Binding over it without the
-- unbind leaves *both* registered: `hyprctl binds` then lists Signal and
-- Gmail on SUPER+SHIFT+G, which is ambiguous at best.
--
-- Unbinding by key works because this file is dofile'd from the user's
-- bindings.lua, which Omarchy loads after its own defaults, so the key is
-- already taken by the time we get here.
--
-- `{ webapp = ..., focus = true }` is Omarchy's own vocabulary: it resolves
-- to `omarchy-launch-or-focus-webapp "Gmail" "<url>"`, so a second press
-- focuses the existing window instead of opening another.
hl.unbind("SUPER + SHIFT + G")
o.bind("SUPER + SHIFT + G", "Gmail", { webapp = "https://mail.google.com/", focus = true })

-- SUPER + ALT + M: the newest mail, in a floating window.
-- SUPER + ALT + CTRL + M: its login code, straight onto the clipboard.
--
-- Two shapes for two jobs. Reading wants a window you can scroll and dismiss;
-- grabbing a code wants no window at all, because you are mid-login in another
-- app and a window would steal the focus you are about to type into. So the
-- code path only ever raises toasts -- see bin/msg-otp.
--
-- The window rule lives here rather than in a windows file because it is not
-- really a window rule: it is half of this binding. --app-id is what ties them
-- together, and it is a private id rather than the terminal's own, so the rule
-- cannot catch an ordinary terminal.
--
-- uwsm-app matches how Omarchy launches everything else, which keeps the
-- window in the right systemd scope rather than parented to Hyprland.
-- Opaque on purpose. Omarchy tags every window with default-opacity, which is
-- fine for a terminal you are typing in and wrong for one you are reading:
-- whatever sits behind shows through the message body.
o.window("^(msg-peek)$", {
  float = true,
  center = true,
  size = { 900, 720 },
  tag = "-default-opacity",
  opacity = "1.0 1.0",
})

o.bind("SUPER + ALT + M", "Latest message",
  "setsid uwsm-app -- xdg-terminal-exec --app-id=msg-peek --title=Messages -e msg-peek")
o.bind("SUPER + ALT + CTRL + M", "Copy login code", "msg-otp")

-- SUPER + SHIFT + S: Slack, in place of Omarchy's Google Maps.
--
-- The unbind is required for the same reason as Gmail's above: Omarchy's
-- o.bind() drops the hl.bind() handle, so there is no object to disable and
-- binding over the key would leave both entries registered.
--
-- Goes through bin/slack-launch rather than launching a Desktop Entry ID,
-- because Slack is the only thing on this row that has to be *installed*: it
-- is a native app and slack-desktop is AUR-only. A VM install answered this
-- key with "slack does not exist" and left it there. The script is shaped like
-- omarchy-launch-spotify, which is what SUPER+SHIFT+M does: focus a window if
-- one is open, launch if the app is present, and otherwise ask -- with gum, in
-- a floating terminal, where sudo can also be answered.
--
-- The window match lives in that script and is still anchored to `^slack$`,
-- for the reason it always was: Slack puts "Slack" in its own window titles,
-- so an unanchored pattern matches any window merely *about* Slack -- a
-- browser tab, or a terminal with it in the prompt -- with no ordering
-- guarantee about which wins. The class is lowercase.
--
-- The flags still live in a Desktop Entry, now tracked as slack/slack.desktop
-- and linked over ~/.local/share/applications/slack.desktop, so a launch from
-- the app menu gets them too. --enable-wayland-ime is the load-bearing one:
-- without it the Compose key does nothing inside Slack. Contrary to what this
-- comment said before, --ozone-platform-hint=auto is not what keeps Electron
-- off XWayland -- Omarchy sets ELECTRON_OZONE_PLATFORM_HINT=wayland globally
-- in default/hypr/envs.lua, which is stronger.
hl.unbind("SUPER + SHIFT + S")
o.bind("SUPER + SHIFT + S", "Slack", "slack-launch")

-- SUPER + SHIFT + W: WhatsApp, in place of Omarchy's Omawrite.
-- SUPER + SHIFT + Q: Messenger. Both open on workspace 5, next to Slack.
--
-- W needs the unbind for the same reason as Gmail's and Slack's above:
-- Omarchy's o.bind() drops the hl.bind() handle, so there is no object to
-- disable and binding over the key would leave both entries registered. Q
-- needs none -- stock Omarchy leaves SUPER + SHIFT + Q free (the calculator
-- is on SUPER + CTRL + Q).
--
-- Matched on class rather than through `{ webapp = ..., focus = true }`. That
-- sugar hands the *description* to omarchy-launch-or-focus-webapp, which tests
-- it as `\b<pattern>\b`, case-insensitively, against class *and* title -- so
-- "WhatsApp" or "Messenger" would focus any window merely titled that, and a
-- browser tab on facebook.com/messages is exactly such a window. Spelling the
-- command out pins each key to the window Chromium actually creates.
--
-- The class comes from Chromium's --app=<url>: `chrome-<host>__<path>-Default`,
-- with "/" written as "_". Anchoring is left to the `\b` the helper adds; the
-- pattern stops before `-Default` so it survives a non-default profile.
hl.unbind("SUPER + SHIFT + W")
o.bind("SUPER + SHIFT + W", "WhatsApp",
  "omarchy-launch-or-focus-webapp 'chrome-web\\.whatsapp\\.com__' 'https://web.whatsapp.com/'")
o.bind("SUPER + SHIFT + Q", "Messenger",
  "omarchy-launch-or-focus-webapp 'chrome-www\\.facebook\\.com__messages' 'https://www.facebook.com/messages'")

-- Same two classes, as plain regexes this time -- window rules match on their
-- own, without the helper's `\b` wrapping.
--
-- `workspace` is Hyprland's "open here" rule and takes a string. It is not
-- `pin`, which means "show on every workspace". Deliberately not "5 silent":
-- pressing the key should land you on the window, and silent would open it out
-- of sight on a workspace you are not looking at.
o.window("^chrome-web\\.whatsapp\\.com__.*$", { workspace = "5" })
o.window("^chrome-www\\.facebook\\.com__messages.*$", { workspace = "5" })

-- SUPER + SHIFT + C: Google Calendar, in place of Omarchy's HEY calendar.
--
-- Unbound first for the usual reason (see the Gmail block): Omarchy binds this
-- key to https://app.hey.com/calendar/weeks/ in
-- default/hypr/bindings/applications.lua and keeps no handle to disable.
--
-- Class-matched rather than by description, for the reason spelled out in the
-- WhatsApp block above -- "Calendar" is if anything a worse pattern than
-- "Messenger", since it turns up in the title of any mail or event page.
--
-- No workspace rule here, unlike WhatsApp and Messenger. Those are chat and
-- belong parked with Slack on 5; a calendar is something you glance at from
-- wherever you already are, and pinning it would drag you off the workspace
-- you were working on.
hl.unbind("SUPER + SHIFT + C")
o.bind("SUPER + SHIFT + C", "Google Calendar",
  "omarchy-launch-or-focus-webapp 'chrome-calendar\\.google\\.com__calendar' 'https://calendar.google.com/calendar'")

-- YouTube (SUPER + SHIFT + Y, Omarchy's own binding) opens on workspace 6.
--
-- No bind or unbind here: Omarchy's default already launches and focuses the
-- web app, and this repo wants only the workspace. Video is the one thing that
-- should never share a workspace with what you are working on -- it is either
-- what you are watching or it is in the way -- so it gets a workspace of its
-- own, one past the chat corner on 5.
--
-- Matched with Omarchy's own pattern for this window rather than the
-- `^chrome-...` shape used above, since default/hypr/apps/browser.lua already
-- catches it as `^.+-youtube\.com__.*$` -- browser-agnostic, so it still holds
-- if the default browser stops being Chromium. Not "6 silent", for the reason
-- given in the WhatsApp block: pressing the key should take you to the video.
o.window("^.+-youtube\\.com__.*$", { workspace = "6" })
