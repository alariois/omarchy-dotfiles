#!/usr/bin/env bash
#
# Report the state of the delta model on this machine:
#
#   1. Are our managed include blocks in place?
#   2. Do our symlinks point into this repo?
#   3. Are the Omarchy hook symlinks intact?
#   4. Which Omarchy-owned config files differ from the shipped stock defaults
#      in ways this repo does NOT capture? Those are the drift -- either port
#      them into the repo as a delta, or revert them.

set -uo pipefail

DOTFILES=$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/.." && pwd)
OMARCHY=${OMARCHY_PATH:-/usr/share/omarchy}
OMARCHY_NVIM=${OMARCHY_NVIM_PATH:-/usr/share/omarchy-nvim}
MARKER='omarchy-dotfiles'

# Stock trees to diff the live system against, as <stock root>|<live root>.
# Omarchy ships nvim from its own package, not from $OMARCHY/config, so it
# needs a second entry rather than being reachable from the first.
STOCK_ROOTS=(
  "$OMARCHY/config|$HOME/.config"
  "$OMARCHY_NVIM/config|$HOME/.config/nvim"
)

# Paths (relative to their stock root) that are runtime state rather than user
# config. Omarchy ships a seed copy, the app then rewrites it constantly, so
# diffing them reports noise forever.
DRIFT_IGNORE=(
  'chromium/Default/Preferences'
  'lazy-lock.json'
)

# Max diff lines to print per drifted file before truncating.
DIFF_CAP=20

tilde() { echo "${1/#"$HOME"/\~}"; }

