# omarchy-dotfiles (quattro)

Personal configuration layered on top of [Omarchy](https://omarchy.org/) 4.x.

## The model: track deltas, never defaults

This repo stores **only what differs from stock Omarchy**. It never contains a
copy of an Omarchy config file. That is the whole design, and it exists because
of how Omarchy writes to disk:

| Omarchy action | How it writes | Effect on us |
|---|---|---|
| `omarchy refresh <x>` | `cp -f` over the target | writes *through* a symlink; link survives |
| `omarchy update` migrations | `mv "$tmp" "$target"` | **replaces a symlink with a regular file**, silently detaching it |

So file ownership decides the mechanism, and `setup/targets.sh` has one lane
for each — plus a third for source we compile.

### `HOOKS` — files Omarchy owns

`~/.bashrc`, `~/.config/tmux/tmux.conf`, `hypr/*.lua`, `shell.json`, terminal
configs, herdr's `config.toml`. These are left stock in place and get one
appended managed block:

```bash
# >>> omarchy-dotfiles >>>
source "/home/you/projects/omarchy-dotfiles/shell/bashrc"
# <<< omarchy-dotfiles <<<
```

Our real configuration lives at the far end of that include, inside this repo.
A migration can clobber the block — it can never touch our config. And
`hooks/post-update.d/reapply-dotfiles.hook` re-asserts every block after each
`omarchy update`, so the clobber self-heals.

The block is always appended **last**, which is what lets an include override a
setting the stock file above it already made. `nvim/options.lua` relies on this:
stock sets `relativenumber = false`, our `dofile` runs after it and sets `true`.

**TOML is the exception** (`toml` style, used for herdr). TOML has no include,
so the block holds a *copy* of the repo file: edit `herdr/config.toml`, then
re-run `install.sh`, and `doctor.sh` reports the block `STALE` until you do. It
goes at the **top**, not the bottom, since a key appended after the stock
tables would land inside the last of them. And it cannot override anything —
TOML rejects a key set twice — so it may only add settings stock leaves unset.
`install.sh` refuses to write a file that would not parse as exactly stock plus
our settings, which is what a leftover hand-edited copy of one of them causes.

**JSON is the other exception** (`claude` style, used for Claude Code's
`~/.claude/settings.json`). JSON has neither an include nor a comment to hang a
block on, so the block is our hook entries themselves: each command ends in a
`# omarchy-dotfiles` shell comment, which the shell running it ignores and
`install.sh` uses to find them again. A run drops every marked entry and merges
`claude/hooks.json` in afresh; entries nobody marked are never touched, and nor
is the rest of the file.

### `LINKS` — files Omarchy never writes

The live path becomes a symlink into this repo, so no drift is possible: the
live file *is* the repo file. Nothing to repair after an update. Prefer this
lane whenever ownership allows it.

Never link a path Omarchy migrates — a migration `mv`s over its target and
would replace the link with a regular file. And only link a whole *directory*
when Omarchy owns nothing inside it.

### `SEEDS` — machine-local files the repo must not own

A template copied into place the first time and then left alone forever. The
point is the leaving alone: the target holds content that should not be
committed, so an existing file is never compared, never overwritten, and never
reported as drift.

This repo is public, so anything with a phone number, a client name, an
internal hostname, or an address goes here rather than into a tracked file.
`xcompose/XCompose` ends with an `include` of its seeded local file, which is
how a public Compose file carries private expansions.

### `BUILDS` — source we compile

Neither lane above fits a program: the repo tracks source, but what the system
needs is a binary, and a binary is a build artifact rather than config. So the
source lives in the repo, `install.sh` runs `make install` out of it, and the
compiled output is gitignored. A compile failure is reported with the
compiler's output and makes `install.sh` exit non-zero.

`install.sh` invokes `make` only when the installed binary is not already a
build of the current source, so a repeat run is silent. It decides that by
hashing both — the `.c`, `.h` and `Makefile` inputs, and the artifact — and
comparing against a stamp under `~/.local/state/omarchy-dotfiles/`.

That used to be an mtime comparison, which cannot actually answer the
question. A checkout stamps files with the time of the checkout, a restore
from backup or a copy between machines carries whatever mtime it likes, and
`touch` settles it outright. Replacing the installed binary with a stub and
touching it was enough to make `install.sh` report `ok` and `doctor.sh` report
`built`, with nothing installed that worked. Both now agree, because both ask
`lib.sh` the same question.

### `FONTS` — families Omarchy does not ship

`install.sh` unpacks these into `~/.local/share/fonts`, which fontconfig picks
up through its `<dir prefix="xdg">fonts</dir>` entry — no root, and pacman's
world is untouched.

Per-user rather than `pacman -S` because the package route is a dead end here.
The Arch package carrying the no-ligature faces, `ttf-jetbrains-mono-nerd`,
`Conflicts With` `ttf-jetbrains-mono-nerd-basic` — which the `omarchy` package
depends on *by that exact name*, so the provided-name alias does not save it.
Installing it would mean breaking omarchy's dependency to gain 232 MB of faces
for the sake of four.

The check is "does fontconfig resolve this family", not "are the files there".
Those differ, and the difference is silent: fontconfig answers a missing family
by substituting another rather than failing, so a half-unpacked font produces
no error anywhere — just the wrong glyphs.

A failure here warns instead of counting as a conflict. It is the only lane
that needs the network, it is cosmetic when it fails, and `install.sh` runs
unattended from the post-update hook — a transient outage during an `omarchy
update` should not report a broken install. `doctor.sh` keeps a missing family
visible, and the run's summary reports the warning count rather than claiming
everything is current.

### `RELEASES` — single binaries no Arch repo carries

`install.sh` downloads these from the project's own releases into
`~/.local/bin` — `openobserve-cli`, so far, for querying logs, metrics and
traces in OpenObserve. Each entry pins a version and the SHA-256 of each
architecture's file, and only a file with that hash is installed. A checksum
from the same release would not do: whoever could replace the binary could
replace the checksum next to it. So upgrading is a deliberate edit to
`setup/targets.sh` — the new version and its hashes — never "latest".

`install.sh` remembers the hash of every file it installs, and replaces only
one of those: an older pin is upgraded, a file you put there yourself is
reported as a conflict and left alone. A download that is not the pinned file
is a conflict too; one that fails warns, as a font's does. `doctor.sh`
reports a missing binary, an older pin, and one that is neither.

### Keeping Hyprland in step

Hyprland watches the files under `~/.config/hypr`, but our config is not there:
those files hold a one-line `dofile()` of a path in this repo, and the watcher
does not follow it. So editing `hypr/bindings.lua` changes nothing in the
running session — a new bind was still missing from `hyprctl binds` three
seconds later, and appeared only after an explicit `hyprctl reload`.

`install.sh` therefore ends by reloading Hyprland, stamped the same way so a
repeat run does not. Outside a session it says so and writes no stamp, which
leaves the reload to the next run that has one — an `omarchy update` on a
console, say. `doctor.sh` reports `BEHIND` when the session is running older
config than the repo holds.

## Layout

```
shell/bashrc                              bash config (hooked into ~/.bashrc)
tmux/tmux.conf                            tmux config (hooked)
nvim/options.lua                          nvim options (hooked into Omarchy's LazyVim)
hypr/bindings.lua                         Hyprland keybindings (hooked)
hypr/input.lua                            keyboard remapping, key repeat, touchpad scroll (hooked)
hypr/looknfeel.lua                        gaps and corner rounding (hooked)
hypr/hyprland.lua                         window rules: Slack on workspace 5 (hooked)
foot/foot.ini                             terminal font (hooked, `ini` style)
herdr/config.toml                         herdr's notification setup (hooked, `toml` style)
claude/hooks.json                         when Claude Code dings (hooked, `claude` style)
claude/ding                               the ding itself
xkb/                                      custom xkb options behind it (linked)
nvim/plugins/*.lua                        added LazyVim plugin specs (linked)
nvim-chad/                                standalone nvim config (linked wholesale)
xcompose/XCompose                         compose-key expansions (linked)
xcompose/XCompose.local.seed              template for the private half (seeded)
hypr-nav/                                 C source for the hypr-nav binary (built)
himalaya/config.toml                      Gmail over IMAP for scripting (linked)
bin/msgs                                  newest message(s), mail or SMS (linked)
bin/msg-code                              one-time code extraction (linked)
bin/msg-peek                              newest message in a floating nvim buffer (linked)
bin/msg-otp                               login code to clipboard, via toast (linked)
bin/term-here                             SUPER+RETURN, file-manager aware (linked)
bin/files-here                            SUPER+SHIFT+F, the mirror of it (linked)
bin/tmux-cwd                              the pane on screen, for both (linked)
bin/peek-here                             toast where those two keys would open (linked)
nautilus/term-here.py                     the Nautilus half of it (linked)
omarchy-shell/workspaces/                 monitor-aware bar workspace markers (linked)
setup/targets.sh                          the delta table -- single source of truth
setup/lib.sh                              freshness checks shared by the two below
setup/install.sh                          assert every block, link, build, package, and hook
setup/doctor.sh                           report state and unmanaged drift
hooks/post-update.d/reapply-dotfiles.hook re-assert blocks after `omarchy update`
vm/omarchy-vm                             disposable Omarchy VM for testing all of the above
env.example.yaml                          the shape of env.yaml, made-up values (tracked)
lib/env.sh                                reading env.yaml: decryption, structure check
lib/cloud.sh                              AWS/Azure profiles generated from env.yaml
bin/aws-select, bin/az-select             switch this terminal to an account (linked)
bin/aws-add                               add an AWS account to env.yaml, or renew its key (linked)
bin/az-add                                add an Azure subscription to env.yaml, or renew its secret (linked)
bin/aws-env-credentials                   credential_process for key-based AWS profiles (linked)
bin/env-secrets                           init/edit/check env.yaml, keep its key (linked)
git-hooks/pre-commit                      env.yaml never committed, example kept in step (linked)
```

## Usage

```bash
setup/install.sh      # wire the repo into the live system; safe to re-run
setup/doctor.sh       # what's hooked, what's linked, what drifted from stock
```

### On a fresh Omarchy

`setup/install.sh` reapplies everything the repo owns: managed blocks, symlinks,
the machine-local seed, the compiled `hypr-nav` binary, the packages a stock
Omarchy lacks, pinned release binaries, the no-ligature font, the Omarchy
post-update hook, and a Hyprland reload to make it all live.

The packages are `himalaya`, `python` and `kdeconnect`, and for the cloud
accounts `aws-cli-v2`, `azure-cli`, `sops`, `age` and `go-yq`, and
`bitwarden-cli` for the Bitwarden vault (`PACKAGES` in `setup/targets.sh`),
installed in one `omarchy-pkg-add`, so sudo asks for your password once if it
has none cached. AWS CLI v1 is removed first when pacman
has it: v2 conflicts with it, and `--noconfirm` answers pacman's "Remove
aws-cli?" with no (`REPLACED` in the same file). A v1 that pacman did not
install is reported, never deleted. That happens only when you run it from a
terminal. The post-update hook runs it unattended, where a password prompt
would hang an `omarchy update`, so there it only warns and names the package.
`jq` and `fzf` are listed though Omarchy ships them, to keep them on every
machine. `less`, `wl-clipboard` and `xdg-terminal-exec` are not listed because
they are all on Omarchy's own base list, `gawk` comes with Arch's `base`, and
`make`/`gcc` come with `base-devel`.

`install.sh` then points `bw` at Bitwarden's EU server (`BITWARDEN_SERVER` in
the same file) rather than its default, bitwarden.com. bw only allows that
while logged out, so a `bw` logged in to another server is reported -- `bw
logout`, then run `install.sh` again -- and never logged out for you.

