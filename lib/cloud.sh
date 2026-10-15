# AWS and Azure accounts from env.yaml, shared by aws-select, az-select,
# aws-add, az-add, aws-env-credentials and setup/install.sh. Source
# lib/env.sh first.
#
# env.yaml is the one place an account is defined. What the clouds' own tools
# need is derived from it here and kept beside them:
#
#   ~/.aws/config     a managed block with one profile per AWS entry, so
#                     `aws --profile <name>` works anywhere, not only in
#                     aws-select
#   profiles.tsv      the account list, without a single secret in it, so the
#                     picker, tab completion and aws-whoami/az-whoami never
#                     decrypt
#   azure/<profile>/  one AZURE_CONFIG_DIR per Azure entry, so each keeps its
#                     own login and switching never logs anything else out
#
# all under CLOUD_STATE except the first. A profile's name is its entry's
# `name` folded to lower-case-and-dashes: "Acme Prod" is acme-prod.

CLOUD_STATE="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy-dotfiles/cloud"
CLOUD_INDEX="$CLOUD_STATE/profiles.tsv"
AWS_CONFIG="${AWS_CONFIG_FILE:-$HOME/.aws/config}"
AWS_CREDENTIAL_HELPER="$HOME/.local/bin/aws-env-credentials"
CLOUD_MARKER=omarchy-dotfiles

# The one definition of a profile name, used by every jq program below.
CLOUD_JQ_DEFS='def slug: ascii_downcase | gsub("[^a-z0-9]+"; "-") | gsub("^-+|-+$"; "");'

