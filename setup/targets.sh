# Single source of truth for the delta model.
#
# Two lanes, chosen by who owns the live file.
#
# HOOKS -- files Omarchy owns and rewrites. We leave them stock and append one
# managed block holding a single include that points back into this repo.
#
#   <target file>|<comment style>|<repo-relative file to include>
#
# Styles:
#   sh   -> `#`  comments, `source "<path>"`
#   tmux -> `#`  comments, `source-file "<path>"`
#   lua  -> `--` comments, `dofile("<path>")`
#   ini  -> `#`  comments, `[main]` + `include=<path>` (foot)
#   xcompose -> `#` comments, `include "<path>"` (X Compose)
#
# The block is appended last, so an include that reassigns a setting the stock
# file above it already set wins. That is how nvim/options.lua overrides
# Omarchy's relativenumber.
#
# LINKS -- files and directories Omarchy never writes. The live path becomes a
# symlink into this repo, so no drift is possible: the live file *is* the repo
# file. Prefer this lane; it needs no repair after an update.
#
#   <target path>|<repo-relative file or directory>
#
# Do not link a path Omarchy migrates -- a migration `mv`s over its target and
# would replace the link with a regular file. Whole directories are safe to
# link only when Omarchy owns nothing inside them.

HOOKS=(
  "$HOME/.bashrc|sh|shell/bashrc"
  "$HOME/.config/tmux/tmux.conf|tmux|tmux/tmux.conf"
  "$HOME/.config/nvim/lua/config/options.lua|lua|nvim/options.lua"
  "$HOME/.config/hypr/bindings.lua|lua|hypr/bindings.lua"
  "$HOME/.config/hypr/input.lua|lua|hypr/input.lua"
  "$HOME/.config/hypr/looknfeel.lua|lua|hypr/looknfeel.lua"
  "$HOME/.config/foot/foot.ini|ini|foot/foot.ini"

  # A hook, not a link, though it was a link until a fresh 4.0.2 machine said
  # otherwise. install/user/xcompose.sh does `tee ~/.XCompose` during the
  # Omarchy install, writing an emoji include plus <space> <n>/<e> identity
  # expansions from the installer's own answers -- so on every new machine this
  # file exists and is Omarchy's, and the LINKS lane reported a CONFLICT
  # forever. It only ever worked here because that tee runs at install and not
  # on update, so an existing symlink survived and hid the problem.
  #
  # Appending is exactly right rather than merely tolerable: our block lands
  # below Omarchy's, and a later Compose definition wins, so our <space> <n>
  # overrides theirs. Verified -- `xkbcli compile-compose` on the hooked shape
  # exits 0 with no warnings, and dumping the table shows <space> <n> resolving
  # to ours, not the value Omarchy wrote.
  "$HOME/.XCompose|xcompose|xcompose/XCompose"
)

