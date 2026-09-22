-- In-buffer markdown rendering: styled headings, tables, code blocks,
-- checkboxes, callouts and bullets. Pure Lua, no terminal graphics protocol
-- required, so it works in foot. Manages `conceallevel` itself.
return {
    "MeanderingProgrammer/render-markdown.nvim",
    dependencies = {
        "nvim-treesitter/nvim-treesitter",
        "echasnovski/mini.icons",
    },
    ft = { "markdown" },
    opts = {
        -- Reveal the raw markup on the line the cursor is on, so the text
        -- stays editable exactly where you are working.
        anti_conceal = { enabled = true },
    },
    keys = {
        {
            "<leader>mr",
            "<cmd>RenderMarkdown toggle<CR>",
            ft = "markdown",
            desc = "Toggle markdown rendering",
        },
    },
}
