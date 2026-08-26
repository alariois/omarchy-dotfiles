# Shared helpers for install.sh and doctor.sh.
#
# Both scripts have to answer the same two questions, and have to answer them
# identically, or `doctor.sh` reports a problem `install.sh` will not fix:
#
#   1. Is the installed binary the one this source builds?
#   2. Is the Hyprland config the live session is running the one in this repo?
#
# Neither can be answered from mtimes, which is what both used to do. See the
# two sections below.

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy-dotfiles"

file_hash() { sha256sum < "$1" | cut -d' ' -f1; }

# ── BUILDS freshness ──────────────────────────────────────────────────
#
# mtime cannot answer "was this binary built from this source". A git
# checkout stamps files with the time of the checkout, a restore from backup
# or a copy between machines carries whatever mtime it likes, and `touch`
# settles it outright -- all of which can leave an artifact that is newer
# than its sources and built from something else entirely. Hashing what is
# actually on disk cannot lie, and costs a few milliseconds on four files.
#
# The stamp records both hashes, because either half can go stale on its
# own: edit the source and the first no longer matches, replace the binary
# and the second does not.

build_inputs_hash() {
  local src=$1
  # Only real inputs -- globbing every file would let a stray `make test`
  # binary in the source dir read as a source change.
  ( cd "$src" && find . -type f \
      \( -name '*.c' -o -name '*.h' -o -name 'Makefile' \) \
      -print0 | LC_ALL=C sort -z | xargs -0 -r sha256sum
  ) | sha256sum | cut -d' ' -f1
}

build_stamp_file() { echo "$STATE_DIR/build-${1//\//_}.stamp"; }

# True when the installed artifact matches a build of the current source.
build_is_current() {
  local dir=$1 artifact=$2 stamp want_src want_art
  [[ -x $artifact ]] || return 1
  stamp=$(build_stamp_file "$dir")
  [[ -f $stamp ]] || return 1
  read -r want_src want_art < "$stamp" || return 1
  [[ $want_src == "$(build_inputs_hash "$DOTFILES/$dir")" ]] || return 1
  [[ $want_art == "$(file_hash "$artifact")" ]] || return 1
}

record_build_stamp() {
  local dir=$1 artifact=$2 stamp
  stamp=$(build_stamp_file "$dir")
  mkdir -p "$(dirname "$stamp")"
  printf '%s %s\n' \
    "$(build_inputs_hash "$DOTFILES/$dir")" "$(file_hash "$artifact")" > "$stamp"
}

# ── Hyprland liveness ─────────────────────────────────────────────────
#
# Hyprland watches the files under ~/.config/hypr, but our config is not
# there -- those files hold a one-line dofile() of a path in this repo, and
# a repo edit is invisible to the watcher. So editing hypr/bindings.lua
# changes nothing in the running session until something reloads it, which
# is how four correct Navigate binds can sit in the repo while the session
# runs the previous set. Verified: a new bind added to hypr/bindings.lua was
# still absent from `hyprctl binds` three seconds later, and appeared only
# after an explicit `hyprctl reload`.
#
# So stamp the payloads and reload when they change.

# The repo files behind targets that live under ~/.config/hypr.
#
# The explicit `return 0` is load-bearing: without it the function exits with
# the status of its last test, which is a failure whenever the last declared
# target is not a hypr one -- and under `set -e` that kills install.sh.
hypr_payloads() {
  local entry target payload
  for entry in "${HOOKS[@]:-}"; do
    [[ -n $entry ]] || continue
    IFS='|' read -r target _ payload <<< "$entry"
    if [[ $target == "$HOME/.config/hypr/"* && -f $DOTFILES/$payload ]]; then
      echo "$payload"
    fi
  done
  for entry in "${LINKS[@]:-}"; do
    [[ -n $entry ]] || continue
    IFS='|' read -r target payload <<< "$entry"
    if [[ $target == "$HOME/.config/hypr/"* && -f $DOTFILES/$payload ]]; then
      echo "$payload"
    fi
  done
  return 0
}

hypr_config_hash() {
  local list
  list=$(hypr_payloads | LC_ALL=C sort)
  [[ -n $list ]] || { echo "none"; return 0; }
  ( cd "$DOTFILES" && printf '%s\n' "$list" | xargs -r sha256sum ) \
    | sha256sum | cut -d' ' -f1
}

hypr_stamp_file() { echo "$STATE_DIR/hypr-config.stamp"; }

# True when the running session has already been reloaded for this config.
hypr_config_is_live() {
  local stamp
  stamp=$(hypr_stamp_file)
  [[ -f $stamp ]] || return 1
  [[ $(cat "$stamp") == "$(hypr_config_hash)" ]]
}

hyprland_running() {
  command -v hyprctl >/dev/null 2>&1 && hyprctl version >/dev/null 2>&1
}
