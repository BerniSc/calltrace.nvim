-- State management for calltrace-plugin

local M = {}

-- needed to place/remove signs in signcol
local utils = require('calltrace.utils')

-- State
M.cur_ref_point = nil
M.trace_cache = {}

-- Set refpoint at cursorposition, need config for signcol icon
function M.set_reference(config, bufnr, pos, function_name)
    M.cur_ref_point = {
        bufnr = bufnr,
        pos = pos,
        name = function_name,
        uri = vim.uri_from_bufnr(bufnr),
        file = vim.api.nvim_buf_get_name(bufnr),
    }

    -- Place sign at refline
    if config.display.highlight_reference then
        utils.place_reference_sign(bufnr, pos[1], config.icons.entry)
    end

    return M.cur_ref_point
end

-- Get current refpoint
function M.get_reference()
    return M.cur_ref_point
end

-- Clear refpoint
function M.clear_reference(config)
    if config.display.highlight_reference and M.cur_ref_point then
        utils.clear_reference_sign(M.cur_ref_point.bufnr)
    end
    M.cur_ref_point = nil
    M.trace_cache = {}
end

--
-- Cache-Management
-- TODO ACTUALLY USE^^ -> Create Working PoC first
--
function M.cache_result(key, result)
    M.trace_cache[key] = result
end

function M.get_cached_result(key)
    return M.trace_cache[key]
end

function M.clear_cache()
    M.trace_cache = {}
end

return M
