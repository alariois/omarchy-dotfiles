-- Personal Hyprland configuration with no stock file of its own: window rules.
--
-- Hooked into ~/.config/hypr/hyprland.lua by setup/install.sh. That file ends
-- with the place Omarchy leaves for "any other personal Hyprland
-- configuration", after require("default.hypr.toggles"), and our block lands
-- right there.
--
-- `o` is Omarchy's helper table (default/hypr/helpers.lua), set up before
-- this runs. A string match in o.window is a regex on the window class.

-- Assign Slack to workspace 5. Add " silent" to open it there without
-- following focus (useful if Slack is autostarted).
o.window("^([Ss]lack)$", { workspace = "5" })
