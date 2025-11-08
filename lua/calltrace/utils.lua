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

-- Clear referencesign(s) from buffer
function M.clear_reference_sign(bufnr)
    vim.fn.sign_unplace('ReferenceGroup', {buffer = bufnr})
end

return M
