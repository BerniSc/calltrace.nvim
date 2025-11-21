-- Configmanagement for calltrace plugin

local M = {}

M.defaults = {
    -- Maximum Depth to trace (prevent infinite loops)
    max_depth = 20,

    -- Displayoptions
    display = {
        -- "quickfix" | "float" | "telescope"
        backend = "float",
        -- Highlight referencepoint in signcol
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
        entry = "📍",
        target = "",
        call = "󰃀",
        path = "→",         -- Might also hold strings like "calls" etc
    },

    loop_detection = {
        -- "simplified" checks if function in path already, if yes it detects a loop, "complete" detects funtionFrom->FunctionTo pairs
        -- (in a call foo->bar->baz->bar->goal as well as foo->bar->goal "complete" would display all, "simplified" one)
        mode = "simplified",    -- "simplified" | "complete"

    },

    -- Debugmode
    debug = false,
}

function M.setup(opts)
    return vim.tbl_deep_extend("force", M.defaults, opts or {})
end

return M
