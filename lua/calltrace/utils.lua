-- utility-container for calltrace-plugin

local M = {}

-- Debug print helper
function M.debug_print(config, ...)
    if config.debug then
        print("[calltrace]", ...)
    end
end

-- Check if a file should be excluded
function M.should_exclude_file(file, exclude_patterns)
    for _, pattern in ipairs(exclude_patterns) do
        if file:match(pattern) then
            return true
        end
    end
    return false
end

-- Place referencesign in the signcolumn
function M.place_reference_sign(bufnr, lnum, icon)
    -- Define sign if not already defined - TODO configurable texthighlight? And think about moving it to init for performance
    vim.fn.sign_define('ReferencePoint', {text = icon or 'R', texthl = 'WarningMsg', numhl = ''})
    -- Remove previous sign(s) for this buffer
    vim.fn.sign_unplace('ReferenceGroup', {buffer = bufnr})
    -- Place new sign
    vim.fn.sign_place(0,                            -- id (auto)
                      'ReferenceGroup',             -- group
                      'ReferencePoint',             -- name
                      bufnr,
                      {lnum = lnum, priority = 10}) -- TODO configurable prio?
end

-- create namespace, cache it to save repeated lookups, even though those are kinda fast
local preview_ns = vim.api.nvim_create_namespace("telescope_preview_temp")

-- temporarily highlight line in buffer
function M.highlight_line(bufnr, lnum, duration_ms)
    -- Zero-based linenumbers for set_extmark
    local mark_id = vim.api.nvim_buf_set_extmark(bufnr, preview_ns, (lnum or 1) - 1, 0, {
        end_line = (lnum or 1), -- end one line later
        hl_group = "CursorLine",
        priority = 200,
    })
    vim.defer_fn(function()
        if vim.api.nvim_buf_is_valid(bufnr) then
            vim.api.nvim_buf_del_extmark(bufnr, preview_ns, mark_id)
        end
    end, duration_ms or 2000)
end

-- Clear referencesign(s) from buffer
function M.clear_reference_sign(bufnr)
    vim.fn.sign_unplace('ReferenceGroup', {buffer = bufnr})
end

return M
