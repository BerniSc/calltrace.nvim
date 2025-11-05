-- Floating window display backend for calltrace-plugin

local M = {}

function M.display(paths, config)
    local lines = {}

    -- Go over each possible path in all paths and seperate them by index
    for path_idx, path in ipairs(paths) do
        table.insert(lines, string.format("=== Path %d ===", path_idx))

        -- Print the current pathelement, starting with Main-Referencepoint to which we trace up to
        -- start at number of elements in path, go down to 1, decrement counter each iteration
        for i = #path, 1, -1 do
            local entry = path[i]

            -- "unravel" our pathstack, start at last path that was found to finish loop, then go down. If it calls display so, otherwise say "goal reached"
            if entry.calls then
                table.insert(lines, string.format("  %s %s → %s",
                                    config.icons.call,
                                    entry.function_name,
                                    entry.calls))
            else
                -- Reached 
                table.insert(lines, string.format("  %s %s", config.icons.reference, entry.function_name))
            end
        end

        -- Empty line at the end to seperate from next path
        table.insert(lines, "")
    end

    -- Create floating window
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    -- WARN These are deprecated, look at alternatives
    vim.api.nvim_buf_set_option(buf, 'modifiable', false)
    vim.api.nvim_buf_set_option(buf, 'buftype', 'nofile')

    local width = 80
    local height = math.min(#lines, 30)
    -- TODO make configurable?
    local opts = {
        relative = 'editor',
        width = width,
        height = height,
        col = (vim.o.columns - width) / 2,
        row = (vim.o.lines - height) / 2,
        style = 'minimal',
        border = 'rounded',
        title = ' Call-Trace ',
        title_pos = 'center',
    }

    vim.api.nvim_open_win(buf, true, opts)

    -- Close on q or Esc
    vim.api.nvim_buf_set_keymap(buf, 'n', 'q', ':close<CR>', { noremap = true, silent = true })
    vim.api.nvim_buf_set_keymap(buf, 'n', '<Esc>', ':close<CR>', { noremap = true, silent = true })
end

return M
