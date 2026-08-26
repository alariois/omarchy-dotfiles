-- Smart navigation: vim splits → tmux panes → Hyprland windows
-- Works with the hypr-nav binary for seamless Alt+hjkl navigation

local function navigate(dir, vim_dir)
  local cur_win = vim.api.nvim_get_current_win()
  vim.cmd("wincmd " .. vim_dir)
  if vim.api.nvim_get_current_win() == cur_win then
    -- At the edge of vim splits, hand off to tmux/hyprland
    vim.fn.system("hypr-nav " .. dir .. " --from-vim")
  end
end

return {
  {
    dir = "hypr-nav",
    name = "hypr-nav",
    virtual = true,
    keys = {
      { "<M-h>", function() navigate("l", "h") end, desc = "Navigate left",  mode = { "n", "t" } },
      { "<M-j>", function() navigate("d", "j") end, desc = "Navigate down",  mode = { "n", "t" } },
      { "<M-k>", function() navigate("u", "k") end, desc = "Navigate up",    mode = { "n", "t" } },
      { "<M-l>", function() navigate("r", "l") end, desc = "Navigate right", mode = { "n", "t" } },
    },
  },
}
