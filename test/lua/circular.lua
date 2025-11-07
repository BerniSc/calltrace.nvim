local helper_loop1, helper_loop2

function helper_loop1(depth)
    print("helper_loop1, depth:", depth)
    if depth > 0 then
        helper_loop2(depth - 1)
    end
end

function helper_loop2(depth)
    print("helper_loop2, depth:", depth)
    if depth > 0 then
        helper_loop1(depth - 1)
    end
end

local function goal()
    helper_loop1(100)
    helper_loop2(100)
end

