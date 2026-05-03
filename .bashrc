# If not running interactively, don't do anything (leave this at the top of this file)
[[ $- != *i* ]] && return

# All the default Omarchy aliases and functions
# (don't mess with these directly, just overwrite them here!)
source ~/.local/share/omarchy/default/bash/rc

# Add your own exports, aliases, and functions here.
#
# Make an alias for invoking commands you use constantly
# alias p='python'

. "$HOME/.local/share/../bin/env"

set -o vi

alias dot='git --git-dir=$HOME/.dotfiles --work-tree=$HOME'

source /usr/share/nvm/init-nvm.sh

alias nv="NVIM_APPNAME='nvim-chad' nvim"