# What an entry must have, as one error line per problem. Checked before
# anything is generated, so a typo in env.yaml is reported by name instead of
# surfacing later as an AWS error about a profile nobody wrote by hand.
CLOUD_JQ_VALIDATE='
  def blank($v): ($v // "" | tostring) == "";
  (.aws // []) as $aws | (.azure // []) as $az |
  ( $aws[] as $e | ($e.name // "an AWS entry") as $n |
      (if blank($e.name) then "aws: an entry has no name" else empty end),
      (if blank($e.region) then "\($n): no region" else empty end),
      (if $e.role_arn then
         if blank($e.source) then "\($n): role_arn needs source, the name of the entry whose keys assume the role"
         elif ([$aws[] | select(.name == $e.source and .access_key_id and .secret_access_key)] | length) == 0
           then "\($n): source \"\($e.source)\" is not an AWS entry with access keys"
         else empty end
       elif blank($e.access_key_id) or blank($e.secret_access_key)
         then "\($n): needs access_key_id and secret_access_key, or role_arn and source"
       else empty end) ),
  ( $az[] as $e | ($e.name // "an Azure entry") as $n |
      (if blank($e.name) then "azure: an entry has no name" else empty end),
      ( "tenant_id", "subscription_id", "client_id", "client_secret" |
          select(blank($e[.])) | "\($n): no \(.)" ) ),
  ( [$aws[].name // empty | slug] | group_by(.)[] | select(length > 1) |
      "aws: two entries are both called \(.[0])" ),
  ( [$az[].name // empty | slug] | group_by(.)[] | select(length > 1) |
      "azure: two entries are both called \(.[0])" )'

# cloud  profile  name  prod  then for aws: account_id region,
#                              and for azure: subscription_id tenant_id
# Each half in its own parentheses: `,` binds looser than `|`, so without them
# the Azure half would run once per AWS entry, against the entry.
CLOUD_JQ_INDEX='
  ((.aws // [])[] | ["aws", (.name | slug), .name, (.prod // false | tostring),
                     (.account_id // "" | tostring), .region] | @tsv),
  ((.azure // [])[] | ["azure", (.name | slug), .name, (.prod // false | tostring),
                       .subscription_id, .tenant_id] | @tsv)'

# Key-based profiles read their keys through the helper at the moment the CLI
# needs them; role profiles name the entry whose keys assume the role, and the
# CLI does the assuming and caches the result itself.
CLOUD_JQ_AWS_BLOCK='
  (.aws // [])[] |
    "[profile \(.name | slug)]",
    "region = \(.region)",
    (if .role_arn then "role_arn = \(.role_arn)", "source_profile = \(.source | slug)"
     else "credential_process = \($helper) \(.name | slug)" end),
    ""'

if [[ -t 1 ]]; then
  C_OK=$'\e[1;32m' C_BAD=$'\e[1;31m' C_PROD=$'\e[1;41;97m' C_DIM=$'\e[2m' C_OFF=$'\e[0m'
else
  C_OK="" C_BAD="" C_PROD="" C_DIM="" C_OFF=""
fi
cloud_ok()   { printf '%s✓%s %s\n' "$C_OK" "$C_OFF" "$*"; }
cloud_bad()  { printf '%s✗%s %s\n' "$C_BAD" "$C_OFF" "$*"; }
cloud_info() { printf '    %s\n' "$*"; }
cloud_prod_tag() { [[ $1 == true ]] && printf ' %s PROD %s' "$C_PROD" "$C_OFF"; return 0; }

# Replace our block in a config file, keeping everything else in it as it was.
# Sets CLOUD_CHANGED=1 when the file actually changed.
cloud_write_block() {
  local file=$1 content=$2 tmp
  local open="# >>> $CLOUD_MARKER >>>" close="# <<< $CLOUD_MARKER <<<"
  tmp=$(mktemp)
  if [[ -f $file ]]; then
    awk -v o="$open" -v c="$close" '$0 == o { s = 1; next } $0 == c { s = 0; next } !s' "$file" > "$tmp"
  fi
  if [[ -n $content ]]; then
    {
      echo "$open"
      echo "# Generated from env.yaml by aws-select and setup/install.sh -- edit env.yaml, not this."
      printf '%s\n' "$content"
      echo "$close"
    } >> "$tmp"
  fi
  if [[ -f $file ]] && cmp -s "$tmp" "$file"; then
    rm -f "$tmp"
    return 0
  fi
  mkdir -p "$(dirname "$file")"
  chmod 700 "$(dirname "$file")"
  cp "$tmp" "$file"
  chmod 600 "$file"
  rm -f "$tmp"
  CLOUD_CHANGED=1
}

# Rebuild everything derived from env.yaml. Skipped when the index is newer
# than env.yaml, since nothing can have changed; --force rebuilds anyway, which
# is what install.sh asks for. Problems go to stderr and return 1.
cloud_sync() {
  local json errors block
  CLOUD_CHANGED=0
  if [[ ${1:-} != --force && -f $CLOUD_INDEX && $CLOUD_INDEX -nt $ENV_FILE ]]; then
    return 0
  fi
  json=$(env_json) || { echo "could not read env.yaml -- is the age key in the keyring? (env-secrets check)" >&2; return 1; }
  errors=$(jq -r "$CLOUD_JQ_DEFS $CLOUD_JQ_VALIDATE" <<<"$json")
  if [[ -n $errors ]]; then
    sed 's/^/env.yaml: /' <<<"$errors" >&2
    return 1
  fi

  ( umask 077
    mkdir -p "$CLOUD_STATE"
    jq -r "$CLOUD_JQ_DEFS $CLOUD_JQ_INDEX" <<<"$json" > "$CLOUD_INDEX.tmp"
    if ! cmp -s "$CLOUD_INDEX.tmp" "$CLOUD_INDEX" 2>/dev/null; then
      mv "$CLOUD_INDEX.tmp" "$CLOUD_INDEX"
      exit 3
    fi
    rm -f "$CLOUD_INDEX.tmp"
    touch "$CLOUD_INDEX" ) || { (( $? == 3 )) && CLOUD_CHANGED=1 || return 1; }

  block=$(jq -r --arg helper "$AWS_CREDENTIAL_HELPER" "$CLOUD_JQ_DEFS $CLOUD_JQ_AWS_BLOCK" <<<"$json")
  cloud_write_block "$AWS_CONFIG" "$block"
}

# One cloud's lines from the index.
cloud_lines() { [[ -f $CLOUD_INDEX ]] && awk -F'\t' -v c="$1" '$1 == c' "$CLOUD_INDEX"; return 0; }

# --profile takes the profile name or the entry's own name, in any case.
cloud_resolve() {
  local q; q=$(tr '[:upper:]' '[:lower:]' <<<"$2")
  cloud_lines "$1" | awk -F'\t' -v q="$q" 'tolower($2) == q || tolower($3) == q' | head -n 1
}

# The picker: one row per account, production ones flagged, the one this
# terminal is on marked. Prints the chosen index line.
cloud_pick() {
  local cloud=$1 header=$2 current=$3 line choice i
  local -a lines labels
  mapfile -t lines < <(cloud_lines "$cloud")
  (( ${#lines[@]} )) || { echo "no $cloud accounts in env.yaml" >&2; return 1; }
  command -v gum >/dev/null || { echo "gum is not installed -- name the account with --profile" >&2; return 1; }
  [[ -t 0 ]] || { echo "no terminal to pick in -- name the account with --profile" >&2; return 1; }

  for line in "${lines[@]}"; do
    IFS=$'\t' read -r _ slug name prod d1 d2 <<<"$line"
    labels+=("$(printf '%-26s %-40s%s%s' "$name" "$d1 · $d2" \
      "$([[ $prod == true ]] && printf '  PROD')" \
      "$([[ $slug == "$current" ]] && printf '  ← current')")")
  done
  choice=$(gum choose --header "$header" --height 20 "${labels[@]}") || return 1
  for i in "${!labels[@]}"; do
    [[ ${labels[$i]} == "$choice" ]] && { printf '%s\n' "${lines[$i]}"; return 0; }
  done
  return 1
}

# A production account takes a deliberate yes: --yes, or a confirmation that
# defaults to no. Without a terminal and without --yes, the answer is no.
cloud_confirm_prod() {
  local name=$1 yes=$2
  [[ $yes == true ]] && return 0
  if [[ ! -t 0 ]] || ! command -v gum >/dev/null; then
    cloud_bad "$name is a production account -- pass --yes to switch to it here"
    return 1
  fi
  gum confirm --default=false --affirmative "Switch to production" --negative "Cancel" \
    "$name is a PRODUCTION account. Switch to it?"
}

cloud_current_file() { printf '%s/%s-current\n' "$CLOUD_STATE" "$1"; }
cloud_set_current() { ( umask 077; mkdir -p "$CLOUD_STATE"; printf '%s\n' "$2" > "$(cloud_current_file "$1")" ); }
cloud_clear_current() { rm -f "$(cloud_current_file "$1")"; }

# Every account of one cloud, for --list.
cloud_list() {
  local line found=false
  while IFS= read -r line; do
    found=true
    IFS=$'\t' read -r _ slug name prod d1 d2 <<<"$line"
    printf '  %-24s %-26s %s%s\n' "$slug" "$name" "$d1 · $d2" "$(cloud_prod_tag "$prod")"
  done < <(cloud_lines "$1")
  $found || echo "  no $1 accounts in env.yaml"
}

die() { echo "${0##*/}: $*" >&2; exit 1; }

# Questions, for aws-add and az-add. Every one has a default, which --yes
# takes: the script sets CLOUD_YES. Without a terminal, and without --yes,
# there is no one to ask, and that is an error. Whether there is a terminal is
# decided here, when the script sources this: the questions run inside $(...),
# where stdout is never one.
CLOUD_YES=false
CLOUD_TERMINAL=false
if [[ -t 0 && -t 1 ]] && command -v gum >/dev/null; then
  CLOUD_TERMINAL=true
fi
can_ask() {
  $CLOUD_YES && return 1
  $CLOUD_TERMINAL && return 0
  die "no terminal to ask in -- pass --yes to take the defaults, with any answers as flags"
}

# gum exits 130 when the question is dismissed: that ends the run, before
# anything has been created.
ask_text() {
  local header=$1 value=$2 rc=0 answer
  can_ask || { printf '%s\n' "$value"; return; }
  answer=$(gum input --header "$header" --value "$value" --width 60) || rc=$?
  (( rc == 0 )) || die "cancelled -- nothing was changed"
  printf '%s\n' "$answer"
}
ask_yes_no() {
  local question=$1 default=$2 rc=0
  can_ask || { printf '%s\n' "$default"; return; }
  gum confirm --default="$default" "$question" || rc=$?
  case $rc in 0) echo true ;; 1) echo false ;; *) die "cancelled -- nothing was changed" ;; esac
}
ask_choice() {
  local header=$1 value=$2 rc=0 answer; shift 2
  can_ask || { printf '%s\n' "$value"; return; }
  answer=$(gum choose --header "$header" --selected "$value" "$@") || rc=$?
  (( rc == 0 )) || die "cancelled -- nothing was changed"
  printf '%s\n' "$answer"
}

# For an entry that needs nothing: go through the questions anyway, to change
# its settings? Asked only in a terminal and without --yes, and no is the
# default -- anywhere else the entry is simply left as it is.
ask_to_change() {
  $CLOUD_YES && return 1
  $CLOUD_TERMINAL || return 1
  [[ $(ask_yes_no "$1" false) == true ]]
}