LINKS=(
  # Entirely ours: Omarchy ships no nvim-chad and never looks at it.
  "$HOME/.config/nvim-chad|nvim-chad"

  # Additions to Omarchy's LazyVim. lazy.nvim imports every file under
  # lua/plugins/, and Omarchy's migrations only ever touch files it shipped
  # (options.lua, remote_clipboard.lua, theme.lua), so dropping new files in
  # beside them is safe -- link the files, never the directory.
  "$HOME/.config/nvim/lua/plugins/hypr-nav.lua|nvim/plugins/hypr-nav.lua"
  "$HOME/.config/nvim/lua/plugins/telescope-find-all.lua|nvim/plugins/telescope-find-all.lua"


  # Gmail over IMAP for scripting, plus the helper that reads it. Omarchy
  # ships nothing under ~/.config/himalaya, and ~/.local/bin is already on the
  # session PATH for hypr-nav's sake. No secret is tracked: the config fetches
  # the app password from gnome-keyring at run time.
  "$HOME/.config/himalaya/config.toml|himalaya/config.toml"
  "$HOME/.local/bin/msgs|bin/msgs"
  "$HOME/.local/bin/msg-code|bin/msg-code"
  "$HOME/.local/bin/msg-peek|bin/msg-peek"
  "$HOME/.local/bin/msg-otp|bin/msg-otp"

  # Slack, which is the only thing on the SUPER+SHIFT row that has to be
  # installed rather than just launched -- it is a native app, and
  # slack-desktop is AUR-only. bin/slack-launch does what
  # omarchy-launch-spotify does for Spotify: focus, else launch, else offer to
  # install it in a floating terminal. It is not in PACKAGES because that lane
  # only reports; install.sh has no sudo and must not acquire any.
  #
  # The .desktop shadows /usr/share/applications/slack.desktop from the AUR
  # package, adding --enable-wayland-ime so the Compose key works inside
  # Slack. Omarchy writes nothing at this path, so a link is safe.
  "$HOME/.local/bin/slack-launch|bin/slack-launch"
  "$HOME/.local/share/applications/slack.desktop|slack/slack.desktop"

  # Custom xkb options, selected by hypr/input.lua. libxkbcommon searches
  # ~/.config/xkb before the system tree, which is how these work without root.
  # Omarchy puts nothing here, so the whole directory is safe to link.
  "$HOME/.config/xkb|xkb"

  # SUPER+RETURN over a file manager: a terminal in the folder that window is
  # showing, with the selected file pre-typed. Two halves, because Nautilus
  # publishes its location nowhere a keybinding can reach -- the extension
  # records it from in-process, the script reads the record.
  #
  # The extension dir is shared, not ours: Omarchy ships defaults for it in
  # default/nautilus-python/extensions and two of them (localsend.py,
  # transcode.py) are already installed here. So link the file, never the
  # directory -- the same call as nvim/plugins/*.lua above.
  #
  # nautilus-python needs no PACKAGES entry: it is on Omarchy's own base list,
  # right below nautilus itself. Nautilus loads extensions at startup though,
  # so the first install of this needs one `nautilus -q` to take effect.
  "$HOME/.local/share/nautilus-python/extensions/term-here.py|nautilus/term-here.py"
  "$HOME/.local/bin/term-here|bin/term-here"

  # The same question asked of tmux, which omarchy-cmd-terminal-cwd cannot see
  # into: the child of a terminal running tmux is the tmux client, not a shell,
  # so its reading is discarded and the answer falls back to $HOME.
  # bin/tmux-cwd asks the tmux server instead, and both keys consult it first
  # -- SUPER+RETURN through term-here, SUPER+SHIFT+F through files-here, which
  # exists only because tmux is more than Omarchy's own launcher can answer.
  #
  # tmux needs no PACKAGES entry: it is on Omarchy's own base list, and
  # bin/tmux-cwd is a no-op on a machine without it (no socket directory, so
  # nothing to scan, so the answer is Omarchy's).
  "$HOME/.local/bin/tmux-cwd|bin/tmux-cwd"
  "$HOME/.local/bin/files-here|bin/files-here"

  # The workspace indicators in the bar, made monitor-aware. A clone of
  # Omarchy's omarchy.workspaces, which is how the shell wants built-in widgets
  # customised -- the packaged copy under $OMARCHY_PATH/shell/plugins is never
  # to be edited, and a user plugin cannot shadow a built-in id
  # (omarchy-plugin-catalog does `unique_by(.id)` over built-ins first, so the
  # packaged one would win and ours be ignored). Hence the new id.
  #
  # ~/.config/omarchy/plugins is the user plugin dir and Omarchy writes nothing
  # into it, so the whole directory is safe to link. omarchy-plugin-catalog
  # walks it with `find -L`, so it follows the link.
  #
  # The other half of this cannot be tracked: the bar layout in
  # ~/.config/omarchy/shell.json has to name alari.workspaces instead of
  # omarchy.workspaces, and shell.json is Omarchy-owned JSON with no include
  # mechanism, so it stays drift -- as it already is for the clock and
  # omalink.phone. `omarchy refresh shell` resets it, and the bar then falls
  # back to the packaged widget. Put it back with:
  #   omarchy-plugin-enable alari.workspaces
  "$HOME/.config/omarchy/plugins/alari.workspaces|omarchy-shell/workspaces"
)

# SEEDS -- machine-local files this repo deliberately does not own. install.sh
# copies the template in when the target is missing and never touches it again,
# so the copy can hold whatever should not be committed. This repo is public.
#
#   <target file>|<repo-relative template>
SEEDS=(
  # Compose expansions with personal details in them. xcompose/XCompose ends
  # with an include of this file.
  "$HOME/.XCompose.local|xcompose/XCompose.local.seed"
)

# BUILDS -- source we compile. Neither lane above fits: the repo tracks source,
# but what the system needs is a binary, and a binary is a build artifact rather
# than config (hence the .gitignore entries).
#
#   <repo-relative source dir>|<installed artifact>
#
# The source dir must hold a Makefile with an `install` target that honours
# PREFIX. install.sh rebuilds only when the installed artifact is not already a
# build of the current source -- decided by content hash, not mtime; see the
# BUILDS section of lib.sh.
BUILDS=(
  "hypr-nav|$HOME/.local/bin/hypr-nav"
)