`bwu` unlocks the vault in the terminal it is run in: the master password the
first time, and in every terminal after that a fingerprint, or your password,
for sudo. `bin/bw-session` keeps the session key `bw unlock` returns in a file
only root can read -- never the master password -- and a `bw` shell function
hands the key to bw alone, so nothing else run in that terminal inherits it.
`bw lock` locks the vault for every terminal, and the next `bwu` asks for the
master password again.

```bash
bwu get                 # pick with fzf; print the username and password
bwu get github          # the same, the search started with "github"
bwu get -u   / -p       # the username alone / the password alone
bwu get -c              # copy the password instead (-c -u: the username)
bwu update              # sync with the server, and cache the vault anew
bwu --update get        # the same, then pick
bwu lock                # lock the vault everywhere, and delete the cache
```

`bwu get` picks from a cache of the vault, so the list is there at once and
bw does not run. The cache holds every item, secrets included, encrypted with
age to a key made new with every unlock and kept the way the session key is:
in root's store, and unexported in the terminals unlocked with it. A cache from
an earlier unlock cannot be read, and `bw lock` deletes it, so a lock still
locks everything. Only when there is no cache it can read does `bwu get` sync
with the server and write one; changes made elsewhere, in the browser or on
the phone, show up after `bwu update`.

The list shows every item: a login with its username and website, anything
else by its name. The search covers the name, username and website, so a note
is found by its title and its text is never searched. A note prints its text,
a card its number, expiry and code. A copy is marked sensitive for clipboard
managers, and cleared after 45 seconds unless something else has been copied
since.

Two things it deliberately does not do, because it cannot:

1. **The two mail passwords**, which belong in the keyring and nowhere else:

   ```bash
   secret-tool store --label="Gmail app password (himalaya)" \
     service himalaya account <gmail-address>
   secret-tool store --label="Zone mail (himalaya)" \
     service himalaya account <work-address>
   ```

2. **Gmail's "Leave a copy of retrieved message on the server"**, a per-account
   tick-box in Gmail's own settings. Without it Gmail drains the Zone mailbox
   and the `superhands` account reads empty.

`setup/doctor.sh` reports both, and any package still missing, so the fastest
way to find out what a new machine still needs is to run it.

`install.sh` exits non-zero if it hit a conflict — a real file or directory
sitting where a link belongs, whose contents it does not recognise. It never
deletes such a file; it reports it and leaves the decision to you. (A path that
already matches the repo byte for byte is adopted silently, since nothing can
be lost.)

`doctor.sh`'s last section is the useful one: it diffs every Omarchy-owned
config against the shipped stock template *with our managed blocks stripped
out*, so anything it reports is a local edit this repo is not capturing. Port
it into the repo as a delta, or revert it with
`omarchy refresh config <path>`.

## Testing in a VM

`vm/omarchy-vm` boots a disposable stock Omarchy in QEMU, for testing what this
repo does to a machine it has never touched. Pointing `install.sh` at an empty
`HOME` proves the plumbing but not the part that matters: there, Omarchy's own
files contain nothing but our block. Whether our include still wins below the
stock content, and whether the post-update hook puts the block back after a
migration clobbers it, only a real Omarchy can answer.

It is a golden base disk plus a throwaway overlay:

| Command | What it does |
|---|---|
| `install` | download and verify the pinned ISO, create the base disk, boot the installer. Once, slow. |
| `reset` | delete the overlay and cut a new one off the base. Instant. |
| `run` | boot the overlay; changes last until the next `reset` |
| `throwaway` | boot the base with every write discarded on shutdown |
| `base-shell` | boot the base **read-write**, for what every fresh machine should have |

Nothing writes to the base after `install` except `base-shell`, so a pristine
machine is always one `reset` away. Everything lives in
`~/.local/share/omarchy-vm` (ISO, base, overlay, UEFI vars), outside the repo.

