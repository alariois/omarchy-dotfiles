#!/usr/bin/env bash
#
# Wire this repo into the live system.
#
# The model: Omarchy owns its config files, we own ours. We never store a copy
# of an Omarchy file. Two lanes, declared in setup/targets.sh:
#
#   HOOKS -- Omarchy-owned files get one managed block holding a single include
#            that points back into this repo (or, in TOML, which has no
#            include, a copy of the repo file). An `omarchy update` migration can
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

# Somebody is at the keyboard to answer sudo. Not when the post-update hook
# runs us -- it passes --quiet and captures everything we print, so a password
# prompt would hang `omarchy update` -- and not when stdin is no terminal.
#
# DOTFILES_ATTENDED=1 says so without a terminal: for the VM test and CI,
# where sudo needs no password and there is no keyboard either.
attended=false
if ! $quiet && { [[ -t 0 ]] || [[ ${DOTFILES_ATTENDED-} == 1 ]]; }; then attended=true; fi

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
# shellcheck source=../lib/env.sh
source "$DOTFILES/lib/env.sh"
# shellcheck source=../lib/cloud.sh
source "$DOTFILES/lib/cloud.sh"

# Set when a target under ~/.config/hypr was rewritten, so the reload at the
# end fires even if the repo payloads themselves are unchanged.
hypr_dirty=0
note_if_hypr() { [[ $1 == "$HOME/.config/hypr/"* ]] && hypr_dirty=1; return 0; }

# Succeeds when <whole> parses as TOML and means exactly <rest> plus
# <payload>; otherwise says why. Two ways it fails, both seen on the first
# hooking of herdr's config, which still had its own copy of our two settings:
# a key set both in the block and outside it makes the file invalid, and herdr
# then loads none of it; and a top-level key below the block silently becomes
# a key of the block's last table -- `onboarding` turned into
# `ui.toast.onboarding`.
toml_adds_up() {
  python3 -c '
import sys, tomllib

def load(path):
    with open(path, "rb") as f:
        return tomllib.load(f)

def merged(a, b):
    out = dict(a)
    for k, v in b.items():
        both = isinstance(v, dict) and isinstance(a.get(k), dict)
        out[k] = merged(a[k], v) if both else v
    return out

try:
    whole, rest, ours = load(sys.argv[1]), load(sys.argv[2]), load(sys.argv[3])
except tomllib.TOMLDecodeError as e:
    sys.exit(e)
if whole != merged(rest, ours):
    sys.exit("a top-level key below the block lands inside one of its tables")
' "$@"
}

