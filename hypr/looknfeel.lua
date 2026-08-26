-- Personal Hyprland look and feel.
--
-- Hooked into ~/.config/hypr/looknfeel.lua by setup/install.sh. Omarchy ships
-- that file as pure comments -- it is the designated place for these -- so our
-- block appends a dofile of this one.
--
-- `hl` is a global set up by Omarchy's bootstrap before this runs. hl.config
-- merges into the running config rather than replacing it, so naming only the
-- keys we change leaves border_size, layout and the theme's colours alone.
--
-- Ported from `main`, where these lived in ~/.config/hypr/looknfeel.conf.
-- Stock Omarchy 4 is gaps 5/10 with square corners.

hl.config({
  general = {
    gaps_in = 4,
    gaps_out = 4,
  },
  decoration = {
    rounding = 4,
  },
})
