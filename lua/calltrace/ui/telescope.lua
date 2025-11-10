-- Telescope display backend for calltrace-plugin

local pickers = require "telescope.pickers"
local finders = require "telescope.finders"
local sorters = require "telescope.sorters"
local previewers = require "telescope.previewers"
local actions = require "telescope.actions"
local action_state = require "telescope.actions.state"
-- local conf = require("telescope.config").values

local M = {}

-- Processes callpaths in flat list for finder
local function process_paths(paths, config)
    local results = {}

    for path_idx, path in ipairs(paths) do
        -- TODO Check agagins docu
        -- telescope seems to display in reversed order, so we can reverse what we had in quickfix and float to fix it here
        for i = 1, #path, 1 do
            local entry = path[i]

            -- Generate displayname to include possible aliasing
            local display_name = entry.function_name
            if entry.alias and entry.alias ~= entry.function_name then
                display_name = string.format("%s (%s)", entry.function_name, entry.alias)
            end

            local text
            if entry.calls then
                text = string.format("%s %s %s %s",
                                     config.icons.call,
                                     display_name,
                                     config.icons.path,
                                     entry.calls)
            else
                -- Leaf -> Found our Tracee
                text = string.format("%s %s (start)", config.icons.target, display_name)
            end

            table.insert(results, {
                display = text,
                ordinal = text,
                filename = entry.file,
                lnum = entry.line,
                col = entry.col + 1,
                value = entry,
            })
        end

        -- Header for this path
        table.insert(results, {
            display = string.format("=== Path %d ===", path_idx),
            ordinal = string.format("Path %d", path_idx),
            -- Use nonexistent file to stop previewer
            -- TODO Check if this might have any performance-issues or anything like that
            filename = "/dev/null",
            lnum = 0,
            col = 0,
        })

        -- Add separator
        table.insert(results, {
            display = "",
            ordinal = "",
            filename = "/dev/null",
            lnum = 0,
            col = 0,
        })
    end

    return results
end

function M.display(paths, config)
    local results = process_paths(paths, config)

    -- TODO put in opts?
    pickers.new({
        prompt_title = "Call-Trace",
        finder = finders.new_table {
            results = results,
            entry_maker = function(entry)
                return {
                    value = entry.value,
                    display = entry.display,
                    ordinal = entry.ordinal,
                    filename = entry.filename,
                    lnum = entry.lnum,
                    col = entry.col,
                }
            end,
        },
        sorter = sorters.get_generic_fuzzy_sorter({}),
        previewer = previewers.new_buffer_previewer {
            get_buffer_by_name = function(_, entry)
                return entry.filename
            end,
            define_preview = function(self, entry, status)
                -- For header and separator clear preview
                if not entry.filename or entry.filename == "/dev/null" then
                    vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, {})
                    return
                end
                previewers.buffer_previewer_maker(
                    entry.filename,
                    self.state.bufnr,
                    {
                        start_lnum = entry.lnum,
                        start_col = entry.col,
                    }
                )
            end,
        },
        -- override replace-defaults (on Enter)
        attach_mappings = function(prompt_bufnr, map)
            actions.select_default:replace(function()
                actions.close(prompt_bufnr)
                -- if selected file exists open it
                local selection = action_state.get_selected_entry()
                if selection.filename and selection.filename ~= "/dev/null" then
                    vim.cmd(string.format("edit +%d %s", selection.lnum, selection.filename))
                    vim.api.nvim_win_set_cursor(0, { selection.lnum, selection.col - 1 })
                end
            end)
            return true
        end,
    }):find()
end

return M
