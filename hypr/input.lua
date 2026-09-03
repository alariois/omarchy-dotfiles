-- Personal Hyprland input configuration.
--
-- Hooked into ~/.config/hypr/input.lua by setup/install.sh. Omarchy ships that
-- file as pure comments -- it is the designated place for input overrides --
-- so our block appends a dofile of this one.

-- Keyboard remapping. The two custom:* options are defined by this repo in
-- xkb/symbols/custom, linked to ~/.config/xkb; they are not stock xkb options
-- and nothing outside this repo provides them.
--
--   custom:caps_esc_compose   Caps Lock -> Escape, Escape -> Compose
--   custom:ralt_super         Right Alt -> a second Super
--   shift:both_capslock_cancel  Omarchy's default, kept: it is what still gives
--                               a Caps Lock, on both Shifts together, now that
--                               the Caps key itself is Escape.
--
-- This deliberately drops Omarchy's `compose:caps`, which would fight
-- custom:caps_esc_compose over the same key. Compose moves to the Escape key
-- and ~/.XCompose depends on it existing somewhere -- without a Compose key,
-- every expansion in that file is dead.
--
-- Only kb_options is set, so Omarchy keeps deriving kb_layout and kb_variant
-- from /etc/vconsole.conf. Note that its `grp:alts_toggle` for a leading
-- non-Latin layout is not reproduced here; add it if kb_layout ever gains one.
--
-- Check a change before applying it, no reload required:
--   xkbcli compile-keymap --layout us \
--     --options custom:caps_esc_compose,custom:ralt_super
hl.config({
  input = {
    kb_options = "custom:caps_esc_compose,custom:ralt_super,shift:both_capslock_cancel",

    -- Ported from `main`. Stock Omarchy 4 is 250; this is the delay before a
    -- held key starts repeating, in ms, so a longer one is less twitchy.
    repeat_delay = 300,
  },
})

-- Touchpad scroll direction. Stock Omarchy leaves natural_scroll off, which is
-- the "traditional" direction: two fingers down scrolls the view down, so the
-- content moves up under them. This flips it to the macOS behaviour, where the
-- content follows the fingers.
--
-- Set in its own hl.config call rather than merged above so the keyboard block
-- keeps its own comment; Hyprland applies both.
hl.config({
  input = {
    touchpad = {
      natural_scroll = true,
    },
  },
})
