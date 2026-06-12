return {
    "nvim-treesitter/nvim-treesitter",
    branch = "main",
    build = ":TSUpdate",
    config = function()
        -- On the main branch, highlight/indent are built into Neovim.
        -- The plugin only handles parser installation.
        require("nvim-treesitter").setup()

        -- Auto-install parsers on FileType
        vim.api.nvim_create_autocmd("FileType", {
            callback = function(args)
                local lang = vim.treesitter.language.get_lang(args.match) or args.match
                if not pcall(vim.treesitter.language.inspect, lang) then
                    local ok, list = pcall(require("nvim-treesitter").get_available)
                    if ok and vim.tbl_contains(list, lang) then
                        pcall(function()
                            require("nvim-treesitter.install").install({ lang })
                        end)
                    end
                end
            end,
        })

        -- Incremental selection via treesitter nodes
        local function get_visual_range()
            local _, srow, scol, _ = unpack(vim.fn.getpos("v"))
            local _, erow, ecol, _ = unpack(vim.fn.getpos("."))
            return srow - 1, scol - 1, erow - 1, ecol - 1
        end

        vim.keymap.set("n", "<Enter>", function()
            local node = vim.treesitter.get_node()
            if not node then return end
            local sr, sc, er, ec = node:range()
            vim.fn.setpos(".", { 0, sr + 1, sc + 1, 0 })
            vim.cmd("normal! v")
            vim.fn.setpos(".", { 0, er + 1, ec, 0 })
        end, { desc = "Start treesitter incremental selection" })

        vim.keymap.set("v", "<Enter>", function()
            local node = vim.treesitter.get_node()
            if not node then return end
            local parent = node:parent()
            if not parent then return end
            local sr, sc, er, ec = parent:range()
            vim.fn.setpos(".", { 0, sr + 1, sc + 1, 0 })
            vim.cmd("normal! v")
            vim.fn.setpos(".", { 0, er + 1, ec, 0 })
        end, { desc = "Expand treesitter selection" })

        vim.keymap.set("v", "<Backspace>", function()
            local node = vim.treesitter.get_node()
            if not node then return end
            -- Try to find a child node that still covers the cursor
            local crow, ccol = unpack(vim.api.nvim_win_get_cursor(0))
            crow = crow - 1
            local child = node:named_child(0)
            if child then
                local sr, sc, er, ec = child:range()
                vim.fn.setpos(".", { 0, sr + 1, sc + 1, 0 })
                vim.cmd("normal! v")
                vim.fn.setpos(".", { 0, er + 1, ec, 0 })
            else
                vim.cmd("normal! v")
            end
        end, { desc = "Shrink treesitter selection" })
    end,
}
