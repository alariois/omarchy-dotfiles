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

So file ownership decides the mechanism:

**Files Omarchy owns** (`~/.bashrc`, `~/.config/hypr/*.lua`, `shell.json`,
terminal configs) are left stock in place. We append one managed block:

```bash
# >>> omarchy-dotfiles >>>
source "/home/you/projects/omarchy-dotfiles/shell/bashrc"
# <<< omarchy-dotfiles <<<
```

Our real configuration lives at the far end of that include, inside this repo.
A migration can clobber the block — it can never touch our config. And
`hooks/post-update.d/reapply-dotfiles.hook` re-asserts every block after each
`omarchy update`, so the clobber self-heals.

**Files Omarchy never writes** (nvim, tmux, custom themes, `~/.local/bin`)
should be symlinked out of this repo instead — no drift is possible when the
live file *is* the repo file. Nothing uses this lane yet.

Why this beats snapshotting whole files: upstream keeps improving its defaults
via migrations. Store the whole file and every upgrade is a conflict against
your own repo, and you eventually end up carrying config for software that no
longer exists. Store only the delta and an upgrade is a no-op for you.

## Layout

```
shell/bashrc                              our bash config (the delta)
setup/targets.sh                          the delta table -- single source of truth
setup/install.sh                          assert every block + hook symlink (idempotent)
setup/doctor.sh                           report block state and unmanaged drift
hooks/post-update.d/reapply-dotfiles.hook re-assert blocks after `omarchy update`
```

## Usage

```bash
setup/install.sh      # wire the repo into the live system; safe to re-run
setup/doctor.sh       # what's hooked, what's missing, what drifted from stock
```

`doctor.sh`'s third section is the useful one: it diffs every Omarchy-owned
config against the shipped stock template *with our managed blocks stripped
out*, so anything it reports is a local edit this repo is not capturing. Port
it into the repo as a delta, or revert it with
`omarchy refresh config <path>`.

## Adding a delta

1. Put the configuration in a repo file (e.g. `omarchy/hypr/personal.lua`).
2. Add one row to `setup/targets.sh` naming the Omarchy file to hook it into.
3. Run `setup/install.sh`.

Two things do not fit the include model and need noting when they come up:

- **`~/.config/hypr/monitors.lua`** sets `local` variables consumed inside that
  file, so it cannot be hooked out — it needs a real edit to the stock file.
  It is per-machine anyway (scale differs per display), so it belongs in a
  host-specific overlay rather than here.
- **`shell.json`** is JSON with no include directive. Keep a `jq` patch in the
  repo and apply it from `install.sh` rather than tracking the whole file.

## History

The `main` branch holds the previous Omarchy 3.x-era snapshot: whole-file
copies of hypr `.conf` files, waybar, and mako, none of which 4.x uses, plus
the nvim configs, tmux config, and the `hypr-nav` C source. Those last three
are worth porting onto this branch; they are reachable on `main`.
