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
for each.

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

## Layout

```
shell/bashrc                              bash config (hooked into ~/.bashrc)
tmux/tmux.conf                            tmux config (hooked)
nvim/options.lua                          nvim options (hooked into Omarchy's LazyVim)
nvim/plugins/*.lua                        added LazyVim plugin specs (linked)
nvim-chad/                                standalone nvim config (linked wholesale)
setup/targets.sh                          the delta table -- single source of truth
setup/install.sh                          assert every block, link, and hook (idempotent)
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

1. Put the configuration in a repo file (e.g. `omarchy/hypr/personal.lua`).
2. Add one row to `setup/targets.sh` — to `HOOKS` if Omarchy owns the live
   file, to `LINKS` if it does not.
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
Launch it with `NVIM_APPNAME=nvim-chad nvim`.

**tmux.** The only surviving delta is `unbind k`. The 3.x-era snapshot on `main`
also carried extended keys, `escape-time`, and a copy-mode status indicator —
4.x stock now ships all three verbatim, so they stopped being deltas. That is
the model paying for itself: a whole-file copy would still be "carrying" them
as a permanent merge conflict against upstream.

**`~/.config/hypr/monitors.lua`** sets `local` variables consumed inside that
file, so it cannot be hooked out — it needs a real edit to the stock file. It is
per-machine anyway (scale differs per display), so it belongs in a
host-specific overlay rather than here.

**`shell.json`** is JSON with no include directive. Keep a `jq` patch in the
repo and apply it from `install.sh` rather than tracking the whole file.

## History

The `main` branch holds the previous Omarchy 3.x-era snapshot: whole-file
copies of hypr `.conf` files, waybar, and mako, none of which 4.x uses.

Ported onto this branch so far: the bash, tmux, nvim, and nvim-chad configs.
Still only on `main` and worth porting:

- **`hypr-nav`** — the C source at `.local/src/hypr-nav`. The nvim plugin spec
  is ported (`nvim/plugins/hypr-nav.lua`) but the binary is not built or
  installed here, so the hand-off at a split edge is currently a silent no-op.
- **`.XCompose`** — Omarchy ships no `.XCompose`, so this is a clean `LINKS`
  candidate. The live file has already lost the Estonian-letter bindings and
  the identification expansions; `main` still has them.

`starship.toml` needs no port: `main`'s copy is byte-identical to 4.x stock.
It was only ever a snapshot of the default.
