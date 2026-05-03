local map = vim.keymap.set

local unmap = vim.keymap.del

-- unmap("n", "<C-h>")
-- unmap("n", "<C-j>")
-- unmap("n", "<C-k>")
-- unmap("n", "<C-l>")

map("n", "-", "<cmd>Oil --float<CR>", { desc = "Open Parent Directory in Oil" })
map("n", "gl", function()
    vim.diagnostic.open_float()
end, { desc = "Open Diagnostics in Float" })

map("n", "<leader>cf", function()
    require("conform").format({
        lsp_format = "fallback",
    })
end, { desc = "Format current file" })

-- Map <leader>fp to open projects
map("n", "<leader>fp", ":ProjectFzf<CR>", { noremap = true, silent = true })

function Add_workspace_diagnostics_to_quickfix()
  -- Get all diagnostics for all buffers (nil for buffer ID gets all workspace diagnostics)
  local diagnostics = vim.diagnostic.get(nil)

  -- Initialize an empty table to hold quickfix items
  local qf_items = {}

  -- Loop through all diagnostics and convert them to quickfix items
  for _, diag in ipairs(diagnostics) do
    local bufname = vim.api.nvim_buf_get_name(diag.bufnr)
    table.insert(qf_items, {
      bufnr = diag.bufnr,
      lnum = diag.lnum + 1,       -- Adjust line number for 1-based indexing
      col = diag.col + 1,         -- Adjust column number for 1-based indexing
      text = diag.message,
      filename = bufname,
    })
  end

  -- Set the quickfix list with the diagnostic items and open it
  vim.fn.setqflist(qf_items)
  vim.cmd('copen')   -- Open the quickfix window
end

map("n", "<leader>tf", "<cmd>ToggleFormat<CR>", { desc = "Toggle auto format" })
map("n", "<leader>y", '"+y', { desc = "Yank to system clipboard" })
map("n", "<leader>Y", '"+Y', { desc = "Yank till end of line to system clipboard" })
map("n", "<leader>dd", "<cmd>lua Add_workspace_diagnostics_to_quickfix()<CR>",
  { desc = "Add workspace diagnostics to quickfix" })
