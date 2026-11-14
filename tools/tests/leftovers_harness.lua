-- ADR 0206. Two harnesses in one, see the adjacent .md. Usage:
--   luajit <this> <repo> trigger <scenario>   the companion's real autorun/server/nativeloader_leftovers.lua in a
--                                             mocked server realm, with a mocked RTX client module
--   luajit <this> <repo> gate <file> <rtx>    an autorun file whose first line of code is the RTX-start gate, in an
--                                             environment that fails on any other global; rtx is "yes" or "no"
local root, mode, a, b = ...

local function eq(x, y, what) if x ~= y then error((what or "value") .. ": expected " .. tostring(y) .. ", got " .. tostring(x), 2) end end

if mode == "gate" then
    local path, rtx = a, b == "yes"
    local chunk = assert(loadfile(path))
    local touched
    local env = setmetatable({}, {
        __index = function(_, key)
            if key == "NativeLoaderRTXStart" then return function() return rtx end end
            if key == "NATIVELOADER_VERIFIED_MULTIPLAYER" then return nil end
            touched = touched or key
            error("touched " .. tostring(key), 2)
        end,
        __newindex = function(_, key) touched = touched or key error("set " .. tostring(key), 2) end,
    })
    setfenv(chunk, env)
    local ok, err = pcall(chunk)
    if rtx then
        -- Past the gate the file goes on to its own work, which this empty environment refuses.
        if ok or not touched then error("the file did nothing past the gate: " .. tostring(err)) end
    elseif not ok then
        error("a start without RTX ran past the gate: " .. tostring(err))
    end
    print("PASS gate " .. path .. " " .. b)
    return
end

local scenario = a
local SCRIPT = root .. "/companion/nativeloader/lua/autorun/server/nativeloader_leftovers.lua"
local REMOVED = "RTX Remix was removed from this game because its loader (bin/win64/winmm.dll) is gone. Restart Garry's Mod to finish."
local PARTLY = "RTX Remix was partly removed from this game because its loader (bin/win64/winmm.dll) is gone. Restart Garry's Mod; the console lists what stayed."

local hooks, required, commands, said, chat, removes = {}, {}, {}, {}, {}, 0
local results = {
    removed = { outcome = "removed", deleted = 12, restored = 1, former = 2, aside = 1, error = "",
        former_folder = "native-loader/backup/former-rtx/20261113T000000Z",
        aside_folder = "native-loader/backup/in-use/20261113T000000Z", notes = {}, restore = { { "r_3dsky", "1" } } },
    partly = { outcome = "partly removed", deleted = 3, restored = 0, former = 0, aside = 0, error = "",
        former_folder = "", aside_folder = "", notes = { "garrysmod/lua/bin/x.dll: could not be deleted yet" }, restore = {} },
    refused = { outcome = "refused", deleted = 0, restored = 0, former = 0, aside = 0, former_folder = "", aside_folder = "",
        error = "another Garry's Mod runs from this folder", notes = {}, restore = {} },
    ["not-needed"] = { outcome = "not needed", error = "the native loader is installed (bin/win64/winmm.dll)", notes = {},
        restore = {} },
}
local answer = results[scenario] or results.removed
if scenario == "french" then answer = results.removed end

local api = { Remove = function()
    removes = removes + 1
    if scenario == "module-error" then error("boom") end
    return answer
end }

local env = setmetatable({}, { __index = _G })
env._G = env
env.SERVER = true
env.istable = function(v) return type(v) == "table" end
env.isstring = function(v) return type(v) == "string" end
env.isfunction = function(v) return type(v) == "function" end
env.IsValid = function(v) return type(v) == "table" and v.valid ~= false end
env.game = { IsDedicated = function() return scenario == "dedicated" end, SinglePlayer = function() return true end }
env.NativeLoaderRTXStart = function() return scenario == "rtx-start" end
env.file = { Exists = function(path, where)
    if path == "bin/win64/winmm.dll" then
        eq(where, "BASE_PATH", "the loader's search path")
        return scenario == "loader-installed"
    end
    if path == "nativeloader/i18n_data.lua" then return where == "LUA" end
    error("unexpected file.Exists " .. tostring(path))
end }
env.include = function(path)
    eq(path, "nativeloader/i18n_data.lua", "include")
    return { fr = { [REMOVED] = "FR retiré", [PARTLY] = "FR en partie" } }
