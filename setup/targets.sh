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

  # Ours outright: Omarchy ships no .XCompose.
  "$HOME/.XCompose|xcompose/XCompose"

  # Gmail over IMAP for scripting, plus the helper that reads it. Omarchy
  # ships nothing under ~/.config/himalaya, and ~/.local/bin is already on the
  # session PATH for hypr-nav's sake. No secret is tracked: the config fetches
  # the app password from gnome-keyring at run time.
  "$HOME/.config/himalaya/config.toml|himalaya/config.toml"
  "$HOME/.local/bin/mail-last|bin/mail-last"
  "$HOME/.local/bin/mail-code|bin/mail-code"
  "$HOME/.local/bin/mail-peek|bin/mail-peek"
  "$HOME/.local/bin/mail-otp|bin/mail-otp"

  # Custom xkb options, selected by hypr/input.lua. libxkbcommon searches
  # ~/.config/xkb before the system tree, which is how these work without root.
  # Omarchy puts nothing here, so the whole directory is safe to link.
  "$HOME/.config/xkb|xkb"
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
PACKAGES=(
  "himalaya|himalaya|mail-last, mail-peek, mail-otp -- the whole mail stack"
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
