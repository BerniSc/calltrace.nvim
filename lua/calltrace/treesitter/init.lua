-- Treesittersetup for calltrace plugin

local M = {}

local utils = require('calltrace.utils')

-- Extract the name-node of a functionnode
-- Needed as for example Lua and its moduleglobal functions hide behind dot_index_expression etc, we have to extract the ACTUAL functionnode from that
-- If we get the functionnode found by LSP its first identifier would be M. instead of what we really want, therefore reference-following would break
function M.find_name_node(func_node)
    if not func_node then
        return nil
    end

    -- Try to find identifier/namechild by iterating over all children until we reach the correct one.
    -- Map for different languages and their Tricks here (can find them by :InspectTree)
    for child in func_node:iter_children() do
        local child_type = child:type()

        -- Direct identifier - Can come before f.e. lua-check as initial check will not show identifier but dot_index_expression
        if child_type == "identifier" or child_type == "name" then
            return child
        end

        -- Handle Lua module functions (M.function_name) -> TSTree should be like this:
        --     name: (dot_index_expression ; [73, 9] - [73, 18]
        --       table: (identifier) ; [73, 9] - [73, 10]
        --       field: (identifier)) ; [73, 11] - [73, 18]   <---- We Want this!
        if child_type == "dot_index_expression" then
            -- Extract "field" (function_name) from M.function_name
            for subchild in child:iter_children() do
                if subchild:type() == "identifier" and subchild ~= child:child(0) then
                    return subchild
                end
            end
        end

        -- C/C++: function_declarator may contain field_identifier or identifier if in class/struct
        --     (function_definition ; [21, 4] - [24, 5]
        --       type: (primitive_type) ; [21, 4] - [21, 8]
        --       declarator: (function_declarator ; [21, 9] - [21, 24]
        --         declarator: (field_identifier) ; [21, 9] - [21, 22]    <---- We want this
        --         parameters: (parameter_list)) ; [21, 22] - [21, 24]
        --       body: (compound_statement ; [22, 4] - [24, 5]
        if child_type == "function_declarator" then
            for subchild in child:iter_children() do
                local sub_type = subchild:type()
                -- Get name of qualified_identifier - Qualified Identifier is functioncall prefixed by namespace or classdefined func
                -- for example "void DUMMY::functionname() {" would produce a qualified_identifier as functiondefinition, need to match this too
                if sub_type == "qualified_identifier" then
                    local child_count = subchild:named_child_count()
                    if child_count > 0 then
                        local last = subchild:named_child(child_count - 1)
                        if last and (last:type() == "identifier" or last:type() == "field_identifier") then
                            return last
                        end
                    end
                elseif sub_type == "field_identifier" or sub_type == "identifier" then
                    return subchild
                end
            end
        end

        -- JS/TS methods (stuff inside of classes/objects) is called differently, look for this as well
        if child_type == "property_identifier" then
            return child
        end

        -- TODO Add other languagestuff here as well as soon as I learn it
    end

    return nil
end

-- Get functionnode surrounding given position
function M.get_fun_surrounding_pos(bufnr, row, col)
    if not pcall(require, "nvim-treesitter") then
        vim.notify("nvim-treesitter is required", vim.log.levels.ERROR)
        return nil
    end

    local parser = vim.treesitter.get_parser(bufnr)
    if not parser then
        return nil
    end

    -- get first found tree -> should only be one? TODO make more stable
    local tree = parser:parse()[1]
    local root = tree:root()

    -- Get node at cursorposition (0-indexed for treesitter)
    -- gets "smallest" node spanning the position (starts at or before and ends after)
    local node = root:named_descendant_for_range(row - 1, col, row - 1, col)

    -- Traverse up to find functiondec/def
    while node do
        local node_type = node:type()

        -- Common functionnode types across languages
        -- TODO: Expand list based on languagesupport
        if vim.tbl_contains({
            "function_declaration",
            "function_definition",
            "method_declaration",
            "method_definition",
            "function_item",        -- Rust
            "function",             -- Python
        }, node_type) then
            -- Found Function -> Exit early
            return node
        end

        -- AAAAaaand restart
        node = node:parent()
    end

    -- failed to find surrounding function -> maybe toplevel already?
    return nil
end

-- Extract alias from an import statement if it exists -> Forward resolve-responsibility to tracer
-- python for example allows aliased imports (import ... as ...), this breaks our referencecycle as we essentially "rename" dynamically.
-- this function checks if we are inside an aliased import and if yes returns name and node (needed for extracting new reference)
-- Returns: alias_name (string), alias_node or nil, nil
function M.get_import_alias(bufnr, row, col)
    local node = vim.treesitter.get_node({ bufnr = bufnr, pos = {row - 1, col} })
    if not node then return nil, nil end

    -- Walk up the tree to find aliased_import node
    -- TODO Check if we should exit early here. Might be better performancewise, wont bother for now
    while node do
        if node:type() == "aliased_import" then
            -- For Python: aliased_import has 'name' and 'alias' fields
            local alias_field = node:field("alias")
            if alias_field and alias_field[1] then
                local alias_name = vim.treesitter.get_node_text(alias_field[1], bufnr)
                return alias_name, alias_field[1]
            end
        end

        -- If we hit an importstatement but no alias, stop looking
        if node:type() == "import_from_statement" or node:type() == "import_statement" then
            return nil, nil
        end

        node = node:parent()
    end

    return nil, nil
end

-- Get functionname from functionnode
function M.get_function_name(bufnr, node, config)
    -- invalid node -> no name
    if not node then
        return nil
    end

    -- Try to find the name node using shared logic
    local name_node = M.find_name_node(node)
    if name_node then
        utils.debug_print(config, " found namenode " .. vim.treesitter.get_node_text(name_node, bufnr))
        return vim.treesitter.get_node_text(name_node, bufnr)
    end

    -- Fallback: try extracting from nodetext using regexstuff, kind of ugly, but if it saves us in some cases I will take it
    -- For this to work we take the first line and then put regex onto the basic "easy, typeless" syntaxmarkers
    local text = vim.treesitter.get_node_text(node, bufnr)
    if text then
        local first_line = vim.split(text, "\n")[1]
        local name = first_line:match("function%s+([%w_]+)") or
                     first_line:match("def%s+([%w_]+)") or
                     first_line:match("fn%s+([%w_]+)")
        if name then
            return name
        end
    end

    -- Fallfallback^^
    return "<anonymous>"
end

-- Get functionname the passed position is inside of (combines get_fun_surrounding_pos and get_function_name)
-- Returns not only the functionname found, but also the position of its node
function M.get_funcname_surrounding_pos(bufnr, row, col, config)
    local node = M.get_fun_surrounding_pos(bufnr, row, col)
    if not node then
        return nil
    end
    -- TODO Reuse existing name_node created in get_function_name
    local name = M.get_function_name(bufnr, node, config)
    local name_node = M.find_name_node(node)
    local pos = nil
    if name_node then
        local srow, scol = name_node:range()
        pos = { srow + 1, scol }
    end
    return { name = name, pos = pos }
end

-- check if node is a ctor call
local function is_ctor_call(node, config)
    -- C++ - Check if node is init_declarator
    if node:type() == "init_declarator" then
        -- TODO For now check if we do have args, this excludes default C'Tors
        for child in node:iter_children() do
            if child:type() == "argument_list" then
                return true
            end
        end
    end
    return false
end

-- Check if position is a functioncall
function M.is_function_call(bufnr, row, col, config)
    local parser = vim.treesitter.get_parser(bufnr)
    if not parser then
        return false
    end

    -- get first found tree -> should only be one? TODO make more stable
    local tree = parser:parse()[1]
    local root = tree:root()

    -- Get node at 0-indexed position for TS
    -- gets "smallest" node spanning the position (starts at or before and ends after)
    local node = root:named_descendant_for_range(row - 1, col, row - 1, col)

    local node_type = nil
    while node do
        node_type = node:type()

        -- Common callnodetypes TODO Add more once i find them
        if vim.tbl_contains({
            "call_expression",
            "function_call",
            "method_call",
            "call",                 -- Generic
            "invoke_expression",    -- C#
        }, node_type) then
            return true
        end

        -- C'tor calldetection
        if config.constructor_tracing and is_ctor_call(node, config) then
            return true
        end

        -- AAAAaaaaand restart^^
        node = node:parent()
    end

    -- Is no functioncall or I screwed it up and found new language where it should work but does not
    utils.debug_print(config, "    last nodetype was no functioncall:", node_type or "<None>")
    return false
end

-- Get call expression details
function M.get_call_details(bufnr, row, col, config)
    -- TODO: Extract function name being called, arguments, etc.
    utils.debug_print(config, "    SHOULD HAVE IMPLEMENTED THIS, DOOFUS")
    return {
        name = nil,
        args = {},
    }
end

-- Get the function being called at position
-- TODO Implement this later on. If we just get coordinates or even worse, get calls like
--  ```foo=bar()+baz()``` we would need something like this to determine the true "source" of the call I think
--  Also instead of saying "call on line 4" we then can say "called bar()" in the cotext above
--
function M.get_called_function_name(bufnr, row, col, config)
    utils.debug_print(config, "    SHOULD HAVE IMPLEMENTED THIS, DOOFUS")
    return nil
end

return M