# shellcheck source=targets.sh
source "$DOTFILES/setup/targets.sh"
# shellcheck source=lib.sh
source "$DOTFILES/setup/lib.sh"

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
echo "== Symlinks into this repo =="
# ${#LINKS[@]} would abort under `set -u` if targets.sh ever drops the array.
link_count=0
[[ -n ${LINKS+x} ]] && link_count=${#LINKS[@]}
if (( link_count == 0 )); then
  echo "  none declared"
else
  for entry in "${LINKS[@]}"; do
    [[ -n $entry ]] || continue
    IFS='|' read -r target payload <<< "$entry"
    if [[ -L $target && $(readlink -f "$target") == "$DOTFILES/$payload" ]]; then
      echo "  linked   $(tilde "$target")  ->  $payload"
    elif [[ -e $target ]]; then
      echo "  STALE    $(tilde "$target")   -> real file/dir, or link elsewhere"
    else
      echo "  MISSING  $(tilde "$target")   -> run setup/install.sh"
    fi
  done
fi

echo
echo "== Machine-local files =="
seed_count=0
[[ -n ${SEEDS+x} ]] && seed_count=${#SEEDS[@]}
if (( seed_count == 0 )); then
  echo "  none declared"
else
  for entry in "${SEEDS[@]}"; do
    [[ -n $entry ]] || continue
    IFS='|' read -r target payload <<< "$entry"
    if [[ -e $target ]]; then
      # Still matching the template means it was seeded but never filled in.
      if cmp -s "$target" "$DOTFILES/$payload"; then
        echo "  seeded   $(tilde "$target")   -> still the bare template"
      else
        echo "  local    $(tilde "$target")   -> has local content (not tracked)"
      fi
    else
      echo "  MISSING  $(tilde "$target")   -> run setup/install.sh"
    fi
  done
fi

echo
echo "== Compiled binaries =="
build_count=0
[[ -n ${BUILDS+x} ]] && build_count=${#BUILDS[@]}
if (( build_count == 0 )); then
  echo "  none declared"
else
  for entry in "${BUILDS[@]}"; do
    [[ -n $entry ]] || continue
    IFS='|' read -r dir artifact <<< "$entry"
    if [[ ! -x $artifact ]]; then
      echo "  MISSING  $(tilde "$artifact")   -> run setup/install.sh"
    elif ! build_is_current "$dir" "$artifact"; then
      # By content, not mtime: an artifact can be newer than its sources and
      # still be a build of something else entirely.
      echo "  STALE    $(tilde "$artifact")   -> not a build of $dir, run setup/install.sh"
    else
      echo "  built    $(tilde "$artifact")  <-  $dir"
      # A binary that is not reachable by name is installed but unusable from a
      # keybinding, which is the only way this one ever gets called.
      command -v "$(basename "$artifact")" >/dev/null 2>&1 \
        || echo "           WARNING: $(basename "$artifact") is not on this shell's PATH"
    fi
  done
fi

echo
echo "== Required packages =="
pkg_count=0
[[ -n ${PACKAGES+x} ]] && pkg_count=${#PACKAGES[@]}
if (( pkg_count == 0 )); then
  echo "  none declared"
else
  for entry in "${PACKAGES[@]}"; do
    [[ -n $entry ]] || continue
    IFS='|' read -r cmd pkg needs <<< "$entry"
    if command -v "$cmd" >/dev/null 2>&1; then
      echo "  ok       $cmd"
    else
      echo "  MISSING  $cmd   -> sudo pacman -S $pkg"
      echo "           needed by $needs"
    fi
  done
fi

echo
echo "== Mail =="
# Three separate things, each of which fails in its own way: the binary, the
# config, and the credential. Checked apart so the report says which.
if ! command -v himalaya >/dev/null 2>&1; then
  echo "  SKIP     himalaya not installed (see Required packages above)"
else
  if himalaya -c "$DOTFILES/himalaya/config.toml" --json account list >/dev/null 2>&1; then
    echo "  ok       himalaya config parses"
  else
    echo "  BROKEN   himalaya config does not parse:"
    himalaya -c "$DOTFILES/himalaya/config.toml" account list 2>&1 \
      | sed 's/^/             /' | head -4
  fi

  # Every account, not just the first -- a second mailbox whose password was
  # never stored fails only when something reaches for it, which is exactly
  # the kind of thing this report exists to catch early.
  #
  # Presence only: never print the secret, never send it anywhere. The live
  # login test is `himalaya account check`, deliberately not run here, so that
  # doctor.sh stays cheap and works offline.
  while IFS= read -r addr; do
    [[ -n $addr ]] || continue
    if secret-tool lookup service himalaya account "$addr" >/dev/null 2>&1; then
      echo "  ok       password in keyring for $addr"
    else
      echo "  MISSING  no keyring password for $addr"
      echo "           -> secret-tool store --label='himalaya' \\"
      echo "                service himalaya account $addr"
    fi
  done < <(sed -n 's/^email *= *"\(.*\)"/\1/p' "$DOTFILES/himalaya/config.toml")
fi

echo
echo "== Fonts =="
font_count=0
[[ -n ${FONTS+x} ]] && font_count=${#FONTS[@]}
if (( font_count == 0 )); then
  echo "  none declared"
else
  for entry in "${FONTS[@]}"; do
    [[ -n $entry ]] || continue
    IFS='|' read -r family url members <<< "$entry"
    # Ask fontconfig, not the filesystem. A missing family is not an error
    # anywhere downstream -- fontconfig quietly substitutes another one -- so
    # this is the only place it ever gets noticed.
    if font_installed "$family"; then
      echo "  ok       $family"
    else
      echo "  MISSING  $family   -> run setup/install.sh (needs network)"
    fi
  done
fi

echo
echo "== Hyprland =="
# The files Hyprland watches only dofile() a path in this repo, so an edit here
# is invisible to the running session until something reloads it. install.sh
# does that; this reports when the session is behind anyway -- after a config
# edit made without re-running install.sh, say.
if ! hyprland_running; then
  echo "  SKIP     no Hyprland session to query"
elif hypr_config_is_live; then
  echo "  ok       session is running this repo's config"
else
  echo "  BEHIND   session predates the current hypr/ config"
  echo "           -> run setup/install.sh (or hyprctl reload)"
fi

echo
echo "== Keyboard =="
# Both of these fail silently in normal use, which is why they are checked here.
# A Compose file that does not parse loses *every* binding in it, not just the
# bad line -- a missing include is enough. And a kb_options naming an undefined
# custom:* option leaves the remapping quietly not applied.
if ! command -v xkbcli >/dev/null 2>&1; then
  echo "  SKIP     xkbcli not installed (package libxkbcommon-tools)"
else
  if [[ -e $HOME/.XCompose ]]; then
    if xkbcli compile-compose --test "$HOME/.XCompose" >/dev/null 2>&1; then
      echo "  ok       ~/.XCompose compiles"
    else
      echo "  BROKEN   ~/.XCompose does not compile -- ALL expansions are dead:"
      xkbcli compile-compose --test "$HOME/.XCompose" 2>&1 \
        | sed 's/^/             /' | head -4
    fi
  else
    echo "  MISSING  ~/.XCompose   -> run setup/install.sh"
  fi

  # Compile the options this repo actually asks for, out of the linked xkb dir.
  opts=$(grep -oP 'kb_options\s*=\s*"\K[^"]+' "$DOTFILES/hypr/input.lua" 2>/dev/null | head -1)
  if [[ -n $opts ]]; then
    if XKB_CONFIG_EXTRA_PATH="$DOTFILES/xkb" \
         xkbcli compile-keymap --layout us --options "$opts" >/dev/null 2>&1; then
      echo "  ok       keymap compiles: $opts"
    else
      echo "  BROKEN   keymap will not compile: $opts"
    fi
  fi
fi

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
for root in "${STOCK_ROOTS[@]}"; do
  IFS='|' read -r stock_root live_root <<< "$root"
  [[ -d $stock_root ]] || continue

  while IFS= read -r stock; do
    rel=${stock#"$stock_root/"}
    live="$live_root/$rel"
    [[ -f $live ]] || continue

    skip=false
    for ignore in "${DRIFT_IGNORE[@]}"; do
      [[ $rel == "$ignore" ]] && skip=true && break
    done
    $skip && continue

    # A live path that is a symlink into this repo is ours by construction --
    # the Symlinks section above already reports on it.
    if [[ -L $live && $(readlink -f "$live") == "$DOTFILES"/* ]]; then
      continue
    fi

    # Compare with our managed block stripped out, so only unmanaged local
    # edits show up here. Only round-trip through awk when a block is actually
    # present -- command substitution mangles trailing newlines, which turns
    # empty stock files into phantom drift.
    cmp_live="$live"
    tmp_live=
    if grep -qF ">>> $MARKER >>>" "$live" 2>/dev/null; then
      tmp_live=$(mktemp)
      awk -v m="$MARKER" '
        index($0, ">>> " m " >>>") { skip = 1; next }
        index($0, "<<< " m " <<<") { skip = 0; next }
        !skip' "$live" > "$tmp_live"
      cmp_live="$tmp_live"
    fi

    if ! cmp -s "$cmp_live" "$stock"; then
      echo "  drift    $(tilde "$live")"
      # stock is '-', live is '+'
      diff --unified=0 "$stock" "$cmp_live" \
        | sed '1,2d' \
        | awk -v cap="$DIFF_CAP" '
            NR <= cap { print "             " $0; next }
            NR == cap + 1 { print "             ... (" NR - 1 "+ lines, run diff for the rest)" }'
      found=$((found + 1))
    fi

    [[ -n $tmp_live ]] && rm -f "$tmp_live"
  done < <(find "$stock_root" -type f 2>/dev/null | sort)
done

if (( found == 0 )); then
  echo "  none -- every Omarchy-owned file is stock plus our managed blocks"
else
  echo
  echo "  $found file(s) drifted. Port each into the repo as a delta, or revert with:"
  echo "    omarchy refresh config <path-relative-to-.config>"
fi
