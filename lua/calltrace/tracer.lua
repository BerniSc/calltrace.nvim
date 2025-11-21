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

    -- Recursive trace function
    -- Takes:
    --      Buffernumber: int
    --      position of the functionname (unless failed to find it, then def): table<int,int>
    --      functionname: string
    --      filename: string
    --      tracepath: table<path_entry>
    --      recursiondepth: int
    --      Visited nodes per Path. This is to prevent loops while still allowing for revisiting the same function on different path. 
    --          We could also filter current-path with loop, but rather use table with O(1) lookup, feels better: table<string>
    --      path_key -> filename:funcname to build incremental string for Loopdetection: string
    local function trace_upward(current_bufnr, current_pos, current_name, current_file_name, path, depth, path_set, path_key)
        -- Exit early -> Reached max rec depth
        if depth > max_depth then
            utils.debug_print(config, "Max depth reached")
            -- No need for early cleanup here, we dont set a key in path_set here, I think this should be alright
            return
        end

        -- Build key to identify call uniquely for this recursive branch. We want to allow using the same functionnode multiple times if it is 
        -- part of multiple paths (like A->C->D as well as A->B->C->D) yet we still need to block endless loops (like A->B->A->B)
        local current_node = current_file_name .. ":" .. current_name

        local new_path_key
        -- TODO Maybe add line/col here as well? Lets see
        if config.loop_detection.mode == "complete" then
            -- Doing this we classify only functionFrom>functionTo in each branch as a loop
            -- This leaves more options in the same branch like foo->bar->baz->bar->main and foo->bar->main
            new_path_key = (path_key .. ">" .. current_node)
        else
            -- this reduces the example above as we now say bar cant be visited twice -> recursion less visible
            new_path_key = current_node
        end

        if path_set[new_path_key] then
            utils.debug_print(config, "Cycle detected in current path:", new_path_key)

            -- Free path from dict in this recursive branch to allow other paths to include the node again
            -- Freeing here also allows for callstructure like main->foo->bar->baz to match as well as main->foo->baz
            -- as the foo->main from the first match will be reset for siblings again
            -- see Notes 21.11.2025 - GN
            path_set[new_path_key] = nil
            return
        end
        path_set[new_path_key] = true

        utils.debug_print(config, string.format("Depth %d: Tracking %s at %s:%d", depth, current_name, vim.api.nvim_buf_get_name(current_bufnr), current_pos[1]))

        -- Check wheter we reached refpoint
        if current_file_name == reference_point.file and current_name == reference_point.name then
            -- Found complete path
            utils.debug_print(config, "Found path to reference point")
            -- path changes recursively, without deepcopy it would still mutate what we write into all_paths
            table.insert(all_paths, vim.deepcopy(path))

            -- Free path from dict in this recursive branch to allow other paths to include the node again
            -- Freeing here also allows for callstructure like main->foo->bar->baz to match as well as main->foo->baz
            -- as the foo->main from the first match will be reset for siblings again
            -- see Notes 21.11.2025 - GN
            path_set[new_path_key] = nil
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

                -- NOTE Can be a functioncall or an aliased functioncall, first one (ideally) we handle here, aliascheck in else
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

                            -- Free path from dict in this recursive branch to allow other paths to include the node again
                            -- Freeing here also allows for callstructure like main->foo->bar->baz to match as well as main->foo->baz
                            -- as the foo->main from the first match will be reset for siblings again
                            -- see Notes 21.11.2025 - GN
                            path_set[new_path_key] = nil
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

                        -- Get pos of function NAME (not start of definition), otherwise we might follow the wrong function
                        local name_node = ts.find_name_node(containing_func_node)

                        local containing_pos
                        -- LSP Positions are 0-based, Lua and vim expect 1-based
                        -- if we found a name use it, it helps ts to find references easier. If the function was for example anonymous or other stuff happened default to funcstart
                        if name_node then
                            local name_row, name_col = name_node:start()
                            containing_pos = {name_row + 1, name_col}
                            utils.debug_print(config, string.format("    Using name position: %d:%d", containing_pos[1], containing_pos[2]))
                        else
                            -- Fallback to function start - might very well fail, but still better than just giving up^^
                            local start_row, start_col = containing_func_node:start()
                            containing_pos = {start_row + 1, start_col}
                            utils.debug_print(config, string.format("    Using fallback position: %d:%d", containing_pos[1], containing_pos[2]))
                        end

                        -- Recursively trace upward from containing functions name
                        -- we pass current_node (filename:function...) instead of new_path_key (current_node(old)->current_node)
                        -- as we dont want to accumulate there
                        -- a->b->a as a key would be different from a->b->a->b etc so we would not be able to detect anything there
                        trace_upward(ref_bufnr, containing_pos, containing_func_name, ref_file, new_path, depth + 1, path_set, current_node)
                    else
                        -- Recterm
                        utils.debug_print(config, "    No containing function found")
                    end
                else
                    -- Check if this is an aliased import
                    local alias, alias_node = ts.get_import_alias(ref_bufnr, ref_row, ref_col)
                    if alias then
                        utils.debug_print(config, string.format("    Found import alias: %s -> %s", current_name, alias))

                        -- Get the position of the alias identifier itself
                        -- TODO Check NIL?
                        local alias_row, alias_col = alias_node:start()

                        -- Add alias info to path entry > display renaming operation in menus
                        local new_path_entry = {
                            file = ref_file,
                            line = ref_row,
                            col = ref_col,
                            function_name = alias, -- real/original name
                            calls = current_name,
                            alias = current_name,  -- current_name is alias used in code
                        }
                        local new_path = vim.deepcopy(path)
                        table.insert(new_path, new_path_entry)

                        -- Continue tracing from the alias position
                        -- we pass current_node (filename:function...) instead of new_path_key (current_node(old)->current_node)
                        -- as we dont want to accumulate there
                        -- a->b->a as a key would be different from a->b->a->b etc so we would not be able to detect anything there
                        trace_upward(ref_bufnr, {alias_row + 1, alias_col}, alias, ref_file, new_path, depth, path_set, current_node)
                    else
                        utils.debug_print(config, "    Reference is not a call and not an aliased import, skipping")
                    end
                end
            else
                utils.debug_print(config, "    File excluded")
            end
        end
        -- Free path from dict in this recursive branch to allow other paths to include the node again
        path_set[new_path_key] = nil
    end

    -- Start tracing with initial path-entry (create table<pathenries> of tables<pathenty>)
    local initial_path = {{
        file = vim.api.nvim_buf_get_name(bufnr),
        line = pos[1],
        col = pos[2],
        function_name = function_name,
        calls = nil,
    }}
    local initial_path_set = {}

    trace_upward(bufnr, pos, function_name, vim.api.nvim_buf_get_name(bufnr), initial_path, 0, initial_path_set, "")

    return all_paths
end

return M
