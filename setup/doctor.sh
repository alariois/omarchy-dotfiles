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

# The lines between our markers in a hooked file.
our_block() {
  awk -v m="$MARKER" '
    index($0, ">>> " m " >>>") { inblock = 1; next }
    index($0, "<<< " m " <<<") { inblock = 0; next }
    inblock' "$1" 2>/dev/null
}

# shellcheck source=targets.sh
source "$DOTFILES/setup/targets.sh"
# shellcheck source=lib.sh
source "$DOTFILES/setup/lib.sh"
# shellcheck source=../lib/env.sh
source "$DOTFILES/lib/env.sh"
# shellcheck source=../lib/cloud.sh
source "$DOTFILES/lib/cloud.sh"

echo "== Managed include blocks =="
# Also check WHERE each block points. Nothing stops a second checkout existing
# -- vm/omarchy-vm push lands one at a different path from a git clone, and
# then whichever install.sh ran last owns the live files. Reporting only
# "present" in that state describes another checkout's world as though it were
# this one: the Symlinks section below duly calls links STALE for pointing at
# the other copy, which is true and thoroughly misleading.
foreign=0
for entry in "${HOOKS[@]}"; do
  IFS='|' read -r target style payload <<< "$entry"
  if grep -qF ">>> $MARKER >>>" "$target" 2>/dev/null; then
    if ! grep -qF "$DOTFILES/$payload" "$target" 2>/dev/null; then
      echo "  FOREIGN  $(tilde "$target")   -> block points at another checkout:"
      # Read the path out of OUR block only. Grepping the whole file matched
      # Omarchy's own include line in foot.ini and a stray tmux directive,
      # reporting paths that had nothing to do with us.
      our_block "$target" | sed 's/^/             /'
      foreign=$((foreign + 1))
    # A toml block is a copy, so it can lag its payload, or be edited in place
    # by the app that owns the file.
    elif [[ $style == toml && $(our_block "$target") != "$(toml_block_body "$DOTFILES/$payload")" ]]; then
      echo "  STALE    $(tilde "$target")   -> block differs from $payload: port any"
      echo "           edit made in the block to the repo, then run setup/install.sh"
    else
      echo "  present  $(tilde "$target")  ->  $payload"
    fi
  else
    echo "  MISSING  $(tilde "$target")   -> run setup/install.sh"
  fi
done
if (( foreign )); then
  echo
  echo "  $foreign block(s) point somewhere else. This checkout is $DOTFILES."
  echo "  Everything below is judged against THIS one, so a second copy will"
  echo "  make correct links look STALE. Run setup/install.sh from the checkout"
  echo "  you mean to keep, or delete the other."
fi

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
    # Resolved on both sides: bin/leave-bus is itself a link to bin/leave, so
    # the live link resolves to leave and never equals the payload's own path.
    if [[ -L $target && $(readlink -f "$target") == "$(readlink -f "$DOTFILES/$payload")" ]]; then
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
    IFS='|' read -r cmd pkg needs prefix <<< "$entry"
    if ! path=$(command -v "$cmd" 2>/dev/null); then
      echo "  MISSING  $cmd   -> sudo pacman -S $pkg"
      echo "           needed by $needs"
    elif [[ -n $prefix && $("$cmd" --version 2>&1 | head -n 1) != "$prefix"* ]]; then
      echo "  STALE    $cmd   -> $path is $("$cmd" --version 2>&1 | head -n 1), not $prefix*"
      echo "           needed by $needs"
    else
      echo "  ok       $cmd"
    fi
  done
fi
for entry in "${REPLACED[@]:-}"; do
  [[ -n $entry ]] || continue
  IFS='|' read -r old new why <<< "$entry"
  # -Qq and compare: plain -Q answers for provided names, and the new package
  # provides the old one's name.
  if [[ $(pacman -Qq "$old" 2>/dev/null) == "$old" ]]; then
    echo "  STALE    $old   -> still installed; setup/install.sh replaces it with $new"
    echo "           $why"
  fi
done

echo
echo "== Bitwarden =="
if ! command -v bw >/dev/null 2>&1; then
  echo "  MISSING  bw   -> see Required packages"
elif ! bw_status=$(bw status 2>/dev/null) || ! jq -e . >/dev/null 2>&1 <<<"$bw_status"; then
  echo "  BROKEN   bw   -> bw status did not answer"
else
  bw_server=$(jq -r '.serverUrl // "https://bitwarden.com"' <<<"$bw_status")
  if [[ $bw_server == "$BITWARDEN_SERVER" ]]; then
    echo "  ok       server $bw_server"
  elif [[ $(jq -r .status <<<"$bw_status") == unauthenticated ]]; then
    echo "  STALE    server $bw_server   -> setup/install.sh sets $BITWARDEN_SERVER"
  else
    echo "  STALE    server $bw_server   -> logged in there; bw logout, then setup/install.sh"
  fi
fi

