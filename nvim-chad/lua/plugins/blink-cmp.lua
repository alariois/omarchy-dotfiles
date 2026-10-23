-- Whether accepting `item` starts placeholders of its own (a function's parameters)
local function opens_placeholders(item)
    local text = item.textEdit and item.textEdit.newText or item.insertText or ""
    return item.insertTextFormat == vim.lsp.protocol.InsertTextFormat.Snippet and text:match("%${?[1-9]") ~= nil
end

-- <C-y>/<CR>: accept the selected (or first) item, then go on to the next
-- parameter of the function being filled in. With no menu, just go on.
local function accept_and_jump(cmp)
    if cmp.is_visible() then
        local item = cmp.get_selected_item() or cmp.get_items()[1]
        return cmp.select_and_accept({
            callback = function()
                -- A function accepted into a parameter starts its own placeholders: stay on its first
                if item ~= nil and not opens_placeholders(item) then
                    cmp.snippet_forward()
                end
            end,
        })
    end
    return cmp.snippet_forward()
end

return {
    {
        "saghen/blink.compat",
        -- use the latest release, via version = '*', if you also use the latest release for blink.cmp
        version = "*",
        -- lazy.nvim will automatically load the plugin when it's required by blink.cmp
        lazy = true,
        -- make sure to set opts so that lazy.nvim calls blink.compat's setup
        opts = {},
    },
    {
        "saghen/blink.cmp",
        -- optional: provides snippets for the snippet source
        dependencies = {
            "rafamadriz/friendly-snippets",
            "moyiz/blink-emoji.nvim",
            "ray-x/cmp-sql",
        },

        -- use a release tag to download pre-built binaries
        version = "1.*",
        -- AND/OR build from source, requires nightly: https://rust-lang.github.io/rustup/concepts/channels.html#working-with-nightly-rust
        -- build = 'cargo build --release',
        -- If you use nix, you can build from source using latest nightly rust with:
        -- build = 'nix run .#build-plugin',

        ---@module 'blink.cmp'
        ---@type blink.cmp.Config
        opts = {
            -- 'default' (recommended) for mappings similar to built-in completions (C-y to accept)
            -- 'super-tab' for mappings similar to vscode (tab to accept)
            -- 'enter' for enter to accept
            -- 'none' for no mappings
            --
            -- All presets have the following mappings:
            -- C-space: Open menu or open docs if already open
            -- C-n/C-p or Up/Down: Select next/previous item
            -- C-e: Hide menu
            -- C-k: Toggle signature help (if signature.enabled = true)
            --
            -- See :h blink-cmp-config-keymap for defining your own keymap
            keymap = {
                preset = "default",
                ["<C-Z>"] = { "accept", "fallback" },
                ["<C-y>"] = { accept_and_jump, "fallback" },
                -- Enter acts like <C-y> in the <M-Space> list and while filling in
                -- parameters; otherwise it stays a newline
                ["<CR>"] = {
                    function(cmp)
                        local item = cmp.get_selected_item()
                        if (cmp.is_visible() and item ~= nil and item.source_id == "clangd_fuzzy")
                            or cmp.snippet_active({ direction = 1 })
                        then
                            return accept_and_jump(cmp)
                        end
                    end,
                    "fallback",
                },
                -- C/C++: fetch everything clangd has for the word's first letter and
                -- fuzzy-filter it locally, so `xkb_new` finds `xkb_context_new`
                ["<M-Space>"] = {
                    function(cmp)
                        if require("config.clangd_fuzzy").available() then
                            return cmp.show({ providers = { "clangd_fuzzy" } })
                        end
                        return cmp.show()
                    end,
                },
                -- Same list in an fzf-lua picker, seeded with the word typed so far
                ["<M-f>"] = {
                    function()
                        require("config.clangd_fuzzy").pick()
                        return true
                    end,
                },
            },

            appearance = {
                -- 'mono' (default) for 'Nerd Font Mono' or 'normal' for 'Nerd Font'
                -- Adjusts spacing to ensure icons are aligned
                nerd_font_variant = "mono",
            },

            -- (Default) Only show the documentation popup when manually triggered
            completion = { documentation = { auto_show = true } },
            signature = { enabled = true },

            -- Default list of enabled providers defined so that you can extend it
            -- elsewhere in your config, without redefining it, due to `opts_extend`
            sources = {
                default = { "lsp", "path", "snippets", "buffer", "emoji", "sql" },
                providers = {
                    -- Only shown through <M-Space>, so it's not in `default`
                    clangd_fuzzy = {
                        name = "clangd",
                        module = "blink.cmp.sources.lsp",
                        override = {
                            get_completions = function(...)
                                return require("config.clangd_fuzzy").get_completions(...)
                            end,
                        },
                    },
                    emoji = {
                        module = "blink-emoji",
                        name = "Emoji",
                        score_offset = 15, -- Tune by preference
                        opts = { insert = true }, -- Insert emoji (default) or complete its name
                        should_show_items = function()
                            return vim.tbl_contains(
                                -- Enable emoji completion only for git commits and markdown.
                                -- By default, enabled for all file-types.
                                { "gitcommit", "markdown" },
                                vim.o.filetype
                            )
                        end,
                    },
                    sql = {
                        -- IMPORTANT: use the same name as you would for nvim-cmp
                        name = "sql",
                        module = "blink.compat.source",

                        -- all blink.cmp source config options work as normal:
                        score_offset = -3,

                        -- this table is passed directly to the proxied completion source
                        -- as the `option` field in nvim-cmp's source config
                        --
                        -- this is NOT the same as the opts in a plugin's lazy.nvim spec
                        opts = {},
                        should_show_items = function()
                            return vim.tbl_contains(
                                -- Enable emoji completion only for git commits and markdown.
                                -- By default, enabled for all file-types.
                                { "sql" },
                                vim.o.filetype
                            )
                        end,
                    },
                },
            },

            -- (Default) Rust fuzzy matcher for typo resistance and significantly better performance
            -- You may use a lua implementation instead by using `implementation = "lua"` or fallback to the lua implementation,
            -- when the Rust fuzzy matcher is not available, by using `implementation = "prefer_rust"`
            --
            -- See the fuzzy documentation for more information
            fuzzy = { implementation = "prefer_rust_with_warning" },
        },
        opts_extend = { "sources.default" },
    },
}