The loop, once the base exists:

```bash
vm/omarchy-vm reset            # fresh machine
vm/omarchy-vm run &            # boot it
vm/omarchy-vm push             # rsync this working tree, uncommitted changes included
vm/omarchy-vm ssh              # then: cd projects/omarchy-dotfiles && ./setup/install.sh
```

`push` copies the working tree rather than having the guest clone from GitHub,
so what gets tested is the repo as it is now, not as of the last commit.

### Setting it up once

1. **Host packages:** `sudo pacman -S --needed qemu-desktop edk2-ovmf`, and
   your user in the `kvm` group. `socat` is needed for `console` and for
   answering the unlock prompt, `rsync` for `push`. `vm/omarchy-vm status`
   checks the host and lists what exists.
2. **`vm/omarchy-vm install`**, then install Omarchy by hand. The script prints
   what to do inside the guest before it boots: turn disk encryption off, and
   install and enable `openssh` with `ufw allow 22/tcp` (stock Omarchy ships
   neither sshd enabled nor port 22 open). Do not install this repo there; an
   untouched Omarchy is the point of the base.
3. **`vm/omarchy-vm user <name>`** with the account you created in the
   installer, since `ssh` and `push` cannot guess it.
4. If the base disk ended up encrypted anyway, **`vm/omarchy-vm luks-set`**
   stores the passphrase and every boot answers the unlock prompt itself. The
   prompt goes to the serial console, so without this the VM window just looks
   dead.
5. **`vm/omarchy-vm prep-base`**, which boots the base, installs your ssh key
   and gives the guest account passwordless sudo, then powers off and cuts a
   fresh overlay. You type the guest password twice, once for ssh-copy-id and
   once for sudo, and never again: every reset after this can be pushed to,
   run `install.sh` (packages included) and be stopped without you. The sudo
   rule is a single drop-in, `/etc/sudoers.d/90-omarchy-vm`, which is fine for
   a disposable guest and never something to copy to a real machine.

Or skip all of that: **`vm/omarchy-vm autoinstall`** builds the base with
nobody at the keyboard. The Omarchy ISO installs itself when a drive labelled
`cidata` carries its configurator's answers, so the script writes those -- the
4.0.2 configurator's own format, an unencrypted disk, user `test`, a generated
password kept in `~/.local/share/omarchy-vm/guest-password` -- plus your ssh
key, builds the drive with `bsdtar`, lets the ISO install and reboot, and adds
the passwordless sudo `prep-base` would. 10-20 minutes, no input.

### The test

```bash
vm/omarchy-vm test             # everything, unattended, with a verdict
vm/omarchy-vm test --keep      # and leave the machine up afterwards to look at
```

`test` is the whole loop above with checks in between, and it needs nothing
from you: it downloads the ISO if there is none, builds the base with
`autoinstall` if there is none, then boots a fresh machine off it and runs
`omarchy update -y`, `install.sh` twice (the second run must change nothing),
`doctor.sh`, and a simulated migration that the post-update hook has to
repair. It also puts AWS CLI v1 in the guest first, so the upgrade to v2 is
tested rather than assumed.

The cloud accounts are tested too. With an `env.yaml` here and its key in the
keyring, the encrypted file is copied in, the key is passed on stdin per
command (never written to the guest's disk), and every account is switched to
for real. Without one, the plumbing is tested on `env.example.yaml`
encrypted to a throwaway key: profiles generated, production guard refusing,
and every switch failing with a clean ✗ -- placeholder credentials that
worked would be the bug.

Output is TAP (`ok 3 - ...` / `not ok 4 - ...`), exit 0 when everything
passed, 1 when a check failed, 2 when the test could not get far enough to
judge. Each run gets its own directory under
`~/.local/share/omarchy-vm/test-runs/` with its overlay, serial log and every
step's output, and never touches the overlay `run` uses. Without a display it
runs headless (`--headless` forces it): no window, plain `virtio-vga`, which
is how Omarchy's own ISO tests run in CI. That, plus `OMARCHY_ENV_AGE_KEY` for
the key where there is no keyring, is what a CI job needs: KVM, `qemu-desktop`
and `edk2-ovmf`, and about 8GB of memory.

### When the guest misbehaves

`console` attaches to the serial console (Ctrl-] detaches), the way in when
the screen is black or sshd is down. `log` prints this boot's serial output,
`screenshot` captures the guest's own screen, and `stop` shuts it down over ssh
(`--force` pulls the plug, which costs nothing on an overlay). The clipboard is
bridged both ways on every boot; `OMARCHY_VM_CLIPBOARD=0` turns that off.
Memory, CPUs, disk size, ssh port and ISO version can all be overridden with
environment variables, listed in `vm/omarchy-vm --help`. The reasoning behind
each choice (USB input, `virtio-vga-gl`, the ssh and firewall steps) is in the
script's comments.

## Cloud accounts

Every AWS and Azure account is defined once, in `env.yaml`, and a new machine
gets all of them from that one file -- no logins typed.

```bash
aws-select                         # pick an AWS account for this terminal
aws-select --profile superhands    # or name it; tab completes profile names
az-select --profile "Acme Prod" --yes  # --yes: no question for production
aws-select --console               # also open the console, signed in
aws-whoami; az-whoami              # which account this terminal is on, if any
aws-select --current | --list | --clear
```

Each switch ends with a real request -- `aws sts get-caller-identity`, or an
Azure Resource Manager call listing the subscription's resource groups -- and
prints ✓ with what the cloud answered, or ✗ with its error, in which case
nothing changes. `az account show` alone would prove nothing; it reads a local
cache.

The switch is for this terminal: `aws-select` exports `AWS_PROFILE`,
`az-select` an `AZURE_CONFIG_DIR` of the account's own (so each Azure account
keeps its login, and switching never signs another out). Only that terminal:
every other one keeps its own, and a new one starts on no account, so run
`aws-select` or `az-select` again there. The prompt shows none of it: `aws-whoami` and `az-whoami` say which account a terminal is on, marking
production ones -- or that it is on none, and so what `aws` or `az` falls
back to. They read the account list, so they answer at once and never ask
the cloud.

**Logins with nobody typing.** AWS accounts use access keys -- one IAM user
per account, or one IAM user whose keys assume a role in each other account
(fewer keys, sessions that expire on their own). Azure accounts use a service
principal per tenant: since October 2025 Azure requires MFA for changes made
from the CLI by people, and service principals are exempt. The generated AWS
profiles read their keys through `aws-env-credentials` at the moment the CLI
needs them, so there is no plaintext copy in `~/.aws/credentials`; `az` does
keep its own copy of a service principal's secret under its config directory,
which cannot be avoided. Billing pages stay hidden from every IAM identity
until the account's root user turns on "IAM user and role access to Billing
information", once per account.

**`env.yaml`** sits in the repo root, gitignored, and encrypted with sops to
an age key: the file can be copied anywhere and is useless without the key.
The key is one line kept in the keyring, read through `SOPS_AGE_KEY_CMD` so
nothing prompts -- and kept in your password manager too, because nothing else
can open the file.

```bash
env-secrets init         # first time: key into the keyring, env.yaml from the example, encrypted
env-secrets show-key     # copy the key into your password manager
env-secrets edit         # fill in the accounts
env-secrets import-key   # on a new machine, before setup/install.sh
env-secrets check        # encrypted, openable, complete, in step with the example
```

`env.example.yaml` is the tracked twin, with made-up values -- never a real
one, and never a real client name, since this repo is public. A key added to
`env.yaml` must appear there too, and a section removed from one must go from
the other; fields inside a list entry are per entry, so the example may show
ones no entry uses. sops leaves keys readable and encrypts only values, so
this is checked without the key: by `env-secrets check`, `install.sh`,
`doctor.sh`, and `git-hooks/pre-commit`, which also refuses any commit that
stages `env.yaml` itself.

