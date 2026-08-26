-- <leader>fa -- find files including hidden and gitignored ones.
--
-- NOTE: ported verbatim from the 3.x-era config. Omarchy 4's LazyVim (install
-- version 8) has no telescope in its lockfile -- it picks with snacks -- so
-- this spec pulls telescope in as a new plugin just for this one binding.
-- To use the picker already in the stack instead, replace the whole return
-- with:
--
--   return {
--     "folke/snacks.nvim",
--     keys = {
--       { "<leader>fa", function()
--           Snacks.picker.files({ hidden = true, ignored = true })
--         end, desc = "Find All Files" },
--     },
--   }

return {
  "nvim-telescope/telescope.nvim",
  keys = {
    {
      "<leader>fa",
      function()
        require("telescope.builtin").find_files({ hidden = true, no_ignore = true })
      end,
      desc = "Find All Files",
    },
  },
}
