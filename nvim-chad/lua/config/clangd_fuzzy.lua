-- Fuzzy clangd completion for C/C++, on two insert-mode keys (see plugins/blink-cmp.lua):
--   <M-Space>  blink menu
--   <M-f>      fzf-lua picker seeded with the word, with signature/docs preview
--
-- clangd filters completions with its own matcher before blink sees them, and
-- that matcher won't skip a word: `xkb_new` never offers `xkb_context_new`.
-- So ask clangd as if only the first letter of the word were typed, with no
-- result limit, and fuzzy-filter that one list locally. Both keys share the
-- list, so the second key on the same word doesn't ask clangd again. It only
-- runs on these keys, never on ordinary keystrokes.
local M = {}

local ns = vim.api.nvim_create_namespace("clangd_fuzzy")

local function client_for(bufnr)
    return vim.lsp.get_clients({ bufnr = bufnr, name = "clangd" })[1]
end

function M.available()
    return client_for(0) ~= nil
end

-- Last fetched list, keyed by where its word starts and the letter asked at
local last = { key = nil, items = nil }

-- Columns are 0-indexed bytes
local function fetch(client, bufnr, row, line, word_start, cursor, callback)
    local ask_at = cursor > word_start and word_start + 1 or cursor
    local key = table.concat({ bufnr, row, word_start, line:sub(word_start + 1, ask_at) }, ":")
    if last.key == key then
        callback(last.items)
        return function() end
    end

    local params = {
        textDocument = vim.lsp.util.make_text_document_params(bufnr),
        position = { line = row - 1, character = vim.str_utfindex(line, client.offset_encoding, ask_at, false) },
        context = { triggerKind = vim.lsp.protocol.CompletionTriggerKind.Invoked },
        limit = 0, -- clangd extension: no result cap, for this request only
    }

    local _, request_id = client:request("textDocument/completion", params, function(err, result)
        local items = (err == nil and result ~= nil) and (result.items or result) or {}
        -- Nothing offered (e.g. naming a new variable): don't keep that for the word
        if #items > 0 then
            last = { key = key, items = items }
        end
        callback(items)
    end, bufnr)

    return function()
        if request_id ~= nil then
            client:cancel_request(request_id)
        end
    end
end

--- blink.cmp source ---

function M.get_completions(_, context, callback)
    local function respond(items)
        -- The list is complete for this word: blink filters it locally from here on
        callback({ is_incomplete_forward = false, is_incomplete_backward = false, items = items })
    end

    local bufnr = vim.api.nvim_get_current_buf()
    local client = client_for(bufnr)
    if client == nil then
        respond({})
        return function() end
    end

    local word_start = context.bounds.start_col - 1
    local cursor = context.cursor[2]
    return fetch(client, bufnr, context.cursor[1], context.line, word_start, cursor, function(items)
        local cursor_lsp = vim.str_utfindex(context.line, client.offset_encoding, cursor, false)
        for _, item in ipairs(items) do
            item.client_id = client.id
            item.client_name = client.name
            item.cursor_column = cursor
            -- clangd's edit only covers the letter we asked at; stretch it to the cursor
            if item.textEdit ~= nil and item.textEdit.range ~= nil then
                item.textEdit.range["end"].character = cursor_lsp
            end
        end
        respond(items)
    end)
end

--- fzf-lua picker ---

local function grey(s)
    return "\27[90m" .. s .. "\27[0m"
end

local function bold(s)
    return "\27[1m" .. s .. "\27[0m"
end

local function name_of(item)
    return vim.trim(item.filterText or item.label)
end

