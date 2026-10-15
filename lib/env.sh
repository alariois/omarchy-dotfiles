# env.yaml: this machine's accounts and secrets, in one file.
#
# Sourced by bin/env-secrets, the cloud scripts, setup/install.sh and
# setup/doctor.sh. The caller sets DOTFILES.
#
# env.yaml sits in the repo root and is gitignored. It is encrypted with sops
# to an age key, so the file itself can be copied anywhere -- a new machine,
# the test VM -- and is useless without the key. The key lives in the keyring
# and sops fetches it through SOPS_AGE_KEY_CMD, so reading it never prompts.
# env.example.yaml is the tracked twin: the same structure, made-up values.

ENV_FILE="$DOTFILES/env.yaml"
ENV_EXAMPLE="$DOTFILES/env.example.yaml"

# Where the age key lives in the keyring, as secret-tool attribute pairs.
ENV_KEY_ATTRS=(service omarchy-dotfiles key sops-age)

# sops takes the key from SOPS_AGE_KEY when that is set -- the VM test passes
# it that way, since an ssh session has no keyring -- and otherwise from the
# keyring. Set here, not only in shell/bashrc, so a credential_process started
# by a program that never read bashrc still finds the key.
env_key_env() {
  if [[ -z ${SOPS_AGE_KEY-} && -z ${SOPS_AGE_KEY_CMD-} && -z ${SOPS_AGE_KEY_FILE-} ]]; then
    export SOPS_AGE_KEY_CMD="secret-tool lookup ${ENV_KEY_ATTRS[*]}"
  fi
}

env_key_stored() { secret-tool lookup "${ENV_KEY_ATTRS[@]}" >/dev/null 2>&1; }

# sops writes its metadata under a top-level `sops:` key; plain YAML has none.
env_is_encrypted() { [[ -f $ENV_FILE ]] && grep -q '^sops:' "$ENV_FILE"; }

# The whole of env.yaml as JSON, decrypted. A file not yet encrypted is read
# as it is, so it still works -- doctor.sh is what complains about it.
env_json() {
  [[ -f $ENV_FILE ]] || { echo "no env.yaml at $ENV_FILE" >&2; return 1; }
  if env_is_encrypted; then
    env_key_env
    sops --decrypt --output-type json "$ENV_FILE"
  else
    yq -o json '.' "$ENV_FILE"
  fi
}

# Rewrite env.yaml through a yq expression, with no plaintext copy on disk at
# any point: decrypted into a pipe, edited, encrypted again to the same
# recipients, and moved over the old file only once the new one decrypts.
# Values the expression needs, secrets above all, come in through the
# environment (strenv), never on a command line. `sops set` would be the
# obvious tool, but it counts comments as list entries, so in a commented
# list like env.yaml's it writes to the wrong one.
env_update() {
  local expr=$1 recipients tmp
  env_is_encrypted || { echo "env.yaml is not encrypted -- 'env-secrets init' first" >&2; return 1; }
  recipients=$(yq -r '.sops.age[].recipient' "$ENV_FILE" | paste -sd, -)
  [[ -n $recipients ]] || { echo "env.yaml names no age recipient to encrypt to" >&2; return 1; }
  env_key_env
  tmp=$(mktemp "$ENV_FILE.XXXXXX") || return 1
  if ( set -o pipefail
       sops --decrypt "$ENV_FILE" | yq "$expr" |
         sops --encrypt --input-type yaml --output-type yaml --age "$recipients" /dev/stdin > "$tmp" &&
       sops --decrypt --input-type yaml --output-type yaml "$tmp" >/dev/null ); then
    chmod 600 "$tmp"
    mv "$tmp" "$ENV_FILE"
  else
    rm -f "$tmp"
    echo "could not rewrite env.yaml -- it is unchanged" >&2
    return 1
  fi
}

# The key paths of a YAML file with list indices folded to [] -- its
# structure, not its content. sops encrypts values and leaves keys readable,
# so this works on the encrypted file without the key. sops's own metadata is
# not structure.
env_paths() {
  yq -o json 'del(.sops)' "$1" |
    jq -r '[paths | map(if type == "number" then "[]" else . end) | join(".")] | unique | .[]'
}

# Does env.example.yaml still describe env.yaml? One line per difference on
# stdout; returns 1 when there are any, 2 when a file cannot be read.
#
#   - a key env.yaml uses that the example does not show: the example is
#     behind, and the next machine set up from it will not know the key exists.
#   - a key the example shows, outside any list, that env.yaml no longer has:
#     a section or setting was removed and the example kept it.
#
# Fields inside list entries are optional per entry -- one AWS account has
# access keys, the next a role -- so the example may show a field that no
# entry in env.yaml happens to use.
env_structure_diff() {
  local env_p ex_p line rc=0
  env_p=$(env_paths "$ENV_FILE") || return 2
  ex_p=$(env_paths "$ENV_EXAMPLE") || return 2
  while IFS= read -r line; do
    [[ -n $line ]] || continue
    echo "only in env.yaml:          $line"
    rc=1
  done < <(comm -23 <(sort <<<"$env_p") <(sort <<<"$ex_p"))
  while IFS= read -r line; do
    [[ -n $line && $line != *'[]'* ]] || continue
    echo "only in env.example.yaml:  $line"
    rc=1
  done < <(comm -13 <(sort <<<"$env_p") <(sort <<<"$ex_p"))
  return $rc
}
