-- Init-File for calltrace-plugin. "Exports" all required functions for setup and creating neovimcmnds 

local M = {}

-- Init submodules
local config = require('calltrace.config')
local state = require('calltrace.state')
local tracer = require('calltrace.tracer')
local ts = require('calltrace.treesitter')
local lsp = require('calltrace.lsp')
local ui = require('calltrace.ui')

-- Configuration -> We do not really care if user forgot to setup -> We have stable config in here anyhow
M.config = config.defaults

-- Setup function -> called by nvim conf using require("module").setup
function M.setup(opts)
    M.config = config.setup(opts or {})
end

-- Set reference point at cursor position -> called by nvim cmds
function M.set_reference()
    local bufnr = vim.api.nvim_get_current_buf()
    local pos = vim.api.nvim_win_get_cursor(0)

    local function_name = ts.get_funcname_surrounding_pos(bufnr, pos[1], pos[2], M.config)

    if not function_name then
        vim.notify("No function found at cursor", vim.log.levels.WARN)
        return
    end

    if state.get_reference() then
        M.clear_reference()
    end

    state.set_reference(M.config, bufnr, pos, function_name)
    vim.notify(string.format("Referencepoint set: %s", function_name), vim.log.levels.INFO)
end

-- Clear reference point -> caled by nvim cmds
function M.clear_reference()
    state.clear_reference(M.config)
    vim.notify("Referencepoint cleared", vim.log.levels.INFO)
end

-- Show current refpoint by jumping to it
-- TODO maybe rethink naming? Later I want show ref in signcol, this could be misunderstandable
function M.show_reference()
    local ref = state.get_reference()

    -- Wrn if we have not yet set ref
    if not ref then
        vim.notify("No referencepoint set", vim.log.levels.WARN)
        return
    end

    -- Jump to current refpoint
    vim.api.nvim_set_current_buf(ref.bufnr)
    -- jump to pos(table<int,int>) in current window. Allready changed "window" to point to correct buffer
    vim.api.nvim_win_set_cursor(0, ref.pos)
    vim.notify(string.format("Referencepoint: %s", ref.name), vim.log.levels.INFO)
end

-- Main trace function
function M.trace(opts)
    opts = opts or {}

    local ref = state.get_reference()
    if not ref then
        vim.notify("No referencepoint set. Use :CalltraceSetReference first", vim.log.levels.WARN)
        return
    end

    local bufnr = vim.api.nvim_get_current_buf()
    local pos = vim.api.nvim_win_get_cursor(0)

    -- Check LSP availability
    if not lsp.is_lsp_available(bufnr) then
        vim.notify("No LSP client available for this buffer", vim.log.levels.ERROR)
        return
    end

    local current_function = ts.get_funcname_surrounding_pos(bufnr, pos[1], pos[2], M.config)

    if not current_function then
        vim.notify("No function found at cursor", vim.log.levels.WARN)
        return
    end

    vim.notify("Tracing call path...", vim.log.levels.INFO)

    -- Merge options with config to allow perCall override of defaults
    local trace_config = vim.tbl_deep_extend("force", M.config, opts)

    -- Perform trace
    local paths = tracer.trace_to_reference(bufnr, pos, current_function, ref, trace_config)

    -- If number of found paths zero we fauled to find connection
    if #paths == 0 then
        vim.notify("No path found to referencepoint", vim.log.levels.WARN)
        return
    end

    -- Display results
    ui.display_results(paths, trace_config)
end

-- Get cahced tracepaths as datastructure
function M.get_cached_trace_paths()
    return state.trace_cache
end

-- Toggle cache
function M.toggle_cache()
    M.config.cache_results = not M.config.cache_results
    local status = M.config.cache_results and "enabled" or "disabled"
    vim.notify(string.format("Cache %s", status), vim.log.levels.INFO)
end

-- Toggle debugmode
function M.toggle_debug()
    M.config.debug = not M.config.debug
    local status = M.config.debug and "enabled" or "disabled"
    vim.notify(string.format("Debug mode %s", status), vim.log.levels.INFO)
end

return M
