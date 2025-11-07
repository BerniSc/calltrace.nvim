-- core tracing algorithm for calltrace-plugin

local M = {}

-- To use core Functionality we use TS (faster) and LSP (more accurate with build in stuff) -> Include both here
local lsp = require('calltrace.lsp')
local ts = require('calltrace.treesitter')

-- Utils - holds stuff like debug-prints
local utils = require('calltrace.utils')

-- Main trace function
function M.trace_to_reference(bufnr, pos, function_name, reference_point, config)
    local max_depth = config.max_depth
    local timeout = config.timeout
    local exclude_patterns = config.exclude_patterns

    local all_paths = {}
    -- Prevent infinite loops by loop-detection dict
    local visited = {}

    -- Recursive trace function
    -- Takes:
    --      Buffernumber: int
    --      position of the functionname (unless failed to find it, then def): table<int,int>
    --      functionname: string
    --      tracepath: table<path_entry>
    --      recursiondepth: int
    local function trace_upward(current_bufnr, current_pos, current_name, path, depth)
        -- Exit early -> Reached max rec depth
        if depth > max_depth then
            utils.debug_print(config, "Max depth reached")
            return
        end

        -- Unique key for loop detection > Use "buffer:row:col" as key as it identifies function clearly
        local key = string.format("%s:%d:%d", vim.api.nvim_buf_get_name(current_bufnr), current_pos[1], current_pos[2])
        if visited[key] then
            utils.debug_print(config, "Already visited:", key)
            return
        end
        visited[key] = true

        utils.debug_print(config, string.format("Depth %d: Tracking %s at %s:%d", depth, current_name, vim.api.nvim_buf_get_name(current_bufnr), current_pos[1]))

        -- Check wheter we reached refpoint
        local current_file = vim.api.nvim_buf_get_name(current_bufnr)
        if current_file == reference_point.file and current_name == reference_point.name then
            -- Found complete path
            utils.debug_print(config, "Found path to reference point")
            -- path changes recursively, without deepcopy it would still mutate what we write into all_paths
            table.insert(all_paths, vim.deepcopy(path))
            return
        end

        -- Get refs to current position
        local refs = lsp.get_references_at_position(current_bufnr, current_pos[1], current_pos[2], timeout)
        -- # is shorthand for number-of-elements-in-table ^^
        utils.debug_print(config, string.format("Found %d references", #refs))

        if not refs or #refs == 0 then
            utils.debug_print(config, "No references found")
            return
        end

        -- Process each ref
        for idx, ref in ipairs(refs) do
            -- different LSP servers might return stuff as "targetUri" instead of "uri". Use both for failsafe^^
            -- https://github.com/typescript-language-server/typescript-language-server/issues/216
            local ref_uri = ref.uri or ref.targetUri
            -- dereference uri like file:///... to /... filepath
            local ref_file = vim.uri_to_fname(ref_uri)

            utils.debug_print(config, string.format("  Processing ref %d: %s", idx, ref_file))

            -- Skip excluded files
            if not utils.should_exclude_file(ref_file, exclude_patterns) then
                local ref_range = ref.range or ref.targetRange
                -- LSP Positions are 0-based, Lua and vim expect 1-based
                local ref_row = ref_range.start.line + 1
                local ref_col = ref_range.start.character

                utils.debug_print(config, string.format("   Position: %d:%d", ref_row, ref_col))

                -- Load buf for ref - create if it does not exist
                -- These buffers are created as hidden unlisted buffers and thereby are cleaned up automatically after functerm I think.
                -- No special cleanup needed
                local ref_bufnr = vim.fn.bufnr(ref_file, true)
                -- if buffer was created but not loaded some ops may fail -> fix here by reloading if it was not laoded
                if not vim.api.nvim_buf_is_loaded(ref_bufnr) then
                    vim.fn.bufload(ref_bufnr)
                end

                -- Ensure filetype is set set and attach ts parser. This is an issue if the buffer we are looking at was not opened manually before
                -- but was openend during our tracing. This results in the buffer just loading, but nothing attaching yet
                -- TODO Implement caching of results to mitigate high performanceimpact
                local ft = vim.filetype.match({ filename = ref_file })
                if ft then
                    -- Trigger autocommands and nvim filetypedetection
                    vim.api.nvim_buf_call(ref_bufnr, function()
                        vim.cmd('setfiletype ' .. ft)
                    end)
                    -- creates OR RETRIEVES parser for buffer -> No need to manually check
                    pcall(vim.treesitter.get_parser, ref_bufnr, ft)
                end

                -- Check if ref is actually a functioncall
                local is_call = ts.is_function_call(ref_bufnr, ref_row, ref_col)
                utils.debug_print(config, string.format("    Is function call: %s", tostring(is_call)))

                if is_call then
                    -- Find containing function by looking in what func we are right now
                    local containing_func_node = ts.get_fun_surrounding_pos(ref_bufnr, ref_row, ref_col)
                    if containing_func_node then
                        local containing_func_name = ts.get_function_name(ref_bufnr, containing_func_node)

                        utils.debug_print(config, string.format("    Containing function: %s", containing_func_name))

                        -- Check if containing func is refpoint
                        if ref_file == reference_point.file and
                            containing_func_name == reference_point.name then
                            -- Found path -> add step and we are done
                            local new_path_entry = {
                                file = ref_file,
                                line = ref_row,
                                col = ref_col,
                                function_name = containing_func_name,
                                calls = current_name,
                            }
                            -- Deepcopy path as other rec-calls work with it. Then add new entry onto path and finally add path to allPaths
                            local new_path = vim.deepcopy(path)
                            table.insert(new_path, new_path_entry)
                            table.insert(all_paths, new_path)
                            utils.debug_print(config, "Found complete path via:", containing_func_name)
                            return
                        end

                        -- Add to path
                        local new_path_entry = {
                            file = ref_file,
                            line = ref_row,
                            col = ref_col,
                            function_name = containing_func_name,
                            calls = current_name,
                        }
                        local new_path = vim.deepcopy(path)
                        table.insert(new_path, new_path_entry)

                        -- Get pos of function NAME (not start of definition)
                        -- To get it iterate over node until we read identifier/name and then exit loop
                        local name_node = nil
                        for child in containing_func_node:iter_children() do
                            if child:type() == "identifier" or child:type() == "name" then
                                name_node = child
                                break
                            end
                        end

                        local containing_pos
                        -- LSP Positions are 0-based, Lua and vim expect 1-based
                        -- if we found a name use it, it helps ts to find references easier. If the function was for example anonymous or other stuff happened default to funcstart
                        if name_node then
                            local name_row, name_col = name_node:start()
                            containing_pos = {name_row + 1, name_col}
                            utils.debug_print(config, string.format("    Using name position: %d:%d", containing_pos[1], containing_pos[2]))
                        else
                            -- Fallback to function start
                            local start_row, start_col = containing_func_node:start()
                            containing_pos = {start_row + 1, start_col}
                            utils.debug_print(config, string.format("    Using fallback position: %d:%d", containing_pos[1], containing_pos[2]))
                        end

                        -- Recursively trace upward from containing functions name
                        trace_upward(ref_bufnr, containing_pos, containing_func_name, new_path, depth + 1)
                    else
                        -- Recterm
                        utils.debug_print(config, "    No containing function found")
                    end
                end
            else
                utils.debug_print(config, "    File excluded")
            end
        end
    end

    -- Start tracing with initial path-entry (create table<pathenries> of tables<pathenty>)
    local initial_path = {{
        file = vim.api.nvim_buf_get_name(bufnr),
        line = pos[1],
        col = pos[2],
        function_name = function_name,
        calls = nil,
    }}

    trace_upward(bufnr, pos, function_name, initial_path, 0)

    return all_paths
end

return M
