return {
    "nvim-treesitter/nvim-treesitter-textobjects",
    branch = "main",
    dependencies = {
        "nvim-treesitter/nvim-treesitter",
    },
    config = function()
        require("nvim-treesitter-textobjects").setup({
            select = {
                lookahead = true,
                selection_modes = {
                    ["@parameter.outer"] = "v",
                    ["@function.outer"] = "V",
                    ["@class.outer"] = "<c-v>",
                },
                include_surrounding_whitespace = true,
            },
        })

        local select = require("nvim-treesitter-textobjects.select")
        local swap = require("nvim-treesitter-textobjects.swap")

        -- Select keymaps
        vim.keymap.set({ "x", "o" }, "af", function()
            select.select_textobject("@function.outer", "textobjects")
        end, { desc = "Select outer function" })
        vim.keymap.set({ "x", "o" }, "if", function()
            select.select_textobject("@function.inner", "textobjects")
        end, { desc = "Select inner function" })
        vim.keymap.set({ "x", "o" }, "ac", function()
            select.select_textobject("@class.outer", "textobjects")
        end, { desc = "Select outer class" })
        vim.keymap.set({ "x", "o" }, "ic", function()
            select.select_textobject("@class.inner", "textobjects")
        end, { desc = "Select inner class" })
        vim.keymap.set({ "x", "o" }, "ao", function()
            select.select_textobject("@comment.outer", "textobjects")
        end, { desc = "Select outer comment" })
        vim.keymap.set({ "x", "o" }, "as", function()
            select.select_textobject("@local.scope", "locals")
        end, { desc = "Select language scope" })

        -- Swap keymaps
        vim.keymap.set("n", "<leader>sn", function()
            swap.swap_next("@parameter.inner")
        end, { desc = "Swap with next parameter" })
        vim.keymap.set("n", "<leader>sp", function()
            swap.swap_previous("@parameter.inner")
        end, { desc = "Swap with previous parameter" })
    end,
}
