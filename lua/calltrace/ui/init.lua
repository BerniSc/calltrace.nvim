-- Display dispatcher for calltrace-plugin

local M = {}

local float = require('calltrace.ui.float')
local quickfix = require('calltrace.ui.quickfix')
-- local split = require('calltrace.ui.split')
local telescope = require('calltrace.ui.telescope')

function M.display_results(paths, config)
    local backend = config.display.backend

    if backend == "float" then
        float.display(paths, config)
    elseif backend == "quickfix" then
        quickfix.display(paths, config)
    -- elseif backend == "split" then
    --     split.display(paths, config)
    elseif backend == "telescope" then
        -- Check if telescope is even installed
        local ok, _ = pcall(require, "telescope")
        if not ok then
            vim.notify("Telescope not found, falling back to quickfix", vim.log.levels.WARN)
            quickfix.display(paths, config)
        else
            telescope.display(paths, config)
        end
    else
        vim.notify("Unknown display backend: " .. backend, vim.log.levels.ERROR)
    end
end

return M