map("n", "<leader>pv", "<cmd>Ex<CR>", { desc = "Open netrw" })
map("n", "J", "mzJ`z", { desc = "Join lines" })
map("n", "<C-d>", "<C-d>zz", { desc = "Scroll down and center" })
map("n", "<C-u>", "<C-u>zz", { desc = "Scroll up and center" })
map("n", "<C-f>", "<cmd>silent !tmux neww tmux-sessionizer<CR>", { desc = "Open tmux sessionizer" })
map("n", "<leader>lf", "<cmd>lua vim.lsp.buf.format()<CR>", { desc = "Format buffer" })
map("n", "<leader>k", "<cmd>lnext<CR>zz", { desc = "Next location list item" })
map("n", "<leader>j", "<cmd>lprev<CR>zz", { desc = "Previous location list item" })
map("n", "<leader>sa", [[:s/\<<C-r><C-w>\>/&/gI<Left><Left><Left>]], { desc = "Append to word in line" })
map("n", "<leader>sA", [["zyiW:s/\<<C-r>z\>/&/gI<Left><Left><Left>]], { desc = "Append to WORD in line" })
map("n", "<leader>sw", [[:s/\<<C-r><C-w>\>//gI<Left><Left><Left>]], { desc = "Substitute word in line" })
map("n", "<leader>sW", [["zyiW:s/<C-r>z//gI<Left><Left><Left>]], { desc = "Substitute WORD in line" })
map("n", "<leader>sga", [[:%s/\<<C-r><C-w>\>/&/gI<Left><Left><Left>]], { desc = "Append to word in file (global)" })
map("n", "<leader>sgA", [["zyiW:%s/\<<C-r>z\>/&/gI<Left><Left><Left>]], { desc = "Append to WORD in file (global)" })
map("n", "<leader>sgw", [[:%s/\<<C-r><C-w>\>//gI<Left><Left><Left>]], { desc = "Substitute word in file (global)" })
map("n", "<leader>sgW", [["zyiW:%s/<C-r>z//gI<Left><Left><Left>]], { desc = "Substitute WORD in file (global)" })
map("n", "<leader>Sa", [[:Subvert/<C-r><C-w>/<C-r>z/g<Left><Left>]], { desc = "Subvert append to word in line" })
map("n", "<leader>SA", [["zyiW:Subvert/<C-r>z/<C-r>z/g<Left><Left>]], { desc = "Subvert append to WORD in line" })
map("n", "<leader>Sw", [[:Subvert/<C-r><C-w>//g<Left><Left>]], { desc = "Subvert word in line" })
map("n", "<leader>SW", [["zyiW:Subvert/<C-r>z//g<Left><Left>]], { desc = "Subvert WORD in line" })
map("n", "<leader>SGa", [[:%Subvert/<C-r><C-w>/<C-r>z/g<Left><Left>]],
  { desc = "Subvert append to word in file (global)" })
map("n", "<leader>SGA", [["zyiW:%Subvert/<C-r>z/<C-r>z/g<Left><Left>]],
  { desc = "Subvert append to WORD in file (global)" })
map("n", "<leader>SGw", [[:%Subvert/<C-r><C-w>//g<Left><Left>]], { desc = "Subvert word in file (global)" })
map("n", "<leader>SGW", [["zyiW:%Subvert/<C-r>z//g<Left><Left>]], { desc = "Subvert WORD in file (global)" })
map("n", "<leader>x", "<cmd>!chmod +x %<CR>", { desc = "Make file executable" })
map("n", "<C-M-p>", ":cnext<CR>", { desc = "Next quickfix item" })
map("n", "<C-M-q>", ":cprev<CR>", { desc = "Previous quickfix item" })
map("n", "<C-M-r>", function() vim.cmd('normal! @d') end, { desc = "Play macro at register d" })
map("n", "<leader>cl", ":cnext<CR>", { desc = "Next quickfix item [alternative]" })
map("n", "<leader>c,", ":cprev<CR>", { desc = "Previous quickfix item [alternative]" })
map("n", "<leader>cp", function() vim.cmd('normal! @d') end, { desc = "Play macro at register d [alternative]" })
map("n", "<leader>cc", ":lua _G.clear_quickfix()<CR>", { desc = "Clear quickfix list and window" })

map("v", "J", ":m '>+1<CR>gv=gv", { desc = "Move line down" })
map("v", "K", ":m '<-2<CR>gv=gv", { desc = "Move line up" })
map("v", "<leader>y", '"+y', { desc = "Yank to clipboard" })
map("v", "<leader>d", '"_d', { desc = "Delete without yanking" })
map("v", "<leader>sa", [[<Esc>"zyiwgv:s/\<<C-r>z\>/&/gI<Left><Left><Left>]], { desc = "Append to word in selection" })
map("v", "<leader>sw", [[<Esc>"zyiwgv:s/\<<C-r>z\>//gI<Left><Left><Left>]], { desc = "Substitute word in selection" })
map("v", "<leader>sA", [[<Esc>"zyiWgv:s/\<<C-r>z\>/&/gI<Left><Left><Left>]], { desc = "Append to WORD in selection" })
map("v", "<leader>sW", [[<Esc>"zyiWgv:s/<C-r>z//gI<Left><Left><Left>]], { desc = "Substitute WORD in selection" })
map("v", "<leader>Sa", [[<Esc>"zyiwgv:Subvert/<C-r>z/<C-r>z/g<Left><Left>]],
  { desc = "Subvert append to word in selection" })
map("v", "<leader>Sw", [[<Esc>"zyiwgv:Subvert/<C-r>z//g<Left><Left>]], { desc = "Subvert word in selection" })
map("v", "<leader>SA", [[<Esc>"zyiWgv:Subvert/<C-r>z/<C-r>z/g<Left><Left>]],
  { desc = "Subvert append to WORD in selection" })
map("v", "<leader>SW", [[<Esc>"zyiWgv:Subvert/<C-r>z//g<Left><Left>]], { desc = "Subvert WORD in selection" })

map("x", "<leader>p", '"_dP', { desc = "Paste and replace selection" })