echo
echo "== Releases =="
rel_count=0
[[ -n ${RELEASES+x} ]] && rel_count=${#RELEASES[@]}
if (( rel_count == 0 )); then
  echo "  none declared"
else
  for entry in "${RELEASES[@]}"; do
    [[ -n $entry ]] || continue
    IFS='|' read -r cmd version url sha_amd64 sha_arm64 needs <<< "$entry"
    target="$RELEASE_DIR/$cmd"
    want=$(release_sha "$sha_amd64" "$sha_arm64")
    if [[ -z $want ]]; then
      echo "  MISSING  $cmd   -> no $cmd is pinned for $(uname -m)"
    elif [[ ! -f $target ]]; then
      echo "  MISSING  $cmd   -> run setup/install.sh"
      echo "           for $needs"
    elif have=$(file_hash "$target") && [[ $have != "$want" ]]; then
      if release_is_ours "$cmd" "$have"; then
        echo "  STALE    $cmd   -> an older pin; setup/install.sh installs $version"
      else
        echo "  FOREIGN  $(tilde "$target")   -> not the pinned $version, and not one install.sh put there"
      fi
    else
      echo "  ok       $cmd $version"
      # Another of the same name earlier on PATH would be the one that runs.
      if [[ $(command -v "$cmd" 2>/dev/null) != "$target" ]]; then
        echo "           WARNING: $cmd on this shell's PATH is $(command -v "$cmd" 2>/dev/null || echo nothing)"
      fi
    fi
  done
fi

echo
echo "== Environment =="
# env.yaml and what is generated from it (lib/env.sh, lib/cloud.sh).
if [[ ! -f $ENV_FILE ]]; then
  echo "  SKIP     no env.yaml -- 'env-secrets init' starts one from env.example.yaml"
else
  if env_is_encrypted; then
    echo "  ok       env.yaml is encrypted"
  else
    echo "  BROKEN   env.yaml is NOT encrypted -> env-secrets init"
  fi
  if ! command -v yq >/dev/null || ! command -v sops >/dev/null; then
    echo "  MISSING  sops/yq   -> setup/install.sh installs them"
  else
    if env_diff=$(env_structure_diff); then
      echo "  ok       env.example.yaml has env.yaml's structure"
    else
      echo "  STALE    env.example.yaml   -> does not match env.yaml:"
      sed 's/^/             /' <<< "$env_diff"
    fi
    if env_data=$(env_json 2>/dev/null); then
      echo "  ok       env.yaml opens with the key available here"
      if [[ -f $CLOUD_INDEX && $CLOUD_INDEX -nt $ENV_FILE ]]; then
        echo "  ok       cloud profiles generated from the current env.yaml"
      else
        echo "  STALE    cloud profiles   -> env.yaml changed since; any aws-select, az-select or setup/install.sh regenerates them"
      fi
      # Client secrets expire, after the years az-add was given, and an
      # expired one fails as a plain login error. Thirty days of warning, the
      # same thirty days within which az-add renews one by itself.
      while IFS=$'\t' read -r name slug expires; do
        [[ -n $expires ]] || continue
        days=$(( ( $(date -d "$expires" +%s 2>/dev/null || echo 0) - $(date +%s) ) / 86400 ))
        if (( days < 0 )); then
          echo "  BROKEN   $name   -> its client secret expired on $expires; az-add --profile $slug"
        elif (( days < 30 )); then
          echo "  STALE    $name   -> its client secret expires in $days day(s), on $expires; az-add --profile $slug"
        fi
      done < <(jq -r "$CLOUD_JQ_DEFS"' (.azure // [])[] | [.name, (.name | slug), (.secret_expires // "" | tostring)] | @tsv' <<< "$env_data")
      unset env_data
    else
      echo "  MISSING  the age key   -> env.yaml cannot be opened here; env-secrets import-key"
    fi
  fi
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
echo "== Web apps =="
webapp_count=0
[[ -n ${WEBAPPS+x} ]] && webapp_count=${#WEBAPPS[@]}
if (( webapp_count == 0 )); then
  echo "  none declared"
else
  for entry in "${WEBAPPS[@]}"; do
    [[ -n $entry ]] || continue
    IFS='|' read -r name url icon_ref <<< "$entry"
    icon=$(webapp_icon_for "$name" "$icon_ref")
    desktop=$(webapp_desktop_file "$name")
    if [[ ! -f $desktop ]]; then
      echo "  MISSING  $(tilde "$desktop")   -> run setup/install.sh"
    elif ! webapp_desktop_is_current "$name" "$url" "$icon"; then
      echo "  STALE    $(tilde "$desktop")   -> not what targets.sh declares, run setup/install.sh"
    else
      echo "  ok       $name  ->  $url"
    fi
    # Checked apart from the entry: an unresolvable Icon= still launches the
    # app, it just shows a blank tile, so nothing else ever reports it.
    if ! webapp_icon_installed "$icon"; then
      echo "           WARNING: no icon '$icon' in any theme -- blank launcher tile"
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

    # Omarchy's installer writes the name and email it asked for into
    # git/config (install/user/git.sh, `git config --global user.*`), so on
    # every machine it installed that file differs from stock by exactly
    # that. It is the installer's answer, not a local edit -- like the
    # XCompose identity lines -- so it is not drift. Anything else in [user]
    # still is.
    if [[ $rel == git/config ]] && grep -qx '\[user\]' "$cmp_live"; then
      [[ -n $tmp_live ]] || tmp_live=$(mktemp)
      awk '
        /^\[user\]$/ { u = 1; held = $0; next }
        /^\[/ { u = 0 }
        u && /^[[:space:]]*(name|email)[[:space:]]*=/ { next }
        u && held != "" { print held; held = "" }
        { print }' "$cmp_live" > "$tmp_live.git"
      mv "$tmp_live.git" "$tmp_live"
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
