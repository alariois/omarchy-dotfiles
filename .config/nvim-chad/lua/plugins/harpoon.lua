return  {
    "ThePrimeagen/harpoon",
    lazy = true,
    branch = "harpoon2",
    dependencies = {
        "nvim-lua/plenary.nvim",
        "ibhagwan/fzf-lua",
    },
    keys = {
        {"<leader>a", desc = "Mark file"},
        {"<C-h>", desc = "Toggle quick menu"},
        {"<C-j>", desc = "Go to file 1"},
        {"<C-k>", desc = "Go to file 2"},
        {"<C-l>", desc = "Go to file 3"},
        {"<C-m>", desc = "Go to file 4"},
        {"<C-e>", desc = "Open Harpoon with fzf"},
    },
    config = function()
        local harpoon = require("harpoon")
        harpoon.setup()

        vim.keymap.set("n", "<leader>a", function()
            harpoon:list():add()
        end, { desc = "Mark file" })

        vim.keymap.set("n", "<C-h>", function()
            harpoon.ui:toggle_quick_menu(harpoon:list())
        end, { desc = "Toggle quick menu" })

        vim.keymap.set("n", "<C-j>", function()
            harpoon:list():select(1)
        end, { desc = "Go to file 1" })

        vim.keymap.set("n", "<C-k>", function()
            harpoon:list():select(2)
        end, { desc = "Go to file 2" })

        vim.keymap.set("n", "<C-l>", function()
            harpoon:list():select(3)
        end, { desc = "Go to file 3" })

        vim.keymap.set("n", "<C-m", function()
            harpoon:list():select(4)
        end, { desc = "Go to file 4" })

        vim.keymap.set("n", "<C-e>", function()
            local file_paths = {}
            for _, item in ipairs(harpoon:list().items) do
                table.insert(file_paths, item.value)
            end
            require("fzf-lua").fzf_exec(file_paths, {
                prompt = "Harpoon> ",
                actions = {
                    ["default"] = function(selected)
                        if selected and selected[1] then
                            vim.cmd("edit " .. selected[1])
                        end
                    end,
                },
            })
        end, { desc = "Open Harpoon with fzf" })
    end,
}

