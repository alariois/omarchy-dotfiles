# Working state

Scratch handoff notes, so work can resume after a reboot. Not part of the
config — delete it once the open items below are closed.

Last updated: 2026-08-26. Branch `quattro`, at `e4e56bb`.

## Where things stand

The 3.x→4.x port is **done, merged, installed, and verified live.** `quattro`
carries three commits on top of the delta-model groundwork:

| Commit | What |
|---|---|
| `cb79348` | tmux + nvim + nvim-chad configs; activated the `LINKS` symlink lane |
| `8020e1f` | hypr-nav; added the `BUILDS` lane for compiled source |
| `e4e56bb` | the `nv` alias, completing the nvim-chad port |

Verified on this machine after install:

- All four managed blocks present, three symlinks resolving into the repo,
  `~/.local/bin/hypr-nav` built and on PATH.
- All four `Navigate` bindings live in the running Hyprland session.
  (`hyprctl binds` shows dispatchers as `__lua` and never prints the command
  string, so grep for `description: Navigate` — grepping for `hypr-nav`
  produces a false negative.)
- hypr-nav: 33/33 unit tests, 14/14 integration tests.

Nothing is pending to make the current config work. `setup/doctor.sh` is the
authority — run it first after reboot and trust it over these notes.

## Open items

**1. `quattro` is not pushed.** It exists only in the local checkout. Only
`worktree-port-nvim-tmux` (the same commits) is on origin. Push `quattro` so a
disk failure is not a total loss.

**2. Port `.XCompose`.** The one config still only on `main`. Omarchy ships no
`.XCompose`, so it is a clean `LINKS` candidate — a single row in
`setup/targets.sh`. The live `~/.XCompose` has already lost the
Estonian-letter bindings (`<Multi_key> <semicolon>` → ö, and the rest) and the
identification expansions; `git show main:.XCompose` still has them. Note the
live file also fixes the include path to `/usr/share/omarchy/default/xcompose`,
which `main`'s version has wrong — keep the live path when porting.

**3. Decide on `nvim/plugins/telescope-find-all.lua`.** Ported verbatim, but
telescope is not in this stack any more — Omarchy 4's LazyVim (install version
8) picks with snacks and has no telescope in its lockfile. As written, the spec
pulls telescope in as a new plugin for the single `<leader>fa` binding. The
snacks.picker replacement sits commented at the top of that file, one edit
away. Either finish the swap or delete the file; leaving it is the only
undecided thing in the port.

**4. Four pre-existing drifts** that `doctor.sh` reports. All predate this
work; none is a regression. Each needs a port-or-revert decision:

| File | Drift | Note |
|---|---|---|
| `~/.config/git/config` | `[user]` name + email | trivial `HOOKS` row, or leave it machine-local |
| `~/.config/hypr/hyprland.lua` | Slack → workspace 5 window rule | belongs in a repo file, hooked like `hypr/bindings.lua` |
| `~/.config/hypr/monitors.lua` | gdk/monitor scale 2/auto → 1/1 | **cannot** be hooked: sets `local`s consumed in that file. Per-machine; needs a host overlay |
| `~/.config/omarchy/shell.json` | `birthYear`, `lifeExpectancy` | JSON, no include directive; plan is a `jq` patch applied from `install.sh` |

## Resuming

The git worktree this was built in (`.claude/worktrees/port-nvim-tmux`) is
disposable and may be gone. Everything is on `quattro` in the main checkout —
start there, not in a worktree.

```bash
cd ~/projects/omarchy-dotfiles
git log --oneline -4
setup/doctor.sh          # read-only; the source of truth for live state
```

Two traps worth remembering:

- **Always run `setup/install.sh` from the real checkout**, never from a
  worktree. It resolves its own location and bakes absolute paths into the
  blocks it writes, so running it from a worktree points `~/.bashrc` at a
  directory that later disappears.
- `git worktree add` defaults to branching from `origin/main`, which is the
  stale 3.x snapshot. Reset onto `quattro` after creating one.

Full design rationale, the three lanes, and the per-config notes are in
`README.md`.
