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
configs. These are left stock in place and get one appended managed block:

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
hypr/input.lua                            keyboard remapping and key repeat (hooked)
hypr/looknfeel.lua                        gaps and corner rounding (hooked)
foot/foot.ini                             terminal font (hooked, `ini` style)
xkb/                                      custom xkb options behind it (linked)
nvim/plugins/*.lua                        added LazyVim plugin specs (linked)
nvim-chad/                                standalone nvim config (linked wholesale)
xcompose/XCompose                         compose-key expansions (linked)
xcompose/XCompose.local.seed              template for the private half (seeded)
hypr-nav/                                 C source for the hypr-nav binary (built)
himalaya/config.toml                      Gmail over IMAP for scripting (linked)
bin/mail-last                             newest message(s), as text or JSON (linked)
bin/mail-code                             one-time code extraction (linked)
bin/mail-peek                             newest mail in a floating window (linked)
bin/mail-otp                              login code to clipboard, via toast (linked)
setup/targets.sh                          the delta table -- single source of truth
setup/lib.sh                              freshness checks shared by the two below
setup/install.sh                          assert every block, link, build, and hook
setup/doctor.sh                           report state and unmanaged drift
hooks/post-update.d/reapply-dotfiles.hook re-assert blocks after `omarchy update`
```

## Usage

```bash
setup/install.sh      # wire the repo into the live system; safe to re-run
setup/doctor.sh       # what's hooked, what's linked, what drifted from stock
```

### On a fresh Omarchy

`setup/install.sh` reapplies everything the repo owns: managed blocks, symlinks,
the machine-local seed, the compiled `hypr-nav` binary, the no-ligature font,
the Omarchy post-update hook, and a Hyprland reload to make it all live.

Three things it deliberately does not do, because it cannot:

1. **`sudo pacman -S himalaya`.** `install.sh` has no sudo anywhere and runs
   unattended from the post-update hook, where a password prompt would hang an
   `omarchy update`. It warns and names the package instead. This is the only
   package missing from a stock Omarchy — `jq`, `less`, `wl-clipboard` and
   `xdg-terminal-exec` are all on Omarchy's own base list, `gawk` comes with
   Arch's `base`, and `make`/`gcc` come with `base-devel`.
2. **The two mail passwords**, which belong in the keyring and nowhere else:

   ```bash
   secret-tool store --label="Gmail app password (himalaya)" \
     service himalaya account <gmail-address>
   secret-tool store --label="Zone mail (himalaya)" \
     service himalaya account <work-address>
   ```

3. **Gmail's "Leave a copy of retrieved message on the server"**, a per-account
   tick-box in Gmail's own settings. Without it Gmail drains the Zone mailbox
   and the `superhands` account reads empty.

`setup/doctor.sh` reports the state of all three, so the fastest way to find
out what a new machine still needs is to run it.

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

**Mail.** `himalaya` reads mail over IMAP, for scripting rather than for
sitting in. Two accounts: `gmail` (the default) and `superhands` (work, hosted
by Zone.ee). `bin/mail-last` wraps it into the one thing wanted most often:

```bash
mail-last                  # newest across every account: date, from, subject, body
mail-last --subject        # just the subject
mail-last --from --subject # sender and subject
mail-last --text           # just the body
mail-last --code           # the one-time code, or NOT FOUND
mail-last --json           # the full structure
mail-last -n 5             # five newest overall, merged
mail-last -a superhands    # one account only
mail-last -m Junk          # a named mailbox instead of the inbox
```

Fields always print in the order date, from, subject, code, text, however the
flags were typed. Asking for exactly one prints the bare value so it pipes cleanly;
asking for more labels each line, since that is the reading case rather than
the scripting one. `--date` renders as `2026-08-28 09:48 (18 minutes ago)` —
the relative half being the point.

Only `--text`, `--code` and `--json` need a body, so the other fields answer
from the envelope alone: `mail-last -n 3 --subject` makes 2 `envelope list`
calls and **zero** `message read` calls, against 3 for `--text`.

`--text` and `--code` tidy the body for reading: every line loses its leading
and trailing whitespace, runs of blank lines collapse to a single one, and
blank runs at the start and end go entirely. `--json` does not, so anything
parsing a body still gets exactly what the sender sent.

This is awk rather than `cat -s`, which does nothing on its own here: the
"blank" lines are not empty but full of spaces, so the strip has to happen
first, and `cat -s` cannot drop the runs at the very start and end.

`--code` extracts one-time codes, and lives in `bin/mail-code` — a separate
program so it can be tested against awkward mail with no mailbox involved
(`mail-code --self-test`, 14 cases). It also works on its own: `mail-last
--text | mail-code`.

Two Hyprland bindings sit on top of all this:

| Key | What |
|---|---|
| `SUPER + ALT + M` | the newest message in a floating window (`bin/mail-peek`) |
| `SUPER + ALT + CTRL + M` | its login code onto the clipboard, toast only (`bin/mail-otp`) |

Two shapes for two jobs. Reading wants a window you can scroll and dismiss;
grabbing a code wants no window at all, because you are mid-login in another
app and a window would steal the focus you are about to type into. The code
path raises a "Fetching…" toast and *replaces* it in place with the result, so
the stack never holds two.

The reader opens before the fetch starts — IMAP takes a second or two, and a
window that appears only afterwards reads as a dropped keypress. Its window
rule lives beside its binding in `hypr/bindings.lua`, because it is not really
a window rule, it is half of the binding; `--app-id=mail-peek` is what ties
them together, private rather than the terminal's own id so the rule cannot
catch an ordinary terminal.

Three things that turned out to matter, all found by screenshotting the actual
window rather than trusting it:

- **Opacity.** Omarchy tags every window `default-opacity`, which is right for
  a terminal you type in and wrong for one you read: the window behind shows
  through the body. Pinned to `1.0`.
- **`less -c`.** `foot-extra`'s terminfo carries no `smcup`, so without an
  alternate screen `less` paints inline and leaves a short message pinned to
  the *bottom* under a screenful of nothing.
- **Whitespace.** HTML-to-text converters leave voids — the MongoDB code mail
  is mostly empty screen — and indent everything, so the text drifts
  rightwards. Tidying now lives in `mail-last` itself rather than the window,
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

To extend it, add to `PATTERNS` or `KEYWORDS` at the top of `bin/mail-code`;
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

The shape `.message` actually has in 2.1, observed against a live inbox rather
than promised anywhere: `text_body` and `html_body` are arrays of *indices
into* `parts`, and a part's content sits at `.body.Text`. So:

```bash
# plain-text body of the newest message
mail-last | jq -r '.[0].message as $m | $m.parts[$m.text_body[0]].body.Text'

# who has been mailing most, out of the last 20
mail-last -n 20 | jq -r '.[].envelope.from[0].email' | sort | uniq -c | sort -rn
```

Treat the `.body.Text` path as a convention rather than a contract — pin
himalaya, or check the shape, if something depends on it.

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
is installed out of it.