`install.sh` regenerates everything derived from `env.yaml` on each run: the
profiles in a managed block of `~/.aws/config`, and an account list without
secrets in `~/.local/state/omarchy-dotfiles/cloud/` that the picker, tab
completion and prompt read. `doctor.sh` warns 30 days before an Azure secret's
`secret_expires`.

### Adding an Azure subscription: `az-add`

```bash
az login                            # as yourself, once
az-add                              # the subscription az login is on
az-add --subscription "Acme Prod"   # another one your login can see
az-add --profile acme-prod          # an entry already in env.yaml: check, repair, renew
az-add --renew                      # a new secret now, even if the old one is fine
```

Your own `az login` cannot go in `env.yaml` -- it belongs to this machine, and
Azure asks people for MFA -- so `az-add` uses it once to give the subscription
a service principal, and writes that into `env.yaml` straight from Azure,
never printed. It looks before it creates: an entry whose secret works and has
over 30 days left is left alone; one whose secret fails or is running out gets
a new secret, and the old one is deleted once the new one signs in; a
subscription in a tenant `env.yaml` already has an app for reuses that app.
Only a tenant with none gets a new app, `omarchy-dotfiles (<your login>)`,
and an earlier run's app of that name is found and reused rather than
duplicated. Name, production or not, email, role (Owner or Contributor) and
the secret's lifetime are asked first, then a summary to confirm -- for an
entry being repaired too, its own answers the defaults; `--yes` takes the
defaults, and flags (`--name`, `--prod`, `--no-prod`, `--email`, `--role`,
`--years`) give answers up front. For an entry that already works there is
nothing to create, so in a terminal it asks whether to change the settings,
with the entry's own filled in; `--name`, `--prod`, `--no-prod` and `--email`
change them without asking. A run that fails before `env.yaml` is written
deletes what it created. The last step is `az-select`,
retried for a few minutes while Azure catches up with a new app or role.

### Adding an AWS account: `aws-add`

```bash
aws login                           # as yourself -- root, or an admin -- once
aws-add                             # the account aws login is on
aws-add --profile acme-prod         # an entry already in env.yaml: check, repair, renew
aws-add --renew                     # a new access key now, even if the old one works
```

An `aws login` session belongs to this machine and runs out, and root's own
access keys are ones AWS says never to make -- so `aws-add` uses the login
once to give the account an IAM user, `omarchy-dotfiles`, with
`AdministratorAccess` (or `PowerUserAccess`, `ReadOnlyAccess`, or any managed
policy named with `--policy`) and an access key, written into `env.yaml`
straight from AWS, never printed. It looks before it creates: an entry for the
account whose key signs in is left alone; one whose key fails gets a new key
for the same IAM user, and the old one is deleted once the new one signs in;
an earlier run's `omarchy-dotfiles` user is reused rather than duplicated.
Entries with no `account_id` are asked by signing in, so a key typed in by
hand is found too, and a root key found that way is replaced and pointed out,
never deleted. An entry that assumes a role has no key to repair -- its keys
are its `source` entry's -- so for it there are only the settings. AWS
allows an IAM user two keys; with two already, `aws-add` lists them and
stops, rather than guess which one to delete. Whatever the entry is named,
the account's number is kept in `account_id`, as an Azure entry keeps its
`subscription_id` and `tenant_id`. The questions -- asked again for an
account already there, to change its settings -- `--yes` and the flags
(`--name`, `--prod`, `--no-prod`, `--email`, `--region`, `--policy`) work as
in `az-add`, as do the rollback and the proof: `aws-select`, retried for up
to a minute while a new key starts to work.

Both need `env.yaml` encrypted first (`env-secrets init`). After a renewal,
copy `env.yaml` to your other machines: the secret or key theirs holds was
just deleted.

## Adding a delta

1. Put the configuration in a repo file (e.g. `hypr/looknfeel.lua`).
2. Add one row to `setup/targets.sh` — to `HOOKS` if Omarchy owns the live
   file, to `LINKS` if it does not, to `BUILDS` if it needs compiling, to
   `SEEDS` if it must stay off GitHub.
3. Run `setup/install.sh`.

## Notes on specific configs

**Neovim.** Omarchy ships its LazyVim config from a *separate* package,
`/usr/share/omarchy-nvim/config`, not from `/usr/share/omarchy/config` — which
is why `doctor.sh` carries two stock roots. Its migrations write three files in
there: `lua/config/options.lua` (prepends the `remote_clipboard` require),
`lua/config/remote_clipboard.lua`, and `lua/plugins/theme.lua` (a symlink into
the current theme). So:

- `options.lua` is Omarchy-owned → hooked, not linked.
- New files under `lua/plugins/` are ours; lazy.nvim imports the whole
  directory and migrations only touch files Omarchy shipped, so extra specs are
  linked in individually. Link the *files*, never the directory.
- `lazy-lock.json` is in `doctor.sh`'s drift ignore list — nvim rewrites it on
  every plugin update, so diffing it reports noise forever.

`nvim-chad/` is a second, standalone config with no overlap with Omarchy's.
Launch it with `nv` (aliased in `shell/bashrc`); plain `nvim` stays on
Omarchy's LazyVim.

**bash.** `shell/bashrc` carries `set -o vi` and the `nv` alias. The 3.x-era
`.bashrc` on `main` had five more personal lines, all deliberately dropped:
`nvm`, `~/.cargo/env`, `~/.local/bin/env` (uv), and Android SDK
platform-tools all point at paths that do not exist on this machine — sourcing
them would error on every shell start — and `alias dot=...` drove a bare git
repo at `~/.dotfiles` that this repo replaces. Omarchy 4 manages toolchains
with mise. Re-add any of them the day the tool is actually installed.

**tmux.** The only surviving delta is `unbind k`. The 3.x-era snapshot on `main`
also carried extended keys, `escape-time`, and a copy-mode status indicator —
4.x stock now ships all three verbatim, so they stopped being deltas. That is
the model paying for itself: a whole-file copy would still be "carrying" them
as a permanent merge conflict against upstream.

**hypr-nav.** One motion — Alt+hjkl — for vim splits, tmux panes, and Hyprland
windows. It spans three layers, so the port touches all three lanes:

| Piece | Lane | Where |
|---|---|---|
| Alt+hjkl keybindings | `HOOKS` | `hypr/bindings.lua` → `~/.config/hypr/bindings.lua` |
| the binary | `BUILDS` | `hypr-nav/` → `~/.local/bin/hypr-nav` |
| vim half of the hand-off | `LINKS` | `nvim/plugins/hypr-nav.lua` |

Hyprland has to own the keys, because it is the only layer that sees the
keypress first. `hypr-nav` then decides where the motion belongs, by how the
focused window is put together:

| Focused window | Motion goes to | How the key gets there |
|---|---|---|
| tmux, vim in the active pane | vim, then tmux, then Hyprland | `tmux send-keys M-hjkl` |
| tmux, no vim | tmux pane, then Hyprland | `tmux select-pane` |
| a bare vim, no tmux | vim, then Hyprland | `hl.dsp.send_shortcut` ALT+hjkl |
| anything else | Hyprland | `hl.dsp.focus` |

In the two vim rows, vim calls back with `--from-vim` once the cursor is at the
edge of its splits, and the motion continues outward from there.

The bare-vim row is why `hypr-nav` reads `/proc`: with no tmux there is no
send-keys channel, so it walks the window's process tree looking for a vim that
is genuinely in front of its tty — the tty's foreground process group, and not
stopped. Both halves matter. After Ctrl-Z under an interactive shell the tty
hands off to the shell's group, but a vim started by a shell with no job
control (`bash -c nvim`) keeps the tty even in state `T`. Matching either one
would send Alt+hjkl to something that cannot act on it, swallowing the press
instead of moving the Hyprland focus. tmux panes never match here — they are
children of the tmux *server*, not of the terminal — so this can never shadow
the tmux path.

