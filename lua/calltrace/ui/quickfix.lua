-- Quickfix display backend for calltrace-plugin

local M = {}

function M.display(paths, config)
    local qf_list = {}

    for path_idx, path in ipairs(paths) do
        -- header for this path -> Mark with custom, useless type to remind me that it is just for my infomation
        table.insert(qf_list, { text = string.format("=== Path %d ===", path_idx),
                                type = "INFORMATION", })

        -- get current pathelement, starting with Main-Referencepoint to which we trace up to
        for i = #path, 1, -1 do
            local entry = path[i]
            local text

            if entry.calls then
                text = string.format("%s %s %s %s",
                                     config.icons.call,
                                     entry.function_name,
                                     config.icons.path,
                                     entry.calls)
            else
                -- Leaf -> Found our Tracee
                text = string.format("%s %s (start)", config.icons.target, entry.function_name)
            end

            -- Insert entry with this line and colnums
            table.insert(qf_list, { filename = entry.file,
                                    lnum = entry.line,
                                    col = entry.col + 1,
                                    text = text, })
        end

        -- Add separator
        table.insert(qf_list, { text = "", type = "INFORMATION" })
    end

    -- Replace current qucikfixlist with build list and open it
    vim.fn.setqflist(qf_list, 'r')
    vim.cmd('copen')

    -- FOR DEBUG - TODO Make really "debuggable"?
    -- vim.notify(string.format("Found %d path(s) to reference point", #paths), vim.log.levels.INFO)
end

return M
