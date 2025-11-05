-- Treesittersetup for calltrace plugin

local M = {}

local utils = require('calltrace.utils')
local config = require('calltrace.config')

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

-- Get functionname from functionnode
function M.get_function_name(bufnr, node)
    -- invalid node -> no name
    if not node then
        return nil
    end

    -- Try to find identifier/name child by iterating over all children until we reach "identifier" or "name"
    for child in node:iter_children() do
        local child_type = child:type()

        -- Direct identifier
        if child_type == "identifier" or child_type == "name" then
            return vim.treesitter.get_node_text(child, bufnr)
        end

        -- C/C++ -> functionname is nested inside of "function_declarator" so we have to subchild
        if child_type == "function_declarator" then
            for subchild in child:iter_children() do
                if subchild:type() == "identifier" then
                    return vim.treesitter.get_node_text(subchild, bufnr)
                end
            end
        end

        -- JS/TS methods (stuff inside of classes/objects) is called differently, look for this as well
        if child_type == "property_identifier" then
            return vim.treesitter.get_node_text(child, bufnr)
        end

        -- TODO Add other languagestuff here as well as soon as I learn it
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
function M.get_funcname_surrounding_pos(bufnr, row, col)
    local node = M.get_fun_surrounding_pos(bufnr, row, col)
    if not node then
        return nil
    end
    return M.get_function_name(bufnr, node)
end

-- Check if position is a functioncall
function M.is_function_call(bufnr, row, col)
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

        -- AAAAaaaaand restart^^
        node = node:parent()
    end

    -- Is no functioncall or I screwed it up and found new language where it should work but does not
    utils.debug_print(config, "    last nodetype was no functioncall:", node_type or "<None>")
    return false
end

-- Get call expression details
function M.get_call_details(bufnr, row, col)
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
function M.get_called_function_name(bufnr, row, col)
    local parser = vim.treesitter.get_parser(bufnr)
    if not parser then
        return nil
    end

    -- get first found tree -> should only be one? TODO make more stable
    -- Also use 0-based indexing for TS
    local tree = parser:parse()[1]
    local root = tree:root()
    local node = root:named_descendant_for_range(row - 1, col, row - 1, col)

    -- Find callexpressionnode
    -- TODO Add more once I find them
    while node and not vim.tbl_contains({
        "call_expression",
        "function_call",
        "method_call",
    }, node:type()) do
        node = node:parent()
    end

    if not node then
        return nil
    end

    local child_type = nil
    -- Extract functionname from call
    for child in node:iter_children() do
        child_type = child:type()

        if child_type == "identifier" then
            return vim.treesitter.get_node_text(child, bufnr)
        end

        -- Handle methodcalls (like object.method()) -> contains name embedded in wrapper -> subchild
        -- TODO Add more langs
        if child_type == "member_expression" or child_type == "field_expression" then
            for subchild in child:iter_children() do
                if subchild:type() == "property_identifier" or subchild:type() == "field_identifier" then
                    return vim.treesitter.get_node_text(subchild, bufnr)
                end
            end
        end
    end

    utils.debug_print(config, "    could not retrieve functionname for:", child_type or "<None>")
    return nil
end

return M
