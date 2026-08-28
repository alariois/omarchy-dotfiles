#!/usr/bin/env bash
#
# Wire this repo into the live system.
#
# The model: Omarchy owns its config files, we own ours. We never store a copy
# of an Omarchy file. Two lanes, declared in setup/targets.sh:
#
#   HOOKS -- Omarchy-owned files get one managed block holding a single include
#            that points back into this repo. An `omarchy update` migration can
#            clobber that block (migrations `mv` a temp file over the target),
#            but it can never touch our actual configuration -- and the
#            post-update hook re-asserts the block afterwards.
#
#   LINKS -- files Omarchy never writes become symlinks into this repo, so the
#            live file *is* the repo file and drift is impossible.
#
# Safe to run repeatedly.

set -euo pipefail

DOTFILES=$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/.." && pwd)

MARKER='omarchy-dotfiles'

quiet=false
[[ ${1:-} == --quiet ]] && quiet=true

repaired=0
conflicts=0
# Reported problems that are not conflicts: nothing is wrong with the repo or
# the live files, we just could not finish something. Tracked separately so the
# summary cannot claim "Everything already current" right after warning.
warnings=0

# say: progress chatter, hidden by --quiet.
# changed: things we actually modified, always printed. The post-update hook
# treats any output in --quiet mode as "something needed repairing".
say()     { $quiet || echo "$@"; }
changed() { echo "$@"; }

# shellcheck source=targets.sh
source "$DOTFILES/setup/targets.sh"
# shellcheck source=lib.sh
source "$DOTFILES/setup/lib.sh"

# Set when a target under ~/.config/hypr was rewritten, so the reload at the
# end fires even if the repo payloads themselves are unchanged.
hypr_dirty=0
note_if_hypr() { [[ $1 == "$HOME/.config/hypr/"* ]] && hypr_dirty=1; return 0; }

ensure_hook() {
  local target=$1 style=$2 payload=$3
  local abs="$DOTFILES/$payload" open close include tmp

  if [[ ! -f $abs ]]; then
    echo "MISSING payload: $abs" >&2
    return 1
  fi

  case $style in
    sh)   open="# >>> $MARKER >>>";  close="# <<< $MARKER <<<"
          include="source \"$abs\"" ;;
    tmux) open="# >>> $MARKER >>>";  close="# <<< $MARKER <<<"
          include="source-file \"$abs\"" ;;
    lua)  open="-- >>> $MARKER >>>"; close="-- <<< $MARKER <<<"
          include="dofile(\"$abs\")" ;;
          # foot.ini is sectioned, and this block lands at the end of the file
          # -- inside whatever section came last. A bare `include` there is
          # read as a key of that section, which foot rejects with
          # "[text-bindings].include: not a valid XKB key name". Re-opening
          # [main] first fixes it, and costs nothing: foot documents that the
          # included file has its own section scope. Verified against
          # `foot --check-config`.
    ini)  open="# >>> $MARKER >>>";  close="# <<< $MARKER <<<"
          include=$'[main]\ninclude='"$abs" ;;
    *)    echo "unknown comment style: $style" >&2; return 1 ;;
  esac

  tmp=$(mktemp)
  # Drop any previous block, keep everything else verbatim.
  if [[ -f $target ]]; then
    awk -v o="$open" -v c="$close" '
      $0 == o { skip = 1; next }
      $0 == c { skip = 0; next }
      !skip' "$target" > "$tmp"
  fi
  printf '%s\n%s\n%s\n' "$open" "$include" "$close" >> "$tmp"

  if [[ -f $target ]] && cmp -s "$tmp" "$target"; then
    say "  ok       ${target/#"$HOME"/\~}"
    rm -f "$tmp"
    return 0
  fi

  # cp, never mv: if the target is ever a symlink we write through it
  # rather than replacing it with a regular file.
  mkdir -p "$(dirname "$target")"
  cp -f "$tmp" "$target"
  rm -f "$tmp"
  note_if_hypr "$target"
  changed "  hooked   ${target/#"$HOME"/\~}  ->  $payload"
  repaired=$((repaired + 1))
}