-- "(params)" and return type, from either label style clangd uses
local function signature_of(item)
    local name = name_of(item)
    local label = vim.trim((item.label:gsub("^%s*•", "")))
    local params = item.labelDetails and item.labelDetails.detail
        or (vim.startswith(label, name) and label:sub(#name + 1) or "")
    local ret = item.detail or (item.labelDetails and item.labelDetails.description) or ""
    return params, ret
end

local function kind_of(item)
    return vim.lsp.protocol.CompletionItemKind[item.kind] or ""
end

local function preview_lines(item)
    local params, ret = signature_of(item)
    local lines = { bold(name_of(item) .. params) }
    if ret ~= "" then
        table.insert(lines, "→ " .. ret)
    end
    table.insert(lines, grey(kind_of(item)))

    local doc = item.documentation
    if type(doc) == "table" then
        doc = doc.value
    end
    if doc ~= nil and doc ~= "" then
        table.insert(lines, "")
        -- clangd escapes markdown punctuation (`xcb\_connect`); show it plain
        vim.list_extend(lines, vim.split((doc:gsub("\\(%p)", "%1")), "\n"))
    end

    for _, edit in ipairs(item.additionalTextEdits or {}) do
        table.insert(lines, "")
        table.insert(lines, grey("also adds: " .. vim.trim(edit.newText)))
    end
    return lines
end

-- 0-indexed byte column where the identifier ending at `cursor` starts
local function word_start_before(line, cursor)
    local start = cursor
    while start > 0 and line:sub(start, start):match("[%w_]") do
        start = start - 1
    end
    return start
end

-- Back to insert mode with the cursor before byte `col` of `row`
local function resume_insert(win, row, col)
    if not vim.api.nvim_win_is_valid(win) then
        return
    end
    vim.api.nvim_set_current_win(win)
    if col == 0 then
        vim.api.nvim_win_set_cursor(win, { row, 0 })
        vim.api.nvim_feedkeys("i", "n", false)
    else
        vim.api.nvim_win_set_cursor(win, { row, col - 1 })
        vim.api.nvim_feedkeys("a", "n", false)
    end
end

local function accept(item, client, win, row, word_start, cursor)
    local bufnr = vim.api.nvim_win_get_buf(win)
    local name = name_of(item)
    vim.api.nvim_buf_set_text(bufnr, row - 1, word_start, row - 1, cursor, { name })

    -- An #include clangd adds above moves the line; follow the end of the name
    local mark = vim.api.nvim_buf_set_extmark(bufnr, ns, row - 1, word_start + #name, {})
    if item.additionalTextEdits ~= nil and #item.additionalTextEdits > 0 then
        vim.lsp.util.apply_text_edits(item.additionalTextEdits, bufnr, client.offset_encoding)
    end
    local pos = vim.api.nvim_buf_get_extmark_by_id(bufnr, ns, mark, {})
    vim.api.nvim_buf_del_extmark(bufnr, ns, mark)

    resume_insert(win, pos[1] + 1, pos[2])
end

local function open_picker(items, client, win, row, word_start, cursor, word)
    local entries, seen = {}, {}
    for i, item in ipairs(items) do
        local name = name_of(item)
        local params, ret = signature_of(item)
        -- A C struct and its typedef come back as two items; list the name once
        if not seen[name .. params] then
            seen[name .. params] = true
            local info = params .. (ret ~= "" and "  → " .. ret or "") .. "  " .. kind_of(item)
            table.insert(entries, ("%d\t%s\t%s"):format(i, name, grey(info)))
        end
    end

    local function item_of(entry)
        return entry ~= nil and items[tonumber(entry:match("^(%d+)\t"))] or nil
    end

    local function cancel()
        resume_insert(win, row, cursor)
    end

    local function choose(selected)
        local item = item_of(selected[1])
        if item == nil then
            return cancel()
        end
        accept(item, client, win, row, word_start, cursor)
    end

    require("fzf-lua").fzf_exec(entries, {
        prompt = "clangd> ",
        query = word,
        -- The "hide" profile swaps our esc action for its own, and resuming
        -- (<leader>fr) would insert at a stale position: opt out of both
        no_hide = true,
        no_resume = true,
        winopts = { title = " clangd completions " },
        fzf_opts = {
            ["--delimiter"] = "\t",
            ["--with-nth"] = "2..", -- hide the index
            ["--nth"] = "1", -- match on the name only
            ["--multi"] = false,
        },
        preview = function(selected)
            local item = item_of(selected[1])
            return item ~= nil and preview_lines(item) or ""
        end,
        actions = {
            enter = choose,
            ["ctrl-y"] = choose,
            esc = cancel,
            ["ctrl-c"] = cancel,
        },
    })
end

function M.pick()
    local bufnr = vim.api.nvim_get_current_buf()
    local client = client_for(bufnr)
    if client == nil then
        vim.notify("No clangd in this buffer", vim.log.levels.WARN)
        return
    end
    pcall(function()
        require("blink.cmp").hide()
    end)

    local win = vim.api.nvim_get_current_win()
    local pos = vim.api.nvim_win_get_cursor(win)
    local line = vim.api.nvim_get_current_line()
    local word_start = word_start_before(line, pos[2])

    -- Scheduled: blink runs keymaps where windows can't be opened (E565),
    -- and a reused list calls back right away
    fetch(client, bufnr, pos[1], line, word_start, pos[2], vim.schedule_wrap(function(items)
        if vim.api.nvim_get_current_win() ~= win then
            return
        end
        if #items == 0 then
            vim.notify("clangd has no completions here", vim.log.levels.WARN)
            return
        end
        -- Take the word as it is now: typing may have continued while clangd answered
        pos = vim.api.nvim_win_get_cursor(win)
        line = vim.api.nvim_get_current_line()
        word_start = word_start_before(line, pos[2])
        open_picker(items, client, win, pos[1], word_start, pos[2], line:sub(word_start + 1, pos[2]))
    end))
end

return M