Hyprland does not re-run keybinds for a shortcut it sent itself, so
`send_shortcut` cannot loop back into `hypr-nav`.

Two things it depends on, both already true on stock Omarchy 4:

- `~/.local/bin` on the session PATH. Omarchy's `default/bash/env-bootstrap`
  adds it, and `default/uwsm/env.d/10-omarchy` sources that, so the Hyprland
  session can resolve `hypr-nav` by name.
- `set -g focus-events on` in tmux. `hypr-nav` picks the right tmux client by
  its `focused` flag, because multi-window terminals like Ghostty share one PID
  across every window and PID ancestry alone cannot tell them apart.

One thing to know about Hyprland versions: 0.56 (Omarchy 4) moved `hyprctl
dispatch` onto Lua, so the old `hyprctl dispatch movefocus l` string now parses
as Lua and fails. `hypr-nav` emits the Lua form and falls back to the string
one, so the same binary works against Omarchy 3 and 4.

`make -C hypr-nav test` runs 46 unit tests; `make -C hypr-nav test-integration`
drives a real tmux session for 14 more.

**term-here.** SUPER+RETURN and SUPER+SHIFT+F both mean "here", so both have to
know where "here" is. Stock Omarchy asks `omarchy-cmd-terminal-cwd`, which
reads the cwd of the focused *terminal's* child process and falls back to
`$HOME` for everything else. That is right for a plain terminal and wrong for
the two windows that come up most: a file manager, which is the one other
window where "the directory I am looking at" is a real answer, and a terminal
running tmux, whose child is the tmux client — not a shell, so the reading is
discarded, and its directory is wherever tmux was first started anyway rather
than the pane on screen.

So `bin/term-here` answers those two and hands every other case straight back
to `omarchy-launch-terminal`, and `bin/files-here` does the same for the file
manager. With a file selected the terminal also pre-types the path, relative to
the folder it is about to open:

| Focused window | Opens in | Pre-typed |
|---|---|---|
| Nautilus, nothing selected | the folder that window shows | — |
| Nautilus, `env.yaml` selected | that folder | ` ./env.yaml`, cursor at column 0 |
| a terminal running tmux | the active pane's cwd | — |
| a terminal | that terminal's cwd (stock) | — |
| anything else | `$HOME` (stock) | — |

The Nautilus rows apply to SUPER+RETURN only: SUPER+SHIFT+F over a file manager
still opens `$HOME`, as it always did, since a second window on the same folder
is not what the key is for.

SUPER+SHIFT+F needed almost nothing written. Omarchy ships the launch as
`omarchy-launch-nautilus-cwd` — `nautilus --new-window "$(omarchy-cmd-terminal-cwd)"`
— parked on SUPER+ALT+SHIFT+F while the plain key opens `$HOME`, so
`hypr/bindings.lua` only had to swap which of the two sits on the key that gets
pressed. tmux is the one thing that command cannot answer, so `bin/files-here`
runs it with `bin/tmux-cwd`'s directory when there is one and Omarchy's own
answer otherwise. Omarchy's SUPER+ALT+SHIFT+F is left alone and now differs
from the plain key only inside tmux.

Four pieces, because none of what the keys need is reachable from where a
keybinding sits:

| Piece | Lane | Where |
|---|---|---|
| the bindings | `HOOKS` | `hypr/bindings.lua` |
| the launchers | `LINKS` | `bin/term-here`, `bin/files-here` → `~/.local/bin/` |
| the tmux pane on screen | `LINKS` | `bin/tmux-cwd` |
| the Nautilus location, and the pre-typed line | `LINKS` | `nautilus/term-here.py`, `shell/bashrc` |

**Why an extension.** Nautilus publishes its location nowhere a keybinding can
reach. Its D-Bus surface is `org.freedesktop.FileManager1` (`ShowItems`,
`ShowFolders` — all setters) plus `org.gtk.Actions`, whose window action states
carry navigation commands and no path; the window title is the folder's display
name, not a path. So the location has to come from inside the process.
`nautilus/term-here.py` keeps no menu items and exists only for the callbacks:
Nautilus rebuilds extension menus *eagerly*, on every selection change and
every navigation rather than when a context menu opens, which makes
`MenuProvider` a usable notification hook — and in Nautilus 50 the only one
left, since `LocationWidgetProvider` is gone from the 4.1 API. It records to
`$XDG_RUNTIME_DIR/omarchy-dotfiles/nautilus-location.json`, keyed by window
title, which is the one identifier both sides can see: the callbacks carry no
window handle, but `Gtk.Window.list_toplevels()` finds the active window from
in-process and its title is byte-identical to the `title` Hyprland reports.
Focus changes alone do not fire the callbacks, so without that key a second
window would answer with the first one's directory.

`nautilus-python` needs no `PACKAGES` entry — it is on Omarchy's own base list,
right below `nautilus`. Nautilus loads extensions at startup, so the first
install needs one `nautilus -q`.

**Why the tmux server has to be asked.** A pane's directory exists nowhere a
keybinding can read it either. `/proc` knows only the client's cwd, which is
where tmux was started and never changes; the server holds the pane's, and only
the server can be asked for it. The bridge from a Hyprland window to a tmux
pane is the client process: the server knows every client's pid and session, a
client's pid is a descendant of the terminal window's pid, and a session's
current pane is the one its clients are showing. So `bin/tmux-cwd` asks each
server for its clients and keeps the ones whose ancestry reaches the focused
window — walking *up* from each client rather than down from the window, since
there are a handful of clients and no reason to enumerate every process on the
machine.

Three details that are not obvious:

- **The client's session by id, not by name.** `display-message -t "$session_id"`
  resolves to that session's current window's active pane. A name would be
  matched as a pattern; `$0` cannot be anything but the session it is.
- **Not `display-message -c <client tty>`,** which looks like the more direct
  question and is not: `-c` picks which client the message is *displayed* to and
  leaves the format expanded against the most recently used client. On tmux
  3.7c, with two clients attached to two sessions, both ttys answered with the
  second session's pane. This was written that way first, and the two-client
  test is what caught it.
- **Every socket in the default directory,** so a server on `tmux -L name` is
  found as well as the plain one. A server on `-S /some/other/path` is out of
  reach and falls back to Omarchy's answer.

When one window pid holds several clients that disagree — kitty shares a single
pid across all of its windows, and so does `foot --server` — it refuses to
guess and the caller falls back to Omarchy's answer, wrong in a predictable way
rather than confidently wrong about which pane you are looking at. Clients on
one session always agree, which is the common case for two panes of the same
terminal.

`tmux` needs no `PACKAGES` entry either — also on Omarchy's base list — and on
a machine without it `bin/tmux-cwd` finds no socket directory to scan, so both
keys are stock.

Verified with `hl.dsp.exec_cmd`, which is what the binds run. From a foot
window whose tmux pane was in `~/projects/superspotmono`, SUPER+RETURN gave a
terminal there and SUPER+SHIFT+F a Nautilus window on the same folder; from a
foot window without tmux and from a Chromium window, both keys landed exactly
where `omarchy-cmd-terminal-cwd` said, unchanged. The resolver itself was
checked against a throwaway server on its own socket: it follows the visible
window, follows the active pane within it, follows a `cd` inside that pane, and
exits 1 for a window with no client, a pid that does not exist, and two clients
that disagree.