# PACKAGES -- commands our own tools need that a stock Omarchy does not ship.
#
#   <command>|<pacman package>|<what stops working without it>
#
# Checked, never installed. install.sh has no sudo anywhere and runs unattended
# from the post-update hook, so prompting for a password there would hang an
# `omarchy update`. It reports these as warnings and doctor.sh lists them.
#
# Only genuinely missing things belong here. Verified against
# /usr/share/omarchy/install/*.packages and pactree: jq, less, wl-clipboard and
# xdg-terminal-exec are all on Omarchy's own base list, gawk comes with Arch's
# `base`, and make/gcc come with base-devel, which Omarchy installs.
#
# python is NOT one of those, which this list previously implied by omission.
# It is not in `base`; it arrives only as a transitive dependency of
# base-devel (via debugedit and gdb), and msg-code has a python3 shebang -- so
# --code and the SUPER+ALT+CTRL+M binding both rest on it. Too thin a thread
# to leave undeclared.
#
# kdeconnect is a genuine optional: without it msgs still reads mail and only
# the SMS half steps aside, with a warning. It is listed because the SMS half
# is part of the tool now, not a nicety. busctl needs no entry -- it ships
# with systemd.
PACKAGES=(
  "himalaya|himalaya|msgs and friends -- the mail half of the message stack"
  "python3|python|msg-code, so --code and msg-otp find one-time codes"
  "kdeconnect-cli|kdeconnect|msgs --sms -- the SMS half, read over DBus"
)

# FONTS -- families we ask for that Omarchy does not ship, installed per-user
# into ~/.local/share/fonts (fontconfig reads it via <dir prefix="xdg">fonts).
#
#   <fontconfig family>|<archive url>|<space-separated members to extract>
#
# Per-user and not `pacman -S` on purpose. The Arch package carrying these
# faces, ttf-jetbrains-mono-nerd, Conflicts With ttf-jetbrains-mono-nerd-basic
# -- which the `omarchy` package itself depends on, by that exact name. So
# installing it would force omarchy's dependency to be broken, to gain 232MB
# of faces for the sake of four. Unpacking what we need into $HOME leaves
# pacman's world untouched and needs no root.
#
# The URL is pinned to a release rather than "latest" so every machine gets
# the same faces. Members are listed exactly, not globbed: the archive holds
# 16 weights of this family alone and a terminal wants four.
FONTS=(
  "JetBrainsMonoNL Nerd Font Mono|https://github.com/ryanoasis/nerd-fonts/releases/download/v3.5.1/JetBrainsMono.tar.xz|JetBrainsMonoNLNerdFontMono-Regular.ttf JetBrainsMonoNLNerdFontMono-Bold.ttf JetBrainsMonoNLNerdFontMono-Italic.ttf JetBrainsMonoNLNerdFontMono-BoldItalic.ttf"
)

# WEBAPPS -- sites we want in the app launcher as their own windows, rather
# than as a tab in the browser.
#
#   <name>|<url>|<icon name already on the system, or an https URL>
#
# Declared, not tracked. A .desktop file for a web app is six lines of
# boilerplate wrapped around this triple, so install.sh writes it -- and
# writing it from one declaration is the point: the launcher entry and the
# keybinding in hypr/bindings.lua would otherwise each carry their own copy of
# the URL and be free to disagree.
#
# The icon is why this is not a LINKS lane. It is a third-party logo and this
# repo is public, so the URL is pinned and fetched into
# ~/.local/share/icons on first install -- the same trade FONTS makes, for the
# same reason. A bare name instead of a URL resolves against the icon themes
# already installed, which is enough for anything Omarchy ships an icon for
# (`whatsapp`, say, from omarchy-settings).
#
# Icon URLs point at each vendor's own branding CDN where one exists, and at
# Google's favicon service otherwise, because both return a real PNG.
# Deliberately not each site's apple-touch-icon, which is what
# omarchy-webapp-install guesses first: facebook.com answers that with a WebP,
# and a WebP saved as "messenger.png" is a file the icon theme spec has no
# entry for, so the launcher tile silently comes up blank.
#
# Only web apps Omarchy does not already ship belong here. WhatsApp and the
# four Google entries arrive with `omarchy refresh applications`, and keeping
# our own copy of an Omarchy-owned file is the one thing this repo never does.
# slack.desktop stays out too: that one is a native app whose entry exists to
# carry Electron flags, not a web app.
WEBAPPS=(
  "Messenger|https://www.facebook.com/messages|https://www.google.com/s2/favicons?domain=messenger.com&sz=256"
  "Google Calendar|https://calendar.google.com/calendar|https://www.gstatic.com/images/branding/product/1x/calendar_512dp.png"
)
