-- ADR 0235: the companion's real autorun/client/nativeloader_leftovers_popup.lua and nativeloader/leftovers_window.lua
-- in a mocked client realm (data folder, game folder, the loader's journal, translations, timers, VGUI). See the
-- adjacent .md. Usage: luajit <this> <repo> <scenario>
local root, scenario = ...
local lib = dofile(root .. "/tools/tests/leftovers_test_lib.lua")
local POPUP = root .. "/companion/nativeloader/lua/autorun/client/nativeloader_leftovers_popup.lua"
local WINDOW = root .. "/companion/nativeloader/lua/nativeloader/leftovers_window.lua"
local STATE = "nativeloader_companion/leftovers_state.json"
local DISMISSED = "nativeloader_companion/leftovers_popup.txt"
local JOURNAL = "native-loader/state.json"
local RELEASES = "https://github.com/SheepyLord/Gmod-Workshop-RTX-Remix/releases/latest"
local NOW = 1800000000

local function eq(x, y, what) if x ~= y then error((what or "value") .. ": expected " .. tostring(y) .. ", got " .. tostring(x), 2) end end

local data, base, hooks, opened, clipboard = {}, {}, {}, {}, {}
local vgui, record = lib.fakeVgui()
local env = setmetatable({}, { __index = _G })
env._G = env
env.CLIENT = true
env.os = { time = function() return NOW end }
env.istable = function(v) return type(v) == "table" end
env.isstring = function(v) return type(v) == "string" end
env.isfunction = function(v) return type(v) == "function" end
env.IsValid = function(v) return type(v) == "table" and v.valid ~= false end
env.Color = function(r, g, b, a) return { r = r, g = g, b = b, a = a or 255 } end
env.ScrW = function() return 3840 end
env.ScrH = function() return 2160 end
env.surface = { CreateFont = function() end, SetDrawColor = function() end, DrawRect = function() end }
env.draw = { RoundedBox = function() end }
env.vgui = vgui
env.gui = { OpenURL = function(url) opened[#opened + 1] = url end }
env.SetClipboardText = function(text) clipboard[#clipboard + 1] = text end
env.util = { JSONToTable = lib.decode }
env.NativeLoaderRTXStart = function() return scenario == "rtx" end
env.game = { SinglePlayer = function() return scenario ~= "remote" and scenario ~= "host" end }
env.LocalPlayer = function() return { valid = true, IsListenServerHost = function() return scenario == "host" end } end
env.GetConVar = function(name)
    if name == "gmod_language" then return { GetString = function() return scenario == "french" and "fr" or "en" end } end
    return nil
end
env.hook = {
    Add = function(event, id, fn) hooks[event] = hooks[event] or {} hooks[event][id] = fn end,
    Remove = function(event, id) if hooks[event] then hooks[event][id] = nil end end,
}
env.timer = { Simple = function(_, fn) fn() end }
env.file = {
    Exists = function(path, where)
        if where == "BASE_PATH" then
            eq(path, "bin/win64/winmm.dll", "the game folder file asked")
            return scenario == "loader"
        end
        if where == "LUA" then return path == "nativeloader/i18n_data.lua" end
        if where == "DATA" then return data[path] ~= nil end
        error("unexpected file.Exists " .. tostring(path) .. " " .. tostring(where))
    end,
    Read = function(path, where)
        if where == "DATA" then return data[path] end
        if where == "BASE_PATH" then return base[path] end
        error("unexpected file.Read " .. tostring(path) .. " " .. tostring(where))
    end,
    Write = function(path, text) data[path] = text end,
    CreateDir = function() end,
}
env.include = function(path)
    if path == "nativeloader/i18n_data.lua" then
        return { fr = { ["RTX Remix is still in this game, but its loader is gone"] = "FR toujours là" } }
    end
    eq(path, "nativeloader/leftovers_window.lua", "include")
    local chunk = assert(loadfile(WINDOW))
    setfenv(chunk, env)
    return chunk()
end

-- The loader's journal: the package's files in each place, another package's beside them.
local function journal()
    local files = {}
    for _, path in ipairs({ "garrysmod/addons/remixbinary/lua/autorun/cl_rtx.lua", "garrysmod/addons/nativeloader/addon.json",
        "garrysmod/addons/!advanced_material_editor/lua/x.lua", "garrysmod/lua/bin/gmsv_nlrtxclient_win64.dll",
        "garrysmod/lua/bin/gmcl_RTXFixesBinary_win64.dll", "rtx-remix/mods/base_mod/mod.usda",
        "rtx-remix/mods/nativeloader_ui/startup_message.txt", "garrysmod/data/remix_map_configs/default.txt",
        "native-loader/packages/gmod-rtx-remix/1/native/manifest.json" }) do
        files[#files + 1] = { path = path, package = "gmod-rtx-remix" }
    end
    files[#files + 1] = { path = "garrysmod/addons/house_rtx/lua/a.lua", package = "modern-house-rtx" }
    files[#files + 1] = { path = "rtx-remix/mods/house/mod.usda", package = "modern-house-rtx" }
    return lib.encode({ schema = 1, current = { files = files } })
end

local function setState(outcome, why, at)
    data[STATE] = lib.encode({ outcome = outcome, error = why, at = at or NOW - 20 })
end

-- What each scenario finds.
if scenario == "refused" or scenario == "french" or scenario == "host" or scenario == "remote" or scenario == "click" then
    setState("refused", "another Garry's Mod runs from this folder")
    base[JOURNAL] = journal()
elseif scenario == "removed" or scenario == "partly" then
    setState(scenario == "removed" and "removed" or "partly removed")
    base[JOURNAL] = journal()
elseif scenario == "stale" then
    setState("removed", nil, NOW - 3600)
    base[JOURNAL] = journal()
elseif scenario == "no-journal" then
    setState("not needed", "the loader has deployed nothing here (no native-loader/state.json)")
elseif scenario == "dismissed" then
    setState("refused", "another Garry's Mod runs from this folder")
    base[JOURNAL] = journal()
    data[DISMISSED] = "dismissed\n"
elseif scenario == "no-state" then
    base[JOURNAL] = journal()
end

local chunk = assert(loadfile(POPUP))
setfenv(chunk, env)
chunk()

local function arrive()
    for _, fn in pairs(hooks.InitPostEntity or {}) do fn() end
end
local function window() return record.frames[#record.frames] end
local function has(texts, text)
    for _, t in ipairs(texts) do if t == text then return true end end
    return false
end

if scenario == "rtx" or scenario == "loader" then
    eq(hooks.InitPostEntity, nil, "the hook")
elseif scenario == "remote" or scenario == "removed" or scenario == "partly" or scenario == "dismissed" then
    arrive()
    eq(#record.frames, 0, "windows")
elseif scenario == "refused" or scenario == "host" or scenario == "french" or scenario == "stale" or scenario == "no-state" or scenario == "click" then
    arrive()
    eq(#record.frames, 1, "windows")
    local frame = window()
    eq(frame.popup, true, "the window takes the mouse")
    local texts = record.texts(frame)
    eq(texts[1], scenario == "french" and "FR toujours là" or "RTX Remix is still in this game, but its loader is gone", "the title")
    assert(has(texts, "The native loader (bin\\win64\\winmm.dll) was removed while RTX Remix's files stayed in this game. Without the loader, RTX Remix can neither start nor remove itself, so parts of it may still show or look wrong."), "the explanation")
    if scenario == "stale" or scenario == "no-state" then
        for _, t in ipairs(texts) do assert(not t:find("It could not remove itself now", 1, true), "a reason from another game") end
    else
        assert(has(texts, "It could not remove itself now: another Garry's Mod runs from this folder."), "the server's reason")
    end
    assert(has(texts, "Recommended: put the native loader back"), "the recommendation")
    assert(has(texts, "1. Download winmm.dll from the latest release (Open the release page) and put it in GarrysMod\\bin\\win64."))
    assert(has(texts, "Delete these folders from GarrysMod\\garrysmod\\addons: !advanced_material_editor, nativeloader, remixbinary"), "the add-ons, sorted, the package's only")
    assert(has(texts, "Delete these files from GarrysMod\\garrysmod\\lua\\bin: gmcl_RTXFixesBinary_win64.dll, gmsv_nlrtxclient_win64.dll"), "the modules")
    assert(has(texts, "Delete these folders from GarrysMod\\rtx-remix\\mods: base_mod, nativeloader_ui"), "the package's mods only")
    assert(has(texts, "Delete these folders from GarrysMod\\garrysmod\\data: remix_map_configs"), "the data folders")
    assert(has(texts, "Last, delete GarrysMod\\native-loader. Your own files the loader had moved aside are in its backup folder: take back what you need first."))
    local buttons = record.buttons(frame)
    eq(#buttons, 4, "the buttons")
    eq(buttons[1].text, "Open the release page", "button 1")
    eq(buttons[2].text, "Copy these steps", "button 2")
    eq(buttons[3].text, "Don't show this again", "button 3")
    eq(buttons[4].text, "Close", "button 4")
    if scenario == "click" then
        buttons[1].DoClick()
        eq(opened[1], RELEASES, "the release page")
        eq(frame.valid, true, "the window stays after opening the page")
        buttons[2].DoClick()
        assert(clipboard[1] and clipboard[1]:find("Recommended: put the native loader back", 1, true)
            and clipboard[1]:find(RELEASES, 1, true), "the steps on the clipboard")
        eq(buttons[2].text, "Copied", "the copy button says so")
        buttons[3].DoClick()
        eq(data[DISMISSED], "dismissed\n", "Don't show this again remembered")
        eq(frame.valid, false, "the window closed")
    end
elseif scenario == "no-journal" then
    arrive()
    local texts = record.texts(window())
    assert(has(texts, "The loader's record of what it installed is gone. Delete the RTX Remix folders from GarrysMod\\garrysmod\\addons (nativeloader, remixbinary and the others it added), its files from GarrysMod\\garrysmod\\lua\\bin and its mods from GarrysMod\\rtx-remix\\mods; the uninstall steps on GitHub list them: https://github.com/SheepyLord/Gmod-Workshop-RTX-Remix#uninstalling"), "the steps without a journal")
    for _, t in ipairs(texts) do assert(not t:find("Delete these folders from", 1, true), "a list without a journal") end
elseif scenario == "window-paths" then
    -- The window writes nothing outside the companion's data folder, whatever a spec says.
    local show = env.include("nativeloader/leftovers_window.lua").Show
    for _, path in ipairs({ "../cfg/autoexec.cfg", "nativeloader_companion/../x.txt", "other/x.txt" }) do
        local frame = show({ title = "t", buttons = { { text = "x", dismiss = path } } })
        record.buttons(frame)[1].DoClick()
        eq(data[path], nil, "written to " .. path)
        eq(frame.valid, false, "closed")
    end
    local frame = show({ title = "t", buttons = { { text = "x", url = "file:///c:/windows" } } })
    record.buttons(frame)[1].DoClick()
    eq(#opened, 0, "a page that is not https")
else
    error("unknown scenario " .. tostring(scenario))
end
print("PASS " .. scenario)
