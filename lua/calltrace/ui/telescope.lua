-- Telescope display backend for calltrace-plugin

local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local sorters = require("telescope.sorters")
local previewers = require("telescope.previewers")
local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")
local utils = require("calltrace.utils")

local M = {}

-- Processes callpaths in flat list for finder
local function process_paths(paths, config)
    local results = {}

    for path_idx, path in ipairs(paths) do
        -- TODO Cant find any reference in Docu, this does not feel entirely great, but it works for me if I just change the order, lets see if it keeps this way 
        -- telescope seems to display in reversed order, so we can reverse what we had in quickfix and float to fix it here (including headers and seperators)
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

            -- telescope.make_entry format so we can "pass these values through" in our display function
            table.insert(results, {
                value = entry,          -- Anything -> Still required
                ordinal = text,         -- Used for filtering
                display = text,         -- what to display, COOOUUULD be a func as well, maybe keep in mind for later
                filename = entry.file,  -- <cr> will open this file
                lnum = entry.line,      -- <cr> will jump here
                col = entry.col + 1,    -- <cr> will jump here
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
            lnum = -1,
            col = 0,
        })
    end

    return results
end

function M.display(paths, config)
    local results = process_paths(paths, config)

    local opts = {
        results_title = "Call-Trace Results",
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
        sorter = sorters.get_generic_fuzzy_sorter({}),  -- Need sorter to "filter" once we are typing. Use generic sorter for that
        previewer = previewers.new_buffer_previewer {
            -- unique name for buffers (caching)
            get_buffer_by_name = function(_, entry)
                return entry.filename
            end,
            -- called each move/update for each file, TODO performance?
            define_preview = function(self, entry, status)
                -- For header and separator clear preview
                if not entry.filename or entry.filename == "/dev/null" then
                    vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, {})
                    return
                end
                -- teardown will automatically clean up all created buffers -> Open them here with filepath, buffernumber and options (in this case where to jump to)
                previewers.buffer_previewer_maker(entry.filename,
                                                  self.state.bufnr,
                                                  -- Use callback to jump preview to functionline and highlight the line as well for some seconds
                                                  -- as suggested in :help for telescope.previewers.buffer_previewer_maker()
                                                  { callback = function(bufnr)
                                                        -- callback is called when the buffer is ready
                                                        if vim.api.nvim_win_is_valid(self.state.winid) then
                                                            vim.api.nvim_win_set_cursor(self.state.winid, { entry.lnum or 1, (entry.col or 1) - 1 })
                                                            -- Center line in window if we have the space for it
                                                            vim.api.nvim_win_call(self.state.winid, function()
                                                                vim.cmd("normal! zz")
                                                            end)
                                                            utils.highlight_line(self.state.bufnr, entry.lnum or 1, 5000)
                                                       end
                                                    end })
            end,
        },
        -- Even if preview was disabled globaly opt in for this picker, if you dont like it pick a different frontend or create an issue
        preview = true,
        -- override replace-defaults (on Enter), no need to use the "map" option yet so we use "_" instead so linter doesnt cry
        attach_mappings = function(prompt_bufnr, _)
            -- Replace default select-action
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
    }

    -- TODO Allow external defaults, maybe make less important opts so style can be determined by user
    local defaults = {}

    pickers.new(opts, defaults):find()
end

return M
