# calltrace.nvim

Trace function call paths from any point in your code back to a referencefunction using LSP and Treesitter.

> **Note**: This plugin is still in very early development. Some/Many features are missing or incomplete.

## What it does

Set a referencepoint (like `main()` or a any other entrypoint), then trace a backward from any function to see how execution could reach that reference point.
The Plugin uses your existing LSP setup and Treesitter for the analysis.

The following image for example demonstrates an exemplary tracking and its result:

![Exemplary use of calltrace plugin](./doc/images/Calltrace_Example_Screenshot.png)

For example if we want to see how/if `helper_function` gets called from `main` and what paths it could take we could trace from `main` to `helper_function`. 

For the different UI-Options take a look at [these images](./doc/images/UIOptions). Telescope does require `telescope` to be installed and set up, but it does provide a cool live preview while looking into the path.

## Installation

### Configoptions
Default configuration of the plugin is:
```lua
M.defaults = {
    -- Maximum Depth to trace (prevent infinite loops)
    max_depth = 20,

    -- Displayoptions
    display = {
        -- "quickfix" | "float" | "telescope"
        -- using float as default as it has less requirements than telescope, but telescope is a lot cooler^^
        backend = "float",
        -- Highlight referencepoint in signcol
        highlight_reference = true,
    },

    -- Performance options
    timeout = 5000,                 -- ms for LSP requests
    cache_results = true,           -- TODO Implement

    -- Filtering - exclude certain files/dirs from trace
    exclude_patterns = {
        "node_modules/",
        "*/test/*",
    },

    -- UI-Customization
    icons = {
        entry = "📍",
        target = "",
        call = "󰃀",
        path = "→",         -- Might also hold strings like "calls" etc
    },

    loop_detection = {
        -- "simplified" checks if function in path already, if yes it detects a loop, "complete" detects funtionFrom->FunctionTo pairs
        -- (in a call foo->bar->baz->bar->goal as well as foo->bar->goal "complete" would display all, "simplified" one)
        mode = "simplified",    -- "simplified" | "complete"
    },

    -- trace constructorcalls as well as functions?
    constructor_tracing = true,

    -- Debugmode
    debug = false,
}
```

### packer.nvim
```lua
use {
    'BerniSc/calltrace.nvim',
    config = function()
        require'calltrace'.setup({
            display = {
                backend = "telescope",
            },
        })
    end
}
```
or with default configs:
```lua
use 'BerniSc/calltrace.nvim'
```

## Usage

1. Put cursor on your entry function (ideally the name of the function) and run `:CalltraceSetReference`
2. Put cursor on any other function (again, ideally the name) and run `:CalltraceTrace`
3. View the call paths in configured UI (or floating window)

### Neovim Commands
- `:CalltraceSetReference` - Set reference point at cursor
- `:CalltraceTrace` - Trace from cursor to reference
- `:CalltraceClearReference` - Clear reference point
- `:CalltraceShowReference` - Jump to reference point
- `:CalltraceToggleDebug` - Enable Debug logging

### Lua API
```lua
local calltrace = require("calltrace")

calltrace.setup({
    max_depth = 50,
    display = { backend = "telescope" },
    timeout = 5000,
})

calltrace.set_reference()
calltrace.trace()

-- Also supports directly overriding configs for single operations like:
require('calltrace').trace({ display = { backend = "telescope" } })
```

## Use Cases

- **Understanding Legacy Code**: Discover how deeply nested functions fit into the bigger picture
- **Debugging**: Trace execution flow to understand call hierarchies
- **Code Review**: Verify that functions are called from expected entry points
- **Documentation**: Generate call path documentation for complex systems
- **Refactoring**: Identify all paths to a function before making changes

## Current Status

**Working:**
- ✅ Basic reference point management
- ✅ LSP-based reference finding
- ✅ Treesitter function detection
- ✅ Backward tracing algorithm
- ✅ Floating window display as well as quickfix and telescopedisplay (both provide referencejumping, telescope live preview as well)
- ✅ Multi-path support
- ✅ Loop-Detection to prevent infinite loops
- ✅ Following of aliased imports (at least in python)

**Todo:**
- [ ] Implement Resultcaching
- [ ] Implement the other displaybackends (split)
- [ ] Cross-file optimization
- [ ] Better language support
- [ ] Performance improvements 
    - [ ] async calls
    - [ ] caching
- [ ] More tests

## Requirements

- Neovim >= I dont know yet, will have to look into it
- LSP server for your language
- nvim-treesitter with appropriate parsers

Tested with Python and basic Lua, should work with most languages that have proper LSP and Treesitter support.
