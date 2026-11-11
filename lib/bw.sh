# Bitwarden accounts: what bin/bw-session, bin/bw-vault and bin/bw-move share.
#
# Sourced by those three. The caller sets DOTFILES.
#
# bw holds one login per data directory (BITWARDENCLI_APPDATA_DIR), so every
# account bwu knows is a directory of its own in BW_ACCOUNTS, named after the
# account: bw's data for it, or a link to the directory that holds it -- bw's
# own, for the login that was there before bwu knew of accounts. `bwu login
# NAME EMAIL` makes one.
#
# The keys come from bin/bw-session, by way of bwu: the cache's key on the
# first line, then a line for each account unlocked -- its name, a space, and
# its session key. bwu hands them over in BW_KEYS for one run.

# BW_ACCOUNTS and BW_OWN_DIR are for tests.
BW_ACCOUNTS=${BW_ACCOUNTS:-${XDG_CONFIG_HOME:-$HOME/.config}/omarchy-dotfiles/bw-accounts}
# bw's own data directory: where a plain `bw` keeps its login.
BW_OWN_DIR=${BW_OWN_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/Bitwarden CLI}

BW_CACHE_KEY=""
declare -A BW_KEY=()

# A name for an account: short, and safe in a path and a list.
bw_valid_name() { [[ $1 =~ ^[a-z0-9][a-z0-9_-]{0,23}$ ]]; }

# Every account, by name, one per line.
bw_accounts() {
  local entry
  [[ -d $BW_ACCOUNTS ]] || return 0
  for entry in "$BW_ACCOUNTS"/*; do
    [[ -d $entry ]] || continue
    entry=${entry##*/}
    if bw_valid_name "$entry"; then printf '%s\n' "$entry"; fi
  done
}

# The accounts unlocked, by name, one per line, sorted.
bw_unlocked() {
  (( ${#BW_KEY[@]} )) || return 0
  printf '%s\n' "${!BW_KEY[@]}" | sort
}

# BW_KEYS, read into BW_CACHE_KEY and BW_KEY.
bw_read_keys() {
  local line first=true
  BW_CACHE_KEY="" BW_KEY=()
  while IFS= read -r line; do
    if $first; then
      BW_CACHE_KEY=$line
      first=false
    elif [[ $line == *" "* ]] && bw_valid_name "${line%% *}"; then
      BW_KEY[${line%% *}]=${line#* }
    fi
  done <<<"${BW_KEYS-}"
}

# bw as one account: its data directory, and its session key. Never asking:
# with a key gone stale bw would ask for the master password itself, unseen
# behind a redirected stderr, and an unlock there makes every key bwu holds
# worthless.
bw_as() {
  local name=$1
  shift
  BITWARDENCLI_APPDATA_DIR=$BW_ACCOUNTS/$name BW_SESSION=${BW_KEY[$name]-} BW_NOINTERACTION=true bw "$@"
}

# Does the account's key still unlock it? Every unlock elsewhere, and every
# lock, makes the key before it worthless.
bw_unlocks() { [[ -n ${BW_KEY[$1]-} ]] && bw_as "$1" unlock --check >/dev/null 2>&1; }
