return {
    "ibhagwan/fzf-lua",
    -- optional for icon support
    -- dependencies = { "nvim-tree/nvim-web-devicons" },
    -- or if using mini.icons/mini.nvim
    dependencies = { "echasnovski/mini.icons" },
    opts = {},
    config = function()
        local fzf     = require('fzf-lua')
        local actions = require('fzf-lua').actions

        fzf.setup {
            -- turn on multi-select
            fzf_opts = { ['--multi'] = '' },
            -- allow Tab/Shift-Tab to toggle selection
            keymap   = {
                fzf = {
                    ['tab']       = 'toggle',
                    ['shift-tab'] = 'toggle+up',
                    ["ctrl-q"] = "select-all+accept",
                },
            },
            actions  = {
                files = {
                    -- default <CR>: if more than one, qf + jump; else open file
                    ['default'] = function(selected, opts)
                        if #selected > 1 then
                            actions.file_sel_to_qf(selected, opts)
                            vim.cmd('cc') -- go to first quickfix entry
                        else
                            -- pass the whole table to file_edit_or_qf
                            actions.file_edit_or_qf(selected, opts)
                        end
                    end,
                    -- Ctrl-Q: select-all → qf → jump to first
                    -- ['ctrl-q'] = {
                    --     prefix = 'select-all',
                    --     fn = function(selected, opts)
                    --         actions.file_sel_to_qf(selected, opts)
                    --         vim.cmd('cc')
                    --     end,
                    -- },
                },
                -- you can duplicate this block under grep, live_grep, git_status, etc.
            },
        }

        -- (optional) if you want <C-q> in other pickers too, you can
        -- copy that actions block under grep, live_grep, git_status, etc.
        -- e.g.:
        -- fzf.setup {
        --   actions = {
        --     live_grep = {
        --       ['ctrl-q'] = {
        --         fn     = actions.file_sel_to_qf,
        --         prefix = 'select-all',
        --       },
        --     },
        --   },
        -- }
    end,
    keys = {
        {
            "<leader>ff",
            function() require('fzf-lua').files() end,
            desc = "Find Files in project directory"
        },
        {
            "<leader>fg",
            function() require('fzf-lua').live_grep() end,
            desc = "Find by grepping in project directory"
        },
        {
            "<leader>fc",
            function() require('fzf-lua').files({ cwd = vim.fn.stdpath("config") }) end,
            desc = "Find in neovim configuration"
        },
        {
            "<leader>fh",
            function()
                require("fzf-lua").helptags()
            end,
            desc = "[F]ind [H]elp",
        },
        {
            "<leader>fk",
            function()
                require("fzf-lua").keymaps()
            end,
            desc = "[F]ind [K]eymaps",
        },
        {
            "<leader>fb",
            function()
                require("fzf-lua").builtin()
            end,
            desc = "[F]ind [B]uiltin FZF",
        },
        {
            "<leader>fw",
            function()
                require("fzf-lua").grep_cword()
            end,
            desc = "[F]ind current [W]ord",
        },
        {
            "<leader>fW",
            function()
                require("fzf-lua").grep_cWORD()
            end,
            desc = "[F]ind current [W]ORD",
        },
        {
            "<leader>fd",
            function()
                require("fzf-lua").diagnostics_document()
            end,
            desc = "[F]ind [D]iagnostics",
        },
        {
            "<leader>fr",
            function()
                require("fzf-lua").resume()
            end,
            desc = "[F]ind [R]esume",
        },
        {
            "<leader>fo",
            function()
                require("fzf-lua").oldfiles()
            end,
            desc = "[F]ind [O]ld Files",
        },
        {
            "<leader><leader>",
            function()
                require("fzf-lua").buffers()
            end,
            desc = "[,] Find existing buffers",
        },
        {
            "<leader>/",
            function()
                require("fzf-lua").lgrep_curbuf()
            end,
            desc = "[/] Live grep the current buffer",
        },
    }
}
