# Moduler

A Lua library for [MoonLoader](https://blast.hk/moonloader/) that allows you to split your SA-MP scripts into organized, reusable modules and submodules without changing your code structure.

- **Split scripts into modules** - Organize your code into separate files
- **Submodule support** - Extract specific submodules from modules, specified by `-- Moduler: submodule_name` before its content
- **Two loading methods** - Choose between traditional file-based loading or runtime loading
- **Build file generation** - Creates readable merged script


## Example Structure
```
moonloader/
├── lib/
│   ├── moduler.lua
│   └── moduler_loader.lua (optional)
├── moduler/
│   └── YourScript/
│       ├── module1.lua
│       ├── module2.lua
│       └── ...
└── YourScript.lua
```


## Usage

### Loading Entire Modules

```lua
moduler("module_name")
```

Loads all code from `moonloader/moduler/YourScript/module_name.lua`

### Loading Submodules

```lua
moduler("module_name.submodule_name")
```

Loads only the `submodule_name` content from the module. Good for organizing multiple submodules in one file (module).


## Example

### Your Base Script

```lua
script_name("MyScript")

require("moduler")

local ev = require("samp.events")

function main()
    if not isSampLoaded() or not isSampfuncsLoaded() then return end
    while not isSampAvailable() do wait(0) end
    
    moduler("commands.register")   -- Load a submodule

    moduler("commands.unregister") -- Load a submodule
    
    while true do wait(0) end
end

moduler("events") -- Load entire module
```

### Your Modules (with/without Submodules)

Create a folder `moonloader/moduler/YourScript/` and add your modules:

```lua
-- moonloader/moduler/YourScript/commands.lua

-- Moduler: register
sampRegisterChatCommand("test", function()
    sampAddChatMessage("Test command works!", -1)
end)

-- Moduler: unregister
sampUnregisterChatCommand("test")
```

```lua
-- moonloader/moduler/YourScript/events.lua

function ev.onServerMessage(color, text)
    print("Server message: "..text)
end
function ev.onSendCommand(cmd)
    print("Command sent: "..cmd)
end
```

### Output Merged Built File

```
moonloader/moduler/YourScript_moduler.lua
```

This file shows how your code looks after module injection.

Example output:
```lua
function main()
    if not isSampLoaded() or not isSampfuncsLoaded() then return end
    while not isSampAvailable() do wait(0) end

    --[[START OF MODULER: commands.register]]
    sampRegisterChatCommand("test", function()
        sampAddChatMessage("Test command works!", -1)
    end)
    --[[END OF MODULER: commands.register]]

    --[[START OF MODULER: commands.unregister]]
    sampUnregisterChatCommand("test")
    --[[END OF MODULER: commands.unregister]]

    while true do wait(0) end
end

--[[START OF MODULER: events]]
function ev.onServerMessage(color, text)
    print("Server message: "..text)
end
function ev.onSendCommand(cmd)
    print("Command sent: "..cmd)
end
--[[END OF MODULER: events]]
```


## Configuration

At the top of `moduler.lua`, you can configure the loading method:

```lua
local useRuntimeMethod = false  -- Set to true for runtime loading (Not recommended)
```

### Default Method
- Creates a merged script file
- Unloads your script and reloads from the final built file in `moonloader/moduler`
- Requires `moduler_loader.lua` in `moonloader/lib/`

### Runtime Method (Not recommended)
- Instant loading in runtime - no script reload required
- Still creates a merged script file for preview
- * Won't work if you call anything in your modules that are predefined in the base script itself

**Default method configuration:**
```lua
local forceKill = true           -- Immediately kill caller script, with error("_FORCE_KILL_THE_SCRIPT_")
local sendThroughCommand = false -- Use a chat command for passing the load request to the loader, or direct import
```


## Limitations

- Submodule nesting limited to one level (`module.submodule`, not `module.submodule.subsub`)
- Compiled (`.luac`) modules are not supported. Module files must be plain Lua scripts


## Note

- For using the minified versions, consider renaming `moduler.min.lua` and `moduler_loader.min.lua` to `moduler.lua` and `moduler_loader.lua` before usage.
- Added a modified version of `SF Integration.lua` in the repo, in case you been using that and the error used for force killing the caller script was annoying (Minifies the error message)
