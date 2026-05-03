#!/usr/bin/env bash
#
# Bootstrap dotfiles on a new system.
# Run after checking out the bare repo:
#   git clone --bare <repo> ~/.dotfiles
#   git --git-dir=$HOME/.dotfiles --work-tree=$HOME checkout
#   ~/setup/install.sh
#
set -euo pipefail

echo "=== Dotfiles setup ==="

# Build and install hypr-nav
if [[ -f "$HOME/.local/src/hypr-nav/Makefile" ]]; then
    echo "Building hypr-nav..."
    make -C "$HOME/.local/src/hypr-nav" clean install
    echo "hypr-nav installed to ~/.local/bin/hypr-nav"
else
    echo "SKIP: hypr-nav source not found"
fi

# Bootstrap nvim-chad plugins (Lazy.nvim self-installs)
if [[ -d "$HOME/.config/nvim-chad" ]]; then
    echo "Bootstrapping nvim-chad plugins..."
    NVIM_APPNAME='nvim-chad' nvim --headless "+Lazy! sync" +qa 2>/dev/null || true
    echo "nvim-chad plugins installed"
else
    echo "SKIP: nvim-chad config not found"
fi

echo "=== Done ==="
