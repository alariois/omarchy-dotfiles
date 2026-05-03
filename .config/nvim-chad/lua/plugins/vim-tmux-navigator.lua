return {
  {
    "christoomey/vim-tmux-navigator",
    name = "vimtmuxnavigator",
    -- ensure defaults are turned off before load
    init = function()
      vim.g.tmux_navigator_no_mappings        = 1
      vim.g.tmux_navigator_disable_when_zoomed = 1
      vim.g.tmux_navigator_no_wrap             = 0
    end,

    -- load when any of these commands are run
    cmd = {
      "TmuxNavigateLeft",
      "TmuxNavigateDown",
      "TmuxNavigateUp",
      "TmuxNavigateRight",
      "TmuxNavigatePrevious",
    },

    -- *and/or* load when any of these key-presses happen
    keys = {
      { "<A-h>", "<cmd>TmuxNavigateLeft<cr>",     silent = true, desc = "tmux ←" },
      { "<A-j>", "<cmd>TmuxNavigateDown<cr>",     silent = true, desc = "tmux ↓" },
      { "<A-k>", "<cmd>TmuxNavigateUp<cr>",       silent = true, desc = "tmux ↑" },
      { "<A-l>", "<cmd>TmuxNavigateRight<cr>",    silent = true, desc = "tmux →" },
      { "<A-\\>", "<cmd>TmuxNavigatePrevious<cr>", silent = true, desc = "tmux ⤾" },
    },

    -- any additional one-time setup (if you have none, you can drop this)
    config = function()
    end,
  },
}

