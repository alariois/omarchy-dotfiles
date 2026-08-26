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
-- motion belongs: it inspects the focused window, and if that window is a
-- terminal running tmux with vim in the active pane it forwards M-hjkl to vim,
-- which calls back with --from-vim once the cursor is at the edge of its
-- splits. Otherwise it moves a tmux pane, and failing that a Hyprland window.
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
