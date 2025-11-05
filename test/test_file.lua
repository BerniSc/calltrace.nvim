-- Test file for calltrace.nvim

local function helper_function()
    print("Helper function")
end

local function intermediate_function()
    helper_function()
    print("Intermediate function")
end

local function another_intermediate()
    helper_function()
end

local function final_nail()
    intermediate_function()
end

local function main()
    another_intermediate()
    final_nail()
    print("Main function")
end

-- Entry point
main()