ensure_hook() {
  local target=$1 style=$2 payload=$3
  local abs="$DOTFILES/$payload" open close include tmp err

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
          # X Compose syntax: the path is quoted, and %H expansion is not
          # wanted here because $abs is already absolute.
    xcompose) open="# >>> $MARKER >>>";  close="# <<< $MARKER <<<"
          include="include \"$abs\"" ;;
          # No include in TOML, so the block is a copy of the payload, and it
          # goes at the top -- see the styles in setup/targets.sh.
    toml) open="# >>> $MARKER >>>";  close="# <<< $MARKER <<<"
          include=$(toml_block_body "$abs") ;;
    *)    echo "unknown comment style: $style" >&2; return 1 ;;
  esac

  # A hook target that is a symlink into this repo is a target that used to be
  # in LINKS. The cp below writes THROUGH a symlink on purpose, so proceeding
  # would append an include of the payload to the payload itself -- a Compose
  # file that includes itself, and the repo file overwritten with it. Refuse,
  # and say what to do, rather than corrupt the thing being installed.
  if [[ -L $target && $(readlink -f "$target") == "$DOTFILES"/* ]]; then
    changed "  CONFLICT ${target/#"$HOME"/\~}   -> symlink into this repo, but this target is a hook now"
    changed "           it was in LINKS before. Remove the link and re-run:"
    changed "             rm ${target/#"$HOME"/\~}"
    changed "           Nothing is lost: the payload is unchanged, and the block"
    changed "           this writes instead just includes it."
    conflicts=$((conflicts + 1))
    return 0
  fi

  tmp=$(mktemp)
  # Drop any previous block, keep everything else verbatim.
  if [[ -f $target ]]; then
    awk -v o="$open" -v c="$close" '
      $0 == o { skip = 1; next }
      $0 == c { skip = 0; next }
      !skip' "$target" > "$tmp"
  fi
  if [[ $style == toml ]]; then
    { printf '%s\n%s\n%s\n' "$open" "$include" "$close"; cat "$tmp"; } > "$tmp.top"
    # Unchecked only without python3: a new machine's first run, before the
    # Packages pass installs it. The run after that checks.
    if command -v python3 >/dev/null && ! err=$(toml_adds_up "$tmp.top" "$tmp" "$abs" 2>&1); then
      changed "  CONFLICT ${target/#"$HOME"/\~}   -> would not mean stock plus $payload:"
      changed "             $err"
      changed "           fix or remove what sits outside the block, then re-run"
      conflicts=$((conflicts + 1))
      rm -f "$tmp" "$tmp.top"
      return 0
    fi
    mv "$tmp.top" "$tmp"
  else
    printf '%s\n%s\n%s\n' "$open" "$include" "$close" >> "$tmp"
  fi

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
    # Resolved on both sides, not compared with the payload's own path: a
    # payload that is itself a link (bin/leave-bus -> leave) resolves past
    # it, and the comparison failed on every run -- relinking, and making the
    # post-update hook report a repair after every `omarchy update`.
    if [[ $(readlink -f "$target") == "$(readlink -f "$abs")" ]]; then
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

# Install the pacman packages our own tools need that a stock Omarchy lacks.
#
# The one lane that needs root, so the one that depends on who is running us.
# Run by hand, omarchy-pkg-add goes through sudo, which asks for the password
# if it has none cached. Unattended there is nobody to answer, so a missing
# package stays a warning naming the command to run -- a warning rather than a
# conflict, like a font that failed to download: nothing is broken, something
# is just absent.
ensure_packages() {
  local entry cmd pkg needs prefix old new why path owner
  local -a missing=() pkgs=() remove=() removing_for=()

  # Old packages in the way of new ones -- only if pacman actually has them.
  for entry in "${REPLACED[@]:-}"; do
    [[ -n $entry ]] || continue
    IFS='|' read -r old new why <<< "$entry"
    if pkg_installed "$old"; then
      remove+=("$old")
      removing_for+=("$entry")
    fi
  done

  for entry in "${PACKAGES[@]:-}"; do
    [[ -n $entry ]] || continue
    IFS='|' read -r cmd pkg needs prefix <<< "$entry"
    if package_ok "$cmd" "$prefix"; then
      say "  ok       $cmd"
    else
      missing+=("$entry")
      pkgs+=("$pkg")
    fi
  done

  (( ${#missing[@]} + ${#remove[@]} )) || return 0

  # Neither exit status is the verdict -- pacman explains its own failures,
  # and the loops below ask what is actually installed now.
  if $attended; then
    local -a replacements=() rest=()
    local failed=false
    for entry in "${removing_for[@]:-}"; do
      [[ -n $entry ]] || continue
      IFS='|' read -r old new why <<< "$entry"
      replacements+=("$new")
    done
    for pkg in "${pkgs[@]:-}"; do
      [[ -n $pkg ]] || continue
      printf '%s\n' "${replacements[@]:-}" | grep -qxF "$pkg" || rest+=("$pkg")
    done

    # A replacement is one transaction: the old package goes only as part of
    # installing the new one, so a download that fails leaves the old one in
    # place. Removing first and installing second was tried -- and with a
    # package database a month old, v2's download 404'd after v1 was already
    # gone, which left no aws at all. --ask 4 answers pacman's "Remove
    # aws-cli?" with yes where --noconfirm would answer no: 4 is
    # ALPM_QUESTION_CONFLICT_PKG in alpm.h, and --ask inverts the default
    # answer for the question types it names. Kept to the declared
    # replacements, so it never removes anything nobody listed.
    if (( ${#replacements[@]} )); then
      sudo pacman -S --noconfirm --needed --ask 4 "${replacements[@]}" || failed=true
    fi
    if (( ${#rest[@]} )); then
      omarchy-pkg-add "${rest[@]}" || failed=true
    fi
    if $failed; then
      changed "  pacman   an install failed. If it says 404 or 'failed retrieving file', the package"
      changed "           database is older than the mirrors: 'omarchy update', then install.sh again"
    fi
  fi

  for entry in "${removing_for[@]:-}"; do
    [[ -n $entry ]] || continue
    IFS='|' read -r old new why <<< "$entry"
    if pkg_installed "$old"; then
      changed "  replace  $old  ->  sudo pacman -Rns $old && sudo pacman -S $new"
      changed "           $why"
      warnings=$((warnings + 1))
    else
      changed "  removed  $old  ($why)"
      repaired=$((repaired + 1))
    fi
  done

  for entry in "${missing[@]:-}"; do
    [[ -n $entry ]] || continue
    IFS='|' read -r cmd pkg needs prefix <<< "$entry"
    if package_ok "$cmd" "$prefix"; then
      changed "  added    $cmd  <-  pacman -S $pkg"
      repaired=$((repaired + 1))
    elif path=$(command -v "$cmd" 2>/dev/null); then
      # There, but the wrong version. When it is the package being replaced,
      # the replace line above already says what to do.
      owner=$(pacman -Qoq "$path" 2>/dev/null) || owner=""
      if [[ -n $owner ]] && printf '%s\n' "${remove[@]:-}" | grep -qxF "$owner"; then
        continue
      fi
      changed "  old ver  $cmd  ->  $path is $("$cmd" --version 2>&1 | head -n 1), not $prefix*"
      if [[ -z $owner ]]; then
        changed "           not from pacman -- remove it yourself; install.sh does not delete what it did not install"
      fi
      warnings=$((warnings + 1))
    else
      changed "  no pkg   $cmd  ->  sudo pacman -S $pkg"
      changed "           needed by $needs"
      warnings=$((warnings + 1))
    fi
  done
}

# Is this exact package installed? Not `pacman -Q <name>` alone: that answers
# for provided names too, and aws-cli-v2 provides aws-cli -- so once v2 was in,
# asking about v1 would answer yes, and "removing v1" would remove v2.
pkg_installed() { [[ $(pacman -Qq "$1" 2>/dev/null) == "$1" ]]; }

# An entry is satisfied by its command existing -- and, when it names a
# version prefix, by `--version` starting with it.
package_ok() {
  command -v "$1" >/dev/null 2>&1 || return 1
  [[ -z ${2:-} ]] && return 0
  [[ $("$1" --version 2>&1 | head -n 1) == "$2"* ]]
}

# env.yaml: the encrypted file of accounts and secrets. Its structure is
# checked against env.example.yaml, and everything derived from it -- the AWS
# profiles in ~/.aws/config and the account list the scripts and the prompt
# read -- is regenerated. A machine without env.yaml skips all of it.
ensure_env() {
  local diff errs line
  if [[ ! -f $ENV_FILE ]]; then
    say "  skip     no env.yaml -- 'env-secrets init' starts one"
    return 0
  fi
  if ! command -v sops >/dev/null || ! command -v yq >/dev/null; then
    changed "  no env   env.yaml needs sops and yq, which are not installed"
    warnings=$((warnings + 1))
    return 0
  fi

  if diff=$(env_structure_diff); then
    say "  ok       env.example.yaml matches env.yaml"
  else
    changed "  example  env.example.yaml no longer matches env.yaml:"
    while IFS= read -r line; do changed "           $line"; done <<< "$diff"
    warnings=$((warnings + 1))
  fi
  if ! env_is_encrypted; then
    changed "  plain    env.yaml is not encrypted -- 'env-secrets init' encrypts it"
    warnings=$((warnings + 1))
  fi

  errs=$(mktemp)
  if cloud_sync --force 2>"$errs"; then
    if (( CLOUD_CHANGED )); then
      changed "  synced   ~/.aws/config and the account list  <-  env.yaml"
      repaired=$((repaired + 1))
    else
      say "  ok       ~/.aws/config and the account list match env.yaml"
    fi
  else
    changed "  no sync  could not regenerate the cloud profiles from env.yaml:"
    while IFS= read -r line; do changed "           $line"; done < "$errs"
    warnings=$((warnings + 1))
  fi
  rm -f "$errs"
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

  if ! hypr_ctl reload >/dev/null 2>&1; then
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

# Write a web app's launcher entry and fetch the icon it names.
#
# The entry is generated rather than tracked, because it is boilerplate around
# the triple in targets.sh -- and generating it from that one declaration is
# what keeps the launcher entry and the keybinding in hypr/bindings.lua from
# each holding their own copy of the URL.
#
# Note what does NOT depend on this lane: the keybindings call
# omarchy-launch-or-focus-webapp with the URL directly, so every SUPER+SHIFT
# key works on a machine where this has never run. What is missing there is the
# launcher entry, which is why a failure here warns rather than conflicting --
# that, and the fact that it is network-dependent and runs unattended from the
# post-update hook, exactly as with ensure_font.
ensure_webapp() {
  local name=$1 url=$2 icon_ref=$3
  local desktop icon body mime ext tmp

  desktop=$(webapp_desktop_file "$name")
  icon=$(webapp_icon_for "$name" "$icon_ref")
  body=$(webapp_desktop_body "$name" "$url" "$icon")

  if webapp_desktop_is_current "$name" "$url" "$icon"; then
    say "  ok       ${desktop/#"$HOME"/\~}"
  else
    mkdir -p "$(dirname "$desktop")"
    printf '%s\n' "$body" > "$desktop"
    chmod +x "$desktop"
    changed "  webapp   ${desktop/#"$HOME"/\~}  ->  $url"
    repaired=$((repaired + 1))
  fi

  if webapp_icon_installed "$icon"; then
    say "  ok       icon $icon"
    return 0
  fi

  # A bare name we cannot resolve is a declaration error, not a fetch we can
  # retry: there is no URL to go and get.
  if [[ $icon_ref != https://* ]]; then
    changed "  no icon  $name  ->  nothing named '$icon' in any icon theme"
    warnings=$((warnings + 1))
    return 0
  fi

  if ! command -v curl >/dev/null 2>&1; then
    changed "  no icon  $name  ->  curl not installed"
    warnings=$((warnings + 1))
    return 0
  fi

  tmp=$(mktemp)
  if ! curl -fsSL --retry 2 --max-time 30 -o "$tmp" "$icon_ref"; then
    rm -f "$tmp"
    changed "  no icon  $name  ->  download failed, re-run when online"
    warnings=$((warnings + 1))
    return 0
  fi

  # Ask what actually arrived rather than trusting the URL to have served what
  # its name suggests. omarchy-webapp-install saves whatever it gets as
  # "<app>.png"; facebook.com answers an icon request with a WebP, and a WebP
  # called .png is a format the icon theme spec has no entry for -- the tile
  # then renders blank and nothing anywhere says why.
  mime=$(file -b --mime-type "$tmp" 2>/dev/null)
  case $mime in
    image/png)  ext=png ;;
    image/svg*) ext=svg ;;
    *) rm -f "$tmp"
       changed "  no icon  $name  ->  served $mime, which hicolor cannot use"
       warnings=$((warnings + 1))
       return 0 ;;
  esac

  mkdir -p "$WEBAPP_ICON_DIR"
  # mktemp is 0600; an icon has to be world-readable like any other.
  mv "$tmp" "$WEBAPP_ICON_DIR/$icon.$ext"
  chmod 644 "$WEBAPP_ICON_DIR/$icon.$ext"
  gtk-update-icon-cache "$HOME/.local/share/icons/hicolor" >/dev/null 2>&1 || true
  changed "  icon     $icon.$ext  <-  $name"
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
ensure_packages

say "Environment:"
ensure_env

say "Fonts:"
for entry in "${FONTS[@]:-}"; do
  [[ -n $entry ]] || continue
  IFS='|' read -r family url members <<< "$entry"
  ensure_font "$family" "$url" "$members"
done

say "Web apps:"
for entry in "${WEBAPPS[@]:-}"; do
  [[ -n $entry ]] || continue
  IFS='|' read -r name url icon_ref <<< "$entry"
  ensure_webapp "$name" "$url" "$icon_ref"
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
