return {
  'mrcjkb/rustaceanvim',
  appendversion = '^5', -- Recommended
  lazy = false, -- This plugin is already lazy
  init = function()
    vim.g.rustaceanvim = {
      server = {
        -- Wait 500ms after last keystroke before sending buffer to rust-analyzer
        -- Prevents analysis of half-typed code
        flags = {
          debounce_text_changes = 500,
        },
      },
    }
  end,
}
