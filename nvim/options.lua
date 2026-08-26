-- Personal Neovim options.
--
-- Hooked into ~/.config/nvim/lua/config/options.lua by setup/install.sh.
-- Omarchy owns that file (its migrations `mv` a temp file over it to inject
-- config.remote_clipboard), so our block lives at the end of it and only
-- points here. The block is appended last, which is what makes these win
-- over the stock assignments above it.

-- Stock Omarchy sets this to false; we want relative numbers.
vim.opt.relativenumber = true

-- Trust per-project .nvim.lua / .exrc files.
vim.o.exrc = true
