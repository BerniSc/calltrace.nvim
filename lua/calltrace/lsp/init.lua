-- LSP utilities for calltrace-plugin

local M = {}

-- TODO move to local import in function to preven circular?
local utils = require('calltrace.utils')
local config = require('calltrace.config')

-- Get LSP definition for a position
function M.get_definition_at_position(bufnr, row, col, callback)
    vim.notify("IMPLEMENT BEFORE USE, DOOFUS (getDefintion Async)", vim.log.levels.ERROR)
end

-- Get the references from ALL attached LSPs for a position
-- TODO Make async for performance
function M.get_references_at_position(bufnr, row, col, timeout)
    timeout = timeout or 1000

    -- Save current state
    local save_bufnr = vim.api.nvim_get_current_buf()
    local save_winnr = vim.api.nvim_get_current_win()
    local save_pos = vim.api.nvim_win_get_cursor(save_winnr)

    -- Find or create a window for this buffer
    local target_win = nil
    for _, win in ipairs(vim.api.nvim_list_wins()) do
        if vim.api.nvim_win_get_buf(win) == bufnr then
            target_win = win
            break
        end
    end

    -- If no window exists, temporarily use current window
    local switched_buf = false
    if not target_win then
        target_win = save_winnr
        vim.api.nvim_win_set_buf(target_win, bufnr)
        switched_buf = true
    end

    -- Switch to targetwindow and set cursor > Can only get position by cursor so we move it
    vim.api.nvim_set_current_win(target_win)
    vim.api.nvim_win_set_cursor(target_win, {row, col})

    -- Debug output
    local line_text = vim.api.nvim_buf_get_lines(bufnr, row - 1, row, false)[1]
    if line_text then
        utils.debug_print(config, string.format("   [LSP] Getting refs at %d:%d, line='%s'", row, col, line_text:sub(1, 50)))
    end

    -- get encoding of windowparams for first client
    local clients = vim.lsp.get_clients({bufnr = bufnr})
    local client = clients[1]
    local encoding = client and client.offset_encoding or 'utf-16'

    -- Make params from current cursorposition
    -- Use current window and first clients encoding TODO Check whter we should include other clients here as well
    local params = vim.lsp.util.make_position_params(0, encoding)

    -- TODO CHECK Lint Warning
    params.context = { includeDeclaration = false }

    -- TODO are these the only way to have a reference? Or is there an alias or something like that?
    local results = vim.lsp.buf_request_sync(bufnr, "textDocument/references", params, timeout)

    -- Restore state before call
    if switched_buf then
        vim.api.nvim_win_set_buf(save_winnr, save_bufnr)
    end
    vim.api.nvim_set_current_win(save_winnr)
    vim.api.nvim_win_set_cursor(save_winnr, save_pos)

    if not results then
        utils.debug_print(config, "   [LSP] Found no references")
        return {}
    end

    local all_refs = {}
    -- we want ALL references, no matter the source -> disregard clientid
    for _, response in pairs(results) do
        if response.result then
            vim.list_extend(all_refs, response.result)
        end
    end

    return all_refs
end

-- Check if LSP is available for buffer
function M.is_lsp_available(bufnr)
    local clients = vim.lsp.get_clients({ bufnr = bufnr })
    -- At least one client attached
    return #clients > 0
end

-- Get active LSP clients for buffer
function M.get_clients(bufnr)
    return vim.lsp.get_clients({ bufnr = bufnr })
end

return M
