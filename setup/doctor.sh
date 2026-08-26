#!/usr/bin/env bash
#
# Report the state of the delta model on this machine:
#
#   1. Are our managed include blocks in place?
#   2. Are the Omarchy hook symlinks intact?
#   3. Which Omarchy-owned config files differ from the shipped stock defaults
#      in ways this repo does NOT capture? Those are the drift -- either port
#      them into the repo as a delta, or revert them.

set -uo pipefail

DOTFILES=$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/.." && pwd)
OMARCHY=${OMARCHY_PATH:-/usr/share/omarchy}
MARKER='omarchy-dotfiles'

# Files under $OMARCHY/config that are runtime state rather than user config.
# Omarchy ships a seed copy, the app then rewrites it constantly, so diffing
# them reports noise forever.
DRIFT_IGNORE=(
  'chromium/Default/Preferences'
)

# Max diff lines to print per drifted file before truncating.
DIFF_CAP=20

tilde() { echo "${1/#"$HOME"/\~}"; }

# shellcheck source=targets.sh
source "$DOTFILES/setup/targets.sh"

echo "== Managed include blocks =="
for entry in "${HOOKS[@]}"; do
  IFS='|' read -r target style payload <<< "$entry"
  if grep -qF ">>> $MARKER >>>" "$target" 2>/dev/null; then
    echo "  present  $(tilde "$target")  ->  $payload"
  else
    echo "  MISSING  $(tilde "$target")   -> run setup/install.sh"
  fi
done

echo
echo "== Omarchy hooks =="
shopt -s nullglob
for src in "$DOTFILES"/hooks/*.d/*.hook; do
  dest="$HOME/.config/omarchy/hooks/$(basename "$(dirname "$src")")/$(basename "$src")"
  if [[ -L $dest && $(readlink -f "$dest") == "$src" ]]; then
    echo "  linked   $(tilde "$dest")"
  elif [[ -e $dest ]]; then
    echo "  STALE    $(tilde "$dest")   -> not a link into this repo"
  else
    echo "  MISSING  $(tilde "$dest")   -> run setup/install.sh"
  fi
done

echo
echo "== Omarchy-owned files that differ from stock =="
found=0
while IFS= read -r stock; do
  rel=${stock#"$OMARCHY/config/"}
  live="$HOME/.config/$rel"
  [[ -f $live ]] || continue

  skip=false
  for ignore in "${DRIFT_IGNORE[@]}"; do
    [[ $rel == $ignore ]] && skip=true && break
  done
  $skip && continue

  # Compare with our managed block stripped out, so only unmanaged local edits
  # show up here. Only round-trip through awk when a block is actually
  # present -- command substitution mangles trailing newlines, which turns
  # empty stock files into phantom drift.
  if grep -qF ">>> $MARKER >>>" "$live" 2>/dev/null; then
    cmp_live=$(mktemp)
    awk -v m="$MARKER" '
      index($0, ">>> " m " >>>") { skip = 1; next }
      index($0, "<<< " m " <<<") { skip = 0; next }
      !skip' "$live" > "$cmp_live"
    trap 'rm -f "$cmp_live"' EXIT
  else
    cmp_live="$live"
  fi

  if ! cmp -s "$cmp_live" "$stock"; then
    echo "  drift    ~/.config/$rel"
    # stock is '-', live is '+'
    diff --unified=0 "$stock" "$cmp_live" \
      | sed '1,2d' \
      | awk -v cap="$DIFF_CAP" '
          NR <= cap { print "             " $0; next }
          NR == cap + 1 { print "             ... (" NR - 1 "+ lines, run diff for the rest)" }'
    found=$((found + 1))
  fi
done < <(find "$OMARCHY/config" -type f 2>/dev/null | sort)

if (( found == 0 )); then
  echo "  none -- every Omarchy-owned file is stock plus our managed blocks"
else
  echo
  echo "  $found file(s) drifted. Port each into the repo as a delta, or revert with:"
  echo "    omarchy refresh config <path-relative-to-.config>"
fi