end
env.GetConVar = function(name)
    if name == "gmod_language" then return { GetString = function() return scenario == "french" and "fr" or "en" end } end
    return nil  -- nativeloader_language: the client realm has not made it yet
end
env.MsgN = function(text) said[#said + 1] = text end
env.hook = {
    Add = function(event, id, fn) hooks[event] = hooks[event] or {} hooks[event][id] = fn end,
    Remove = function(event, id) if hooks[event] then hooks[event][id] = nil end end,
}
env.require = function(name)
    required[#required + 1] = name
    if scenario == "no-module" then error("Module not found!") end
    rawset(env, "NativeLoaderLeftovers", api)
end
env.RunConsoleCommand = function(name, value) commands[#commands + 1] = name .. " " .. value end

local chunk = assert(loadfile(SCRIPT))
setfenv(chunk, env)
chunk()

local function said_with(part)
    for _, line in ipairs(said) do if line:find(part, 1, true) then return true end end
    return false
end
local function initialize()
    for _, fn in pairs(hooks.Initialize or {}) do fn() end
end
-- The player arrives: their first own move, after a forced one, is when the chat shows the notice.
local function arrive()
    local ply = { valid = true, IsListenServerHost = function() return true end,
                  ChatPrint = function(_, text) chat[#chat + 1] = text end }
    for _, fn in pairs(hooks.PlayerInitialSpawn or {}) do fn(ply) end
    local move = (hooks.SetupMove or {})[ply]
    if move then
        move(ply, ply, nil, { IsForced = function() return true end })
        eq(#chat, 0, "chat before the player's own move")
        move(ply, ply, nil, { IsForced = function() return false end })
    end
end

if scenario == "rtx-start" or scenario == "dedicated" or scenario == "loader-installed" then
    eq(hooks.Initialize, nil, "the Initialize hook")
    eq(#required, 0, "modules loaded")
elseif scenario == "no-module" then
    initialize()
    eq(#required, 1, "modules loaded")
    eq(required[1], "nlrtxclient", "module")
    eq(#said, 0, "console lines")
    eq(hooks.PlayerInitialSpawn, nil, "the arrival hook")
elseif scenario == "not-needed" or scenario == "module-error" then
    initialize()
    eq(removes, 1, "removal calls")
    eq(#said, 0, "console lines")
    eq(#commands, 0, "console commands")
    eq(hooks.PlayerInitialSpawn, nil, "the arrival hook")
elseif scenario == "refused" then
    initialize()
    assert(said_with("were not removed now: another Garry's Mod runs from this folder. The next local game tries again."), table.concat(said, "\n"))
    eq(#commands, 0, "console commands")
    eq(hooks.PlayerInitialSpawn, nil, "the arrival hook")
elseif scenario == "removed" or scenario == "french" then
    initialize()
    eq(hooks.Initialize and next(hooks.Initialize), nil, "the Initialize hook removes itself")
    assert(said_with("RTX Remix removed. 12 files deleted, 1 of yours put back."), table.concat(said, "\n"))
    assert(said_with("2 files of an earlier RTX installation kept in native-loader/backup/former-rtx/20261113T000000Z."))
    assert(said_with("1 files this game holds open moved to native-loader/backup/in-use/20261113T000000Z"))
    assert(said_with("Console settings put back: r_3dsky 1"))
    eq(#commands, 1, "console commands")
    eq(commands[1], "r_3dsky 1", "the restored setting")
    arrive()
    eq(#chat, 1, "chat lines")
    eq(chat[1], scenario == "french" and "FR retiré" or REMOVED, "the notice")
elseif scenario == "partly" then
    initialize()
    assert(said_with("RTX Remix partly removed."))
    assert(said_with("  garrysmod/lua/bin/x.dll: could not be deleted yet"))
    arrive()
    eq(chat[1], PARTLY, "the notice")
else
    error("unknown scenario " .. tostring(scenario))
end
print("PASS " .. scenario)
