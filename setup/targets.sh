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
# PREFIX. install.sh rebuilds only when a source file is newer than the
# installed artifact.
BUILDS=(
  "hypr-nav|$HOME/.local/bin/hypr-nav"
)
