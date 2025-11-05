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

return M