# Point target at the repo copy. Never destroys anything that is not already
# byte-identical to what we would link: an unrecognised file there is somebody's
# real config, so we report it and let them decide.
ensure_link() {
  local target=$1 payload=$2
  local abs="$DOTFILES/$payload"

  if [[ ! -e $abs ]]; then
    echo "MISSING payload: $abs" >&2
    return 1
  fi

  if [[ -L $target ]]; then
    if [[ $(readlink -f "$target") == "$abs" ]]; then
      say "  ok       ${target/#"$HOME"/\~}"
      return 0
    fi
  elif [[ -e $target ]]; then
    # A real file or directory sits where the link belongs. Only replace it if
    # it already matches the repo, in which case nothing can be lost.
    if diff -rq "$target" "$abs" >/dev/null 2>&1; then
      rm -rf "$target"
    else
      changed "  CONFLICT ${target/#"$HOME"/\~}   -> real file/dir, differs from $payload"
      changed "           inspect it, move it aside, then re-run install.sh"
      conflicts=$((conflicts + 1))
      return 0
    fi
  fi

  mkdir -p "$(dirname "$target")"
  ln -sfn "$abs" "$target"
  note_if_hypr "$target"
  changed "  linked   ${target/#"$HOME"/\~}  ->  $payload"
  repaired=$((repaired + 1))
}

# Drop a template into place the first time and then leave it alone forever.
# The point is the "leave it alone": the target holds machine-local content the
# repo must not own, so an existing file is never compared or overwritten.
ensure_seed() {
  local target=$1 payload=$2
  local abs="$DOTFILES/$payload"

  if [[ ! -f $abs ]]; then
    echo "MISSING template: $abs" >&2
    return 1
  fi

  if [[ -e $target ]]; then
    say "  ok       ${target/#"$HOME"/\~}  (local, left alone)"
    return 0
  fi

  mkdir -p "$(dirname "$target")"
  cp "$abs" "$target"
  changed "  seeded   ${target/#"$HOME"/\~}  <-  $payload"
  changed "           machine-local and untracked; edit it there, not in the repo"
  repaired=$((repaired + 1))
}

# Compile source in the repo and install the resulting binary. Skipped when the
# installed artifact already matches a build of the current source, so a repeat
# run stays silent instead of shelling out to make and reprinting its output.
#
# "Matches" is by content, not mtime -- see the BUILDS section of lib.sh for why
# mtime cannot answer this.
ensure_build() {
  local dir=$1 artifact=$2
  local src="$DOTFILES/$dir" out bindir prefix

  if [[ ! -f $src/Makefile ]]; then
    echo "MISSING Makefile: $src/Makefile" >&2
    return 1
  fi

  if build_is_current "$dir" "$artifact"; then
    say "  ok       ${artifact/#"$HOME"/\~}"
    return 0
  fi

  # The Makefile convention is $(PREFIX)/bin/<binary>, so PREFIX is two levels
  # up from the artifact.
  bindir=$(dirname "$artifact")
  prefix=$(dirname "$bindir")

  if ! out=$(make -C "$src" PREFIX="$prefix" install 2>&1); then
    changed "  FAILED   build $dir  ->  ${artifact/#"$HOME"/\~}"
    changed "$out"
    conflicts=$((conflicts + 1))
    return 0
  fi

  record_build_stamp "$dir" "$artifact"
  changed "  built    ${artifact/#"$HOME"/\~}  <-  $dir"
  repaired=$((repaired + 1))
}

# Re-read our Hyprland config into the running session.
#
# Nothing else does this: the files Hyprland watches only dofile() a path in
# this repo, so a repo edit never reaches the session on its own. Without it
# install.sh can report success while the session still runs the old binds.
ensure_hypr_live() {
  if (( hypr_dirty == 0 )) && hypr_config_is_live; then
    say "  ok       Hyprland config is live"
    return 0
  fi

  # Outside a session there is nothing to reload -- and deliberately no stamp
  # either, so the reload happens on the next run that does have one.
  if ! hyprland_running; then
    say "  skip     no Hyprland session to reload"
    return 0
  fi

  if ! hyprctl reload >/dev/null 2>&1; then
    changed "  FAILED   hyprctl reload"
    conflicts=$((conflicts + 1))
    return 0
  fi

  mkdir -p "$STATE_DIR"
  hypr_config_hash > "$(hypr_stamp_file)"
  changed "  reloaded Hyprland"
  repaired=$((repaired + 1))
}

