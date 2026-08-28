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
-- code path only ever raises toasts -- see bin/mail-otp.
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
o.window("^(mail-peek)$", {
  float = true,
  center = true,
  size = { 900, 720 },
  tag = "-default-opacity",
  opacity = "1.0 1.0",
})

o.bind("SUPER + ALT + M", "Latest mail",
  "setsid uwsm-app -- xdg-terminal-exec --app-id=mail-peek --title=Mail -e mail-peek")
o.bind("SUPER + ALT + CTRL + M", "Copy login code", "mail-otp")