**Why the terminal types to itself.** bash takes no argument for "start with
this on the prompt": the only way to set the line is `READLINE_LINE`, and the
only way to reach `READLINE_LINE` is from inside a `bind -x` command — which
means a key has to be pressed. So `shell/bashrc` has the terminal press it.
`\e[5n` is a status request; the terminal answers `\e[0n` on the shell's own
*input*, exactly as if it had been typed, and readline dispatches it like any
other key sequence. The handler sets the line, puts the cursor at column 0, and
unbinds itself so a later status reply cannot overwrite a command you are
typing. The reply lands before the first prompt, while the tty is still echoing,
so it arrives on screen as a literal `^[[0n` — hence the `\e7` before the
request and `\e8\e[J` in the handler, which erase it and the prompt drawn under
it while leaving anything printed above alone.

The line reaches the new shell as an environment variable set *on the exec
inside the terminal*, not exported by `term-here`: `uwsm-app` starts the
terminal from the systemd user manager's environment, so anything exported
outside is dropped on the way.

**Bar workspaces.** Stock `omarchy.workspaces` renders one marker, on
`Hyprland.focusedWorkspace` — a single global value — so every bar on a
multi-monitor desk draws the identical row. The laptop bar claims the workspace
focused on the external monitor is the current one, and says nothing about the
workspace the laptop is actually showing. A bar surface exists per monitor, so
`omarchy-shell/workspaces/` answers for its own screen instead:

Three orthogonal channels carry three independent facts:

| Channel | Says | How |
|---|---|---|
| shape | what is on screen | filled square = this monitor is showing it; outline square = another monitor is; plain digit = not on screen anywhere |
| colour | where the keyboard is | accent = this monitor's workspace, and this monitor has focus |
| opacity | which monitor owns it | full = this monitor's; faint = another monitor's; faintest = does not exist yet |

Ownership is the third one because Hyprland binds a workspace to the output it
was created on, and that is what decides where pressing the number takes you —
worth saying on every bar, not just on the one that owns it. So on a desk where
1 and 4 live on the external monitor and 2, 3, 5, 6, 7 on the laptop, the laptop
bar shows 2/3/5/6/7 bright and 1/4 faint, and the external bar is its exact
complement. A glance at either says which workspaces live on that screen, which
one it is showing, which the others are showing, and which of them has the
keyboard.

The three opacity steps are named properties at the top of the file
(`ownOpacity`, `foreignOpacity`, `ownerlessOpacity`) — `foreignOpacity` is the
one worth tuning by eye. Foreign sits brighter than ownerless on purpose: a
workspace another screen is holding is more real than one that does not exist,
and the other way round reads as though an empty slot mattered more than a
screenful of windows.

On a single monitor it reduces to stock plus the accent — nothing is foreign,
so nothing is dimmed for ownership.

Nothing in the widget counts or names monitors, so a monitor plugged in later
needs no restart: the bar host instantiates a surface per `Quickshell.screens`
entry, and every lookup is a scan of Hyprland's own live monitor list. Verified
with `hyprctl output create headless` — the new bar came up with its own marker
and both existing bars grew a second outline marker for it, live.

The monitor comes from `Hyprland.monitorFor(QsWindow.window.screen)` —
`QsWindow.window` being the panel window the widget was instantiated into. If
that cannot be resolved (before Hyprland reports its outputs, or a screen it
does not know) the widget falls back to `Hyprland.focusedWorkspace`, which is
stock behaviour and the right thing to degrade to. Accent is `Color.accent`,
loaded from the theme's `colors.toml` and rebound on a theme switch;
deliberately not `Color.bar.active`, which is shell.toml's "modules calling
attention to themselves" colour (recording, alerts, updates) and red in most
themes.

**Why a clone.** The packaged widget under `$OMARCHY_PATH/shell/plugins` is
never to be edited, and a user plugin cannot shadow a built-in id —
`omarchy-plugin-catalog` does `unique_by(.id)` with built-ins first, so the
packaged one wins and ours would be ignored. `omarchy plugin clone
omarchy.workspaces` produces `alari.workspaces`, which is linked back into the
repo. `moduleName` inside the QML stays `omarchy.workspaces`, as the clone
leaves it, so the shell can route the widget's IPC through the manifest's
`clonedFrom`.

Two things this lane cannot do. The bar layout in
`~/.config/omarchy/shell.json` has to name `alari.workspaces`, and shell.json
is Omarchy-owned JSON with no include mechanism — so it stays drift, as it
already is for the clock and `omalink.phone`. `omarchy refresh shell` resets
it and the bar falls back to the packaged widget; put it back with
`omarchy-plugin-enable alari.workspaces`. And because the live directory is a
symlink into the repo, the shell's plugin watcher never sees writes through it:
editing the QML does not hot-reload, and `omarchy-shell shell rescanPlugins` is
not enough either. Run `omarchy restart shell`.

**XCompose.** Split across two files because the repo is public. The tracked
`xcompose/XCompose` holds the emoji include, the name/email/repo expansions,
the LAN prefixes, and the eight Estonian letters mapped to where they sit on an
Estonian keyboard relative to a US one. It ends with `include
"%H/.XCompose.local"` for anything private — that file is seeded from a
template and never tracked.

`~/.XCompose.local` **must exist**. A missing include is fatal — libxkbcommon
abandons the entire Compose file, so every expansion stops working, not just
the include. That is what the `SEEDS` lane is for, and why `doctor.sh` runs
`xkbcli compile-compose --test` against the live file: the failure is total and
otherwise completely silent.

Changes need `omarchy-restart-xcompose`, and running applications only pick
them up when they restart.

**Keyboard.** Caps Lock is Escape, and the freed Escape key is Compose — which
is what makes the XCompose file above reachable. Right Alt is a second Super.

Neither is a stock xkb option; they are defined in `xkb/symbols/custom` and
made selectable by `xkb/rules/evdev`, with `hypr/input.lua` naming them in
`kb_options`. The 3.x system had the same two options as
`custom:caps_esc_compose,custom:ralt_super`, but their definitions lived in
`/usr/share/X11/xkb` — root-owned, outside any dotfiles repo, and gone after a
reinstall. libxkbcommon searches `~/.config/xkb` ahead of the system tree, so
the same options now work per-user with no root and are tracked here.

Two consequences worth knowing:

- This drops Omarchy's default `compose:caps`, which would otherwise fight for
  the Caps key. `shift:both_capslock_cancel` is kept, and is what still gives a
  Caps Lock — both Shifts together.
- Right Alt leaves `Mod5`, so there is no AltGr. Fine on a `us` layout;
  reconsider before adding a layout that needs it.

Check a change without applying it, then reload:

```bash
xkbcli compile-keymap --layout us --options custom:caps_esc_compose,custom:ralt_super
```

**`~/.config/hypr/monitors.lua`** sets `local` variables consumed inside that
file, so it cannot be hooked out — it needs a real edit to the stock file. It is
per-machine anyway (scale differs per display), so it belongs in a
host-specific overlay rather than here.

**`shell.json`** is JSON with no include directive. Keep a `jq` patch in the
repo and apply it from `install.sh` rather than tracking the whole file.

**Messages.** `bin/msgs` answers one question — what arrived last — across
two channels at once. Mail comes over IMAP through `himalaya`, for scripting
rather than for sitting in, from two accounts: `gmail` (the default) and
`superhands` (work, hosted by Zone.ee). SMS comes off the phone through the
KDE Connect daemon. Both are read by default and merged by date, so "the last
message" means the last one that actually arrived, whichever carried it.

```bash
msgs                  # newest of anything: date, from, subject, body
msgs --subject        # just the subject
msgs --from --subject # sender and subject
msgs --text           # just the body
msgs --code           # the one-time code, or NOT FOUND
msgs --json           # the full structure
msgs -n 5             # five newest overall, merged across both channels
msgs --mail           # mail only
msgs --sms            # SMS only
msgs -a superhands    # one mail account (implies --mail)
msgs -m Junk          # a named mailbox instead of the inbox (mail only)
msgs -d <device-id>   # a specific phone (`kdeconnect-cli -a --id-only`)
msgs --no-cache       # re-fetch the bodies instead of reusing cached ones
```

