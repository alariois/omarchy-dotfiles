# omarchy-dotfiles

Personal [Omarchy](https://omarchy.org/) configuration files managed with a bare git repo.

## How it works

The `dot` alias is git with two flags: `--git-dir=$HOME/.dotfiles` (repo data) and `--work-tree=$HOME` (working tree). Config files stay in their real locations under `~/.config/` — no symlinks needed. The `.gitignore` ignores everything by default so only explicitly added files are tracked.

## Setup on a fresh machine

```bash
# 1. Clone the bare repo
git clone --bare git@github.com:alariois/omarchy-dotfiles.git ~/.dotfiles

# 2. Add the dot alias to .bashrc
echo "alias dot='git --git-dir=\$HOME/.dotfiles --work-tree=\$HOME'" >> ~/.bashrc
source ~/.bashrc

# 3. Configure git to hide untracked files
dot config status.showUntrackedFiles no

# 4. Checkout the config files
dot checkout

# If checkout conflicts with existing files, back them up first:
# dot checkout 2>&1 | grep "^\t" | awk '{print $1}' | xargs -I{} mv {} {}.bak
# dot checkout
```

## Day-to-day usage

```bash
dot status                  # see what's changed
dot add ~/.config/hypr/bindings.conf
dot commit -m "update hyprland bindings"
dot push
```

## What's tracked

- `~/.config/hypr/` — Hyprland (keybindings, monitors, appearance, idle, lock)
- `~/.config/tmux/` — tmux
- `~/.config/waybar/` — Waybar (bar layout and styling)
- `~/.config/ghostty/` — Ghostty terminal
- `~/.config/mako/` — Mako notifications
- `~/.config/starship.toml` — Starship prompt
- `~/.bashrc` — Shell config

Stock omarchy files (shaders, themes, samples) are excluded since they're restored by `omarchy-theme-set` / `omarchy-refresh-*`.
