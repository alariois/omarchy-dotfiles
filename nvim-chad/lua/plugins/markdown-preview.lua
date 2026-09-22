-- Live markdown preview in the browser, synced to the cursor.
--
-- NOTE on `build`: upstream's usual install step (`mkdp#util#install()`) pulls
-- a prebuilt Node binary that SEGFAULTS on this machine's glibc (2.44). The
-- plugin falls back to running the app with `node` whenever that binary is
-- absent, which works fine, so we build the Node app instead and never fetch
-- the binary.
return {
    "iamcco/markdown-preview.nvim",
    cmd = { "MarkdownPreview", "MarkdownPreviewStop", "MarkdownPreviewToggle" },
    build = function()
        local dir = require("lazy.core.config").plugins["markdown-preview.nvim"].dir
        vim.fn.system({ "npm", "--prefix", dir .. "/app", "install", "--no-audit", "--no-fund" })
        -- Make sure a previously downloaded (crashing) binary can't win.
        for _, bin in ipairs(vim.fn.glob(dir .. "/app/bin/markdown-preview-*", false, true)) do
            if not bin:match("%.bak$") then
                vim.fn.delete(bin)
            end
        end
    end,
    init = function()
        vim.g.mkdp_filetypes = { "markdown" }
        -- Leave the preview tab open when switching away from the buffer.
        vim.g.mkdp_auto_close = 0
    end,
    config = function()
        -- mkdp defines its commands as BUFFER-LOCAL from its own FileType
        -- autocmd. When lazy loads the plugin on demand that event has already
        -- passed for the open buffer, so re-fire it or the commands silently
        -- do nothing.
        vim.cmd([[do FileType]])
    end,
    keys = {
        {
            "<leader>mp",
            "<cmd>MarkdownPreviewToggle<CR>",
            ft = "markdown",
            desc = "Toggle markdown preview (browser)",
        },
    },
}