An SMS has no subject, so `--subject` renders it as `(SMS)`. That is what
marks the channel when reading: mail output is untouched, and an SMS can never
be mistaken for a mail whose subject went missing.

```
Date:    2026-09-03 11:48 (36 minutes ago)
From:    +37253365468
Subject: (SMS)

Tellimus 26901000033841 on nüüd valmis ja ootab Teid…
```

Neither channel can take the other down. If the phone is not paired, not
reachable, or KDE Connect is not installed, the SMS half steps aside with a
warning on stderr and mail still answers; an unreachable mail account likewise
leaves SMS working. Asking for `--sms` by name turns those same conditions
into an error, because then there is nothing else to return.

SMS is read from the daemon with a single `activeConversations()` DBus call,
which answers from KDE Connect's own cache — single-digit milliseconds, no
round trip to the handset. One caveat is invisible in the output and worth
knowing: that call returns the newest message of each *thread*, not the newest
messages outright. At the default `-n 1` those are the same thing. At larger
`-n`, two of the newest messages sitting in one conversation show up as one
entry. Only received messages are listed, matching the mail half — that reads
an inbox, so "the last message" should not turn out to be something you sent.

Fields always print in the order date, from, subject, code, text, however the
flags were typed. Asking for exactly one prints the bare value so it pipes cleanly;
asking for more labels each line, since that is the reading case rather than
the scripting one. `--date` renders as `2026-08-28 09:48 (18 minutes ago)` —
the relative half being the point.

Only `--text`, `--code` and `--json` need a body, so the other fields answer
from the envelope alone: `msgs -n 3 --subject --mail` makes 2 `envelope list`
calls and **zero** `message read` calls, against 3 for `--text`. SMS is free
either way — the body arrives with the conversation list, so there is no
second call to skip.

Bodies are also where all the time went, and `msgs -n 10` took 18.6s until
three things changed. Measured, not guessed — the split came out of a
timestamped trace:

| | before | after |
|---|---|---|
| `msgs -n 10`, nothing cached | 18.6s | ~3s |
| `msgs -n 10` again | 18.6s | ~1.2s |
| `msgs -n 10 --subject` (no bodies) | 0.97s | 0.97s |

- **Four fetches at a time** instead of one. `message read` takes a single id
  and there is no batch form, so ten messages were ten processes and ten IMAP
  sessions, strictly in turn. Eight gmail messages take 6.0s serially, 1.6s
  at four in flight and 2.2s at eight — past four the server throttles and the
  extra connections cost more than they buy. `MSGS_JOBS` overrides it.
- **One jq pass over the envelopes** instead of five per message over the
  whole merged structure. That structure is 13 MB for ten messages, one
  newsletter being 1.9 MB of base64 on its own, and it was being re-parsed for
  every field of every message: about half the wall clock, none of it printed.
  Each message's body now comes out of its own file.
- **A cache**, in `${XDG_CACHE_HOME:-~/.cache}/msgs/bodies`, keyed by
  Message-ID. Delivered mail does not change, so the only question is how long
  to keep it: thirty days untouched and an entry is pruned, a hit is touched.
  Keying on the header rather than the per-mailbox id means the same mail
  reached through two accounts is fetched once, and moving a message between
  mailboxes does not orphan its body. `--no-cache` skips it both ways.
  Envelope listing is never cached — that is the half that has to be current,
  and it is already fast.

What remains is the network, and one thing worth knowing: an occasional single
`message read` stalls for ten seconds or more where its neighbours take 0.6s.
That is not new and not the parallelism — the same stall shows up in serial
runs — but it is now the whole of a slow run, and the cache means it is paid
once per message ever.

`--text` and `--code` tidy the body for reading: every line loses its leading
and trailing whitespace, runs of blank lines collapse to a single one, and
blank runs at the start and end go entirely. `--json` does not, so anything
parsing a body still gets exactly what the sender sent.

This is awk rather than `cat -s`, which does nothing on its own here: the
"blank" lines are not empty but full of spaces, so the strip has to happen
first, and `cat -s` cannot drop the runs at the very start and end.

`--code` extracts one-time codes, and lives in `bin/msg-code` — a separate
program so it can be tested against awkward text with no mailbox and no phone
involved (`msg-code --self-test`, 14 cases). It reads stdin and knows nothing
about either channel, so it also works on its own: `msgs --text | msg-code`.

Adding SMS mattered most here. One-time codes mostly arrive by text, not by
mail, so `--code` and the `SUPER + ALT + CTRL + M` binding only now reach
where the codes actually are:

```console
$ msgs --sms -n 5 --from --code
From: Apple
Code: 530627

From: AMAZON
Code: 279860
```

Two Hyprland bindings sit on top of all this:

| Key | What |
|---|---|
| `SUPER + ALT + M` | the newest message, mail or SMS, in a floating neovim buffer (`bin/msg-peek`) |
| `SUPER + ALT + CTRL + M` | its login code onto the clipboard, toast only (`bin/msg-otp`) |

Both act on *the newest message*, whichever channel it came from. That is the
intended behaviour rather than a limitation — you press the key straight after
asking a service for a code — but it does mean a newsletter arriving in the
same minute can shadow a code that came by SMS.

Two shapes for two jobs. Reading wants a window you can scroll and dismiss;
grabbing a code wants no window at all, because you are mid-login in another
app and a window would steal the focus you are about to type into. The code
path raises a "Fetching…" toast and *replaces* it in place with the result, so
the stack never holds two.

The reader opens before the fetch starts — IMAP takes a second or two, and a
window that appears only afterwards reads as a dropped keypress. Its window
rule lives beside its binding in `hypr/bindings.lua`, because it is not really
a window rule, it is half of the binding; `--app-id=msg-peek` is what ties
them together, private rather than the terminal's own id so the rule cannot
catch an ordinary terminal.

The message lands in neovim, not a pager — `msg-peek --nvim`, which the
binding passes and a bare `msg-peek` does not, so the script still works in a
terminal that has no editor config to speak of. It buys the keys you already
know for searching and yanking a code out of the body, and `ZZ` or `:wq` for
the way out. Two things it needs to be: a real file under `XDG_RUNTIME_DIR`
rather than a scratch buffer, since `ZZ` and `:wq` both *write* and would
otherwise error on the one key you reach for, and `NVIM_APPNAME=nvim-chad` set
in the script, since `nv` is a shell alias and Hyprland runs no shell. The file
is named `message.eml` so neovim reads the `Date:`/`From:`/`Subject:` block as
mail, and is deleted when the window closes.

Three things that turned out to matter, all found by screenshotting the actual
window rather than trusting it:

- **Opacity.** Omarchy tags every window `default-opacity`, which is right for
  a terminal you type in and wrong for one you read: the window behind shows
  through the body. Pinned to `1.0`.
- **`less -c`.** `foot-extra`'s terminfo carries no `smcup`, so without an
  alternate screen `less` paints inline and leaves a short message pinned to
  the *bottom* under a screenful of nothing. Still there for `msg-peek`
  without `--nvim`; neovim clears the window itself.
- **Whitespace.** HTML-to-text converters leave voids — the MongoDB code mail
  is mostly empty screen — and indent everything, so the text drifts
  rightwards. Tidying now lives in `msgs` itself rather than the window,
  so `--text` and `--code` get it too; see below.

Finding digits is easy; not finding the *wrong* digits is the job. Real mail is
full of street numbers, ZIP codes, copyright years and "expires in 10 minutes",
so candidates are ranked by distance to a word like *code* or *password* — in
**either** direction, because senders disagree about which comes first:

