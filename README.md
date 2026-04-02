# omarchy-dotfiles

Personal [Omarchy](https://omarchy.org/) configuration files.

## Usage

```bash
# Clone on a fresh machine
git clone --bare git@github.com:alariois/omarchy-dotfiles.git ~/.dotfiles
alias dot='git --git-dir=$HOME/.dotfiles --work-tree=$HOME'
dot config status.showUntrackedFiles no
dot checkout

# If checkout conflicts with existing files, back them up first:
# dot checkout 2>&1 | grep "^\t" | awk '{print $1}' | xargs -I{} mv {} {}.bak
# dot checkout
```

## Tracking new files

```bash
dot add ~/.config/hypr/bindings.conf
dot commit -m "update hyprland bindings"
dot push
```
