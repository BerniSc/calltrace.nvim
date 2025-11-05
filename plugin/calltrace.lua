-- Lua-Based Plugin Loader -> We are Neovim exclusive anyhow (TS, LSP etc.) and can therefore use this without feeling bad
-- This file is optional if you're using the Vim script version

if vim.g.loaded_calltrace then
    return
end
vim.g.loaded_calltrace = true

-- Create commands
vim.api.nvim_create_user_command('CalltraceSetReference', function()
    require('calltrace').set_reference()
end, { desc = 'Set calltrace reference point' })

vim.api.nvim_create_user_command('CalltraceShowReference', function()
    require('calltrace').show_reference()
end, { desc = 'Show current reference point' })

vim.api.nvim_create_user_command('CalltraceClearReference', function()
    require('calltrace').clear_reference()
end, { desc = 'Clear calltrace reference point' })

vim.api.nvim_create_user_command('CalltraceTrace', function()
    require('calltrace').trace()
end, { desc = 'Trace to reference point' })

vim.api.nvim_create_user_command('CalltraceToggleCache', function()
    require('calltrace').toggle_cache()
end, { desc = 'Toggle result caching' })

vim.api.nvim_create_user_command('CalltraceToggleDebug', function()
    require('calltrace').toggle_debug()
end, { desc = 'Toggle debug mode' })
