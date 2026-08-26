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

# say: progress chatter, hidden by --quiet.
# changed: things we actually modified, always printed. The post-update hook
# treats any output in --quiet mode as "something needed repairing".
say()     { $quiet || echo "$@"; }
changed() { echo "$@"; }

# shellcheck source=targets.sh
source "$DOTFILES/setup/targets.sh"

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
  changed "  linked   ${target/#"$HOME"/\~}  ->  $payload"
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

say "Symlinks:"
for entry in "${LINKS[@]:-}"; do
  [[ -n $entry ]] || continue
  IFS='|' read -r target payload <<< "$entry"
  ensure_link "$target" "$payload"
done

say "Omarchy hooks:"
ensure_omarchy_hooks

say ""
if (( conflicts )); then
  say "$conflicts conflict(s) left unresolved."
elif (( repaired )); then
  say "Applied $repaired change(s). Open a new shell to pick up shell changes."
else
  say "Everything already current."
fi

(( conflicts == 0 ))