# Unpack a font family Omarchy does not ship into the per-user font dir.
#
# A failure here warns rather than counting as a conflict. It is the one lane
# that depends on the network, it is cosmetic when it fails (fontconfig
# substitutes another family), and install.sh runs unattended from the
# post-update hook -- a transient outage during `omarchy update` should not
# report a broken install. doctor.sh keeps a missing family visible.
ensure_font() {
  local family=$1 url=$2 members=$3
  local tmp archive

  if font_installed "$family"; then
    say "  ok       $family"
    return 0
  fi

  if ! command -v curl >/dev/null 2>&1; then
    changed "  no font  $family  ->  curl not installed"
    warnings=$((warnings + 1))
    return 0
  fi

  tmp=$(mktemp -d)
  archive="$tmp/${url##*/}"

  if ! curl -fsSL --retry 2 --max-time 120 -o "$archive" "$url"; then
    rm -rf "$tmp"
    changed "  no font  $family  ->  download failed, re-run when online"
    warnings=$((warnings + 1))
    return 0
  fi

  mkdir -p "$FONT_DIR"
  # Unquoted on purpose: members is a deliberate space-separated list.
  # shellcheck disable=SC2086
  if ! tar -xf "$archive" -C "$FONT_DIR" $members 2>/dev/null; then
    rm -rf "$tmp"
    changed "  no font  $family  ->  archive lacks the expected faces"
    warnings=$((warnings + 1))
    return 0
  fi
  rm -rf "$tmp"

  fc-cache -f "$FONT_DIR" >/dev/null 2>&1

  # Unpacking is not the same as resolving -- ask fontconfig, do not assume.
  if ! font_installed "$family"; then
    changed "  no font  $family  ->  unpacked, but fontconfig does not see it"
    warnings=$((warnings + 1))
    return 0
  fi

  changed "  font     $family  <-  ${url##*/}"
  repaired=$((repaired + 1))
}

ensure_omarchy_hooks() {
  local src dest
  for src in "$DOTFILES"/hooks/*.d/*.hook; do
    [[ -e $src ]] || continue
    dest="$HOME/.config/omarchy/hooks/$(basename "$(dirname "$src")")/$(basename "$src")"
    mkdir -p "$(dirname "$dest")"
    if [[ -L $dest && $(readlink -f "$dest") == "$src" ]]; then
      say "  ok       ${dest/#"$HOME"/\~}"
      continue
    fi
    ln -sfn "$src" "$dest"
    changed "  linked   ${dest/#"$HOME"/\~}"
    repaired=$((repaired + 1))
  done
}

say "omarchy-dotfiles: $DOTFILES"
say "Config hooks:"
for entry in "${HOOKS[@]}"; do
  IFS='|' read -r target style payload <<< "$entry"
  ensure_hook "$target" "$style" "$payload"
done

# Seeded before the symlinks, because xcompose/XCompose includes the local file
# that this creates.
say "Local files:"
for entry in "${SEEDS[@]:-}"; do
  [[ -n $entry ]] || continue
  IFS='|' read -r target payload <<< "$entry"
  ensure_seed "$target" "$payload"
done

say "Symlinks:"
for entry in "${LINKS[@]:-}"; do
  [[ -n $entry ]] || continue
  IFS='|' read -r target payload <<< "$entry"
  ensure_link "$target" "$payload"
done

say "Builds:"
for entry in "${BUILDS[@]:-}"; do
  [[ -n $entry ]] || continue
  IFS='|' read -r dir artifact <<< "$entry"
  ensure_build "$dir" "$artifact"
done

say "Packages:"
for entry in "${PACKAGES[@]:-}"; do
  [[ -n $entry ]] || continue
  IFS='|' read -r cmd pkg needs <<< "$entry"
  if command -v "$cmd" >/dev/null 2>&1; then
    say "  ok       $cmd"
  else
    # A warning, not a conflict: nothing here is broken, something is just
    # absent, and install.sh cannot fix it without sudo it must not have.
    changed "  no pkg   $cmd  ->  sudo pacman -S $pkg"
    changed "           needed by $needs"
    warnings=$((warnings + 1))
  fi
done

say "Fonts:"
for entry in "${FONTS[@]:-}"; do
  [[ -n $entry ]] || continue
  IFS='|' read -r family url members <<< "$entry"
  ensure_font "$family" "$url" "$members"
done

say "Omarchy hooks:"
ensure_omarchy_hooks

say "Hyprland:"
ensure_hypr_live

say ""
if (( conflicts )); then
  say "$conflicts conflict(s) left unresolved."
elif (( repaired )); then
  say "Applied $repaired change(s). Open a new shell to pick up shell changes."
else
  (( warnings )) || say "Everything already current."
fi
# An `if`, not `(( warnings )) && say ...`: the latter leaves the script's exit
# status riding on set -e's rules for a failing test in an AND-list, which is
# too subtle to leave load-bearing this close to the final status line.
if (( warnings )); then
  say "$warnings warning(s) above -- see setup/doctor.sh."
fi

(( conflicts == 0 ))
