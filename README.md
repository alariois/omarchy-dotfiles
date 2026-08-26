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
