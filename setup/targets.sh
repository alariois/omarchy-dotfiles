# Single source of truth for the delta model.
#
# Each entry: <target file>|<comment style>|<repo-relative file to include>
#
# Adding a new delta = one row here + the file it points at. Styles:
#   sh   -> block uses `#`  comments and `source "<path>"`
#   lua  -> block uses `--` comments and `dofile("<path>")`
#
# Only list files Omarchy itself owns. Files Omarchy never writes to should be
# symlinked from the repo instead, not hooked.

HOOKS=(
  "$HOME/.bashrc|sh|shell/bashrc"
)
