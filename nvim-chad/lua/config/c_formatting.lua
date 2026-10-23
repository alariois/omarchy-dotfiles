-- C/C++: indent while typing the way <leader>cf (clang-format) will format it.
--
-- vim-sleuth guesses the indent from each file's existing lines, and cindent
-- uses that guess, while clang-format follows the nearest .clang-format (LLVM,
-- 2 spaces, when there is none). So take the indent from clang-format instead,
-- and let clangd re-indent each new line as you press Enter.

local filetypes = { "c", "cpp" }

for _, ft in ipairs(filetypes) do
    vim.g["sleuth_" .. ft .. "_heuristics"] = 0
end

-- IndentWidth, UseTab and TabWidth from the style clang-format uses for `path`
local function clang_format_style(path)
    local ok, result = pcall(function()
        return vim.system({ "clang-format", "--dump-config", "--assume-filename=" .. path }, { text = true })
            :wait(2000)
    end)
    if not ok or result.code ~= 0 then
        return nil
    end
    local style = {}
    for _, key in ipairs({ "IndentWidth", "UseTab", "TabWidth" }) do
        style[key] = result.stdout:match("\n" .. key .. ":%s*(%S+)")
    end
    return style
end

vim.api.nvim_create_autocmd("FileType", {
    pattern = filetypes,
    desc = "Indent C/C++ like clang-format",
    callback = function(ev)
        local path = vim.api.nvim_buf_get_name(ev.buf)
        if path == "" then
            path = vim.fn.getcwd() .. "/untitled." .. vim.bo[ev.buf].filetype
        end
        local style = clang_format_style(path)
        if style == nil or tonumber(style.IndentWidth) == nil then
            return
        end
        local bo = vim.bo[ev.buf]
        bo.shiftwidth = tonumber(style.IndentWidth)
        bo.softtabstop = -1 -- follow shiftwidth
        bo.expandtab = style.UseTab == "Never"
        if not bo.expandtab and tonumber(style.TabWidth) then
            bo.tabstop = tonumber(style.TabWidth)
        end
    end,
})

-- clangd formats on Enter: it re-indents the new line and tidies the one you left
vim.api.nvim_create_autocmd("LspAttach", {
    desc = "Format C/C++ as you type, through clangd",
    callback = function(ev)
        local client = vim.lsp.get_client_by_id(ev.data.client_id)
        if client ~= nil and client.name == "clangd" then
            vim.lsp.on_type_formatting.enable(true, { client_id = client.id })
        end
    end,
})