```
600338                              Your one-time verification code:
                                    474661
This code expires in 30 minutes.
```

Two traps found by running it against live mail, both now regression-tested.
Hyphenated keywords: the chunked pattern `ABCD-1234` happily matched the words
*one-time* and *single-use*, which sit at distance zero from the very keyword
that found them, so chunked candidates must contain a digit. And CSS: HTML mail
drags whole stylesheets along, and a stylesheet that themes a `<code>` element
puts `#333333` right beside the keyword — which made a sign-in *notification*
with no code in it report one. Declaration-block lines are dropped before
anything is matched.

To extend it, add to `PATTERNS` or `KEYWORDS` at the top of `bin/msg-code`;
`PATTERNS` is ordered, earlier entries winning ties.

With no `-a` it queries every account and merges by date, so "the last mail I
got" means what it says. `-n` counts *after* merging. Without `-m` no
`--mailbox` is passed at all, letting each account resolve its own
`mailbox.alias.inbox` — which is what lets Gmail's `INBOX` and Zone's `Inbox`
coexist without the wrapper hardcoding either.

Merged output is de-duplicated by `Message-ID`, because one message really can
live in two accounts: mail to `alari@superhands.ee` lands on Zone and Gmail
POP-fetches a copy. The surviving entry lists every account holding it in
`accounts`, while `account` is the one it was read from. An account that fails
to list is reported on stderr and skipped rather than killing the run — stdout
stays valid JSON — and the exit is non-zero only if nothing could be reached.

One wrinkle worth knowing. Gmail POP-fetches the superhands.ee mailboxes, and
whether it *deletes them from Zone as it goes* is a per-account tick-box in
Gmail ("Leave a copy of retrieved message on the server"). It is on for
`alari@superhands.ee`, so that mail stays on Zone and is readable the moment it
lands — before Gmail even fetches it, which is the whole point. It is still off
for `info@`, `admin@` and `development@`, so those are drained and only ever
readable through the `gmail` account:

```bash
himalaya envelope search "to info@superhands.ee"
```

That history is visible in the UID counter: before the change Zone's Inbox held
0 messages against a UIDNEXT of 23482, i.e. ~23k messages had passed through
and been deleted. Do not read an empty Inbox as a broken setup.

Zone publishes no autoconfig — neither the Thunderbird ISPDB nor
`autoconfig.superhands.ee` has an entry — so its settings were read off the
server: `imap.zone.eu:993` presents a cert for exactly that name and advertises
`AUTH=PLAIN` with `SASL-IR`, so it takes the same plain-SASL-over-TLS shape as
Gmail. `mail.zone.eu` and `mail.superhands.ee` do not resolve.

Output is a JSON array of `{ envelope, message }`. The envelope half has a
published schema — `himalaya json-schema <dir>` dumps the JSON shape of every
command — so filter on that. The message half is passed through verbatim,
because himalaya documents it only as "a minimal header block followed by a
per-part walk" with no fixed schema; reshaping it here would be a guess that
breaks on the next release. Reading never marks anything seen: `himalaya
message read` sets that flag only when passed `--seen`, which the wrapper
never does.

`--json` tags every entry with its `source`, `"mail"` or `"sms"`. An SMS also
carries `sms` (body, addresses, `date_ms`, thread and message ids) and a
*synthesised* `envelope` — date from `date_ms`, from from the sender, subject
the literal `(SMS)`, id `sms-<uid>`. That envelope is what lets one sort, one
de-duplication pass and one renderer serve both channels; `sms.addresses`
keeps the untouched participant list, and `sms.date_ms` the millisecond
precision `envelope.date` rounds off.

The sender is `addresses[0]`, not the whole array. A person-to-person thread
comes back as `[sender, your own number, sender]`, so joining it would repeat
the sender and print your own number as though it had texted you.

The rest of this applies to mail. The shape `.message` actually has in 2.1,
observed against a live inbox rather
than promised anywhere: `text_body` and `html_body` are arrays of *indices
into* `parts`, and a part's content sits under a single-key tag naming its
variant — `.body.Text` or `.body.Html`.

Those two arrays are **not** a text/html split, which is the trap. An
HTML-only mail lists the *same* index in both, and that part is `{"Html": …}`
— so `text_body[0]` can name a part with no `.body.Text` at all. Select on the
variant the part carries, never on which array named it:

```bash
# readable body of the newest message, whichever variant it has
msgs | jq -r '.[0].message as $m
  | ($m.text_body + $m.html_body) as $c
  | first($c[] | select($m.parts[.].body | has("Text")))
    // first($c[] | select($m.parts[.].body | has("Html")))
  | $m.parts[.].body | (.Text // .Html)'

# who has been mailing most, out of the last 20
msgs -n 20 | jq -r '.[].envelope.from[0].email' | sort | uniq -c | sort -rn
```

`--text` and `--code` do that selection for you, and run an HTML part through
a small awk pass first — tags out, entities decoded, `<br>` and block tags to
line breaks, and anchors keeping their target so "click here" survives as
something you can act on. It is a reading aid, not a browser: senders' layout
tables come out as prose, and an unrecognised `&entity;` is left as written
rather than dropped. `--json` is never touched — anything parsing a body gets
exactly the bytes the sender sent.

Treat those paths as a convention rather than a contract — pin himalaya, or
check the shape, if something depends on it.

Credentials are a Gmail **app password**, which requires 2-Step Verification on
the account, stored in gnome-keyring:

```bash
secret-tool store --label="Gmail app password (himalaya)" \
  service himalaya account <your-address>
```

`himalaya/config.toml` fetches it with a `cmd`, never a `raw` — the repo is
public and nothing secret may be tracked. `doctor.sh` checks the binary, the
config and the credential separately, because each fails differently; it tests
only that the credential *exists*, never printing it and never logging in.
`himalaya account check` does the live login when you want it.

OAuth2 against the Gmail REST API is the other option, and himalaya ships it
(`+gmail`, with `labels`, `threads`, `history` and `settings` subcommands that
IMAP cannot express). It needs a Google Cloud OAuth client, so it is not set up
here; the config is structured so a `[accounts.gmail.gmail]` block can be added
beside the IMAP one rather than replacing it.

## History

The `main` branch holds the previous Omarchy 3.x-era snapshot: whole-file
copies of hypr `.conf` files, waybar, and mako, none of which 4.x uses.

Everything worth carrying is now ported: the bash, tmux, nvim, and nvim-chad
configs, hypr-nav, and XCompose. Nothing is left waiting on `main`.

`starship.toml` needs no port: `main`'s copy is byte-identical to 4.x stock.
It was only ever a snapshot of the default.

The `hypr-nav` source moved from `~/.local/src/hypr-nav` (where `main` tracked
it as a live path) into `hypr-nav/` in the repo. Nothing needs to live under
`~/.local/src` — the repo *is* the source directory, and only the built binary
**Claude Code.** A ding when Claude Code finishes a turn, and when it stops to
ask you something: a question (`AskUserQuestion`), a plan to approve
(`ExitPlanMode`), or a permission prompt. `claude/hooks.json` says when, as
`Stop`, `PreToolUse` and `Notification` hooks; `claude/ding` plays
sound-theme-freedesktop's `complete.oga` through `pw-play`, detached, so
Claude never waits on it. Change the sound there.

The permission-prompt ding comes about six seconds late: Claude Code only
raises that notification once a prompt has sat unanswered that long, so one
you answer at once stays quiet. `idle_prompt` is deliberately not matched -- it
fires a minute after a turn ends, which would ding a second time for a turn
that already dinged.

Claude Code watches its settings file, so `install.sh` takes effect in running
sessions too, without a restart. Check them with `/hooks`.

is installed out of it.
