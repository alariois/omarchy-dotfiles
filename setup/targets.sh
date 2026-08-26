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
)
