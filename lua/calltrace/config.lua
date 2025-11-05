-- Configmanagement for calltrace plugin

local M = {}

M.defaults = {
    -- Maximum Depth to trace (prevent infinite loops)
    max_depth = 50,

    -- Displayoptions
    display = {
        -- "quickfix" | "float" | "split" | "telescope"
        -- TODO Implement the others
        backend = "float",
        -- Highlight reference point differently TODO Implement
        highlight_reference = true,
    },

    -- Performance options
    timeout = 5000,                 -- ms for LSP requests
    cache_results = true,           -- TODO Implement

    -- Filtering - exclude certain files/dirs from trace
    exclude_patterns = {
        "node_modules/",
        "*/test/*",
    },

    -- UI-Customization
    icons = {
        reference = "📍",   -- currently used for shortly set reference (may provoke misunderstandings -> TODO Look at it)
        call = "󰃀",
        path = "→",
    },

    -- Debugmode
    debug = false,
}

function M.setup(opts)
    return vim.tbl_deep_extend("force", M.defaults, opts or {})
end

return M
