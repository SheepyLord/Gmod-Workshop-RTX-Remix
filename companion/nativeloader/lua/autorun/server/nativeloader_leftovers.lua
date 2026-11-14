-- RTX a removed loader left in the game (ADR 0206). The loader removes the RTX package at the first start after it
-- goes, but only a start that runs the loader does: with bin/win64/winmm.dll deleted first, everything it deployed
-- stays, and Garry's Mod runs the package's add-ons without the runtime (the RTX Remix tab, the fixes' sky). In the
-- server realm of a local game, when this machine's loader did not start RTX and its bootstrap is gone, the RTX client
-- module (gmsv_nlrtxclient) removes it with the loader's own uninstall: once the server's Lua has loaded (Initialize),
-- so that no autorun of this start loses its file half-way, and before the player's client realm starts. The console
-- settings RTX sessions changed are put back, and the player is told to restart. Edit the English text below; its
-- translations are in companion/i18n/<language>.po. Documented in nativeloader_leftovers.lua.md.
if not SERVER or MENU_DLL or NativeLoaderLeftoversAutorun then return end
NativeLoaderLeftoversAutorun = true
if game.IsDedicated() then return end
if NativeLoaderRTXStart and NativeLoaderRTXStart() then return end
-- The loader is still installed (a start through an off switch): it removes what it deployed itself, and a start
-- through an off switch loads none of the package's native code, so the module is not loaded at all. It checks again.
do
    local ok, found = pcall(file.Exists, "bin/win64/winmm.dll", "BASE_PATH")
    if not ok or found then return end
end

local function N(text) return text end
local TEXT = {
    removed = N"RTX Remix was removed from this game because its loader (bin/win64/winmm.dll) is gone. Restart Garry's Mod to finish.",
    partly = N"RTX Remix was partly removed from this game because its loader (bin/win64/winmm.dll) is gone. Restart Garry's Mod; the console lists what stayed.",
}

-- The player's language, read now: the removal takes this add-on's files, its translations with them.
local phrases
do
    local ok, data = pcall(function()
        if not file.Exists("nativeloader/i18n_data.lua", "LUA") then return nil end
        return include("nativeloader/i18n_data.lua")
    end)
    if ok and istable(data) then
        local aliases = { zh = "zh-CN", ["zh-cn"] = "zh-CN", ["zh-tw"] = "zh-TW" }
        local function code(name)
            local convar = GetConVar(name)
            local value = convar and convar:GetString() or ""
            return aliases[value:lower()] or value
        end
        local chosen = code("nativeloader_language")
        phrases = data[chosen ~= "" and chosen or code("gmod_language")]
    end
end
local function L(text)
    local translated = istable(phrases) and phrases[text]
    return isstring(translated) and translated ~= "" and translated or text
end

local function say(text) MsgN("[nativeloader] " .. text) end

-- In the chat once the player is in the game (their first own move, as the RTX fixes tell a full load), in a single
-- player game or to a listen server's host; Garry's Mod's own chat shows it, so no Lua of this add-on is needed there.
local function tell(text)
    local function show(ply)
        if IsValid(ply) and (game.SinglePlayer() or ply:IsListenServerHost()) then ply:ChatPrint(text) end
    end
    hook.Add("PlayerInitialSpawn", "nativeloader_leftovers", function(ply)
        hook.Add("SetupMove", ply, function(self, mover, _, cmd)
            if self ~= mover or cmd:IsForced() then return end
            hook.Remove("SetupMove", self)
            show(self)
        end)
    end)
end

hook.Add("Initialize", "nativeloader_leftovers", function()
    hook.Remove("Initialize", "nativeloader_leftovers")
    local loaded = pcall(require, "nlrtxclient")
    local api = loaded and rawget(_G, "NativeLoaderLeftovers")
    if not istable(api) or not isfunction(api.Remove) then return end
    local ok, result = pcall(api.Remove)
    if not ok or not istable(result) or result.outcome == "not needed" then return end
    local outcome = tostring(result.outcome)
    if outcome ~= "removed" and outcome ~= "partly removed" then
        say("The native loader (bin/win64/winmm.dll) is gone, but RTX Remix's files were not removed now: " ..
            tostring(result.error) .. ". The next local game tries again.")
        return
    end
    say(string.format("The native loader (bin/win64/winmm.dll) is gone: RTX Remix %s. %d files deleted, %d of yours put back.",
        outcome, tonumber(result.deleted) or 0, tonumber(result.restored) or 0))
    if (tonumber(result.former) or 0) > 0 then
        say(string.format("%d files of an earlier RTX installation kept in %s.", result.former, tostring(result.former_folder)))
    end
    if (tonumber(result.aside) or 0) > 0 then
        say(string.format("%d files this game holds open moved to %s; delete that folder whenever you like.",
            result.aside, tostring(result.aside_folder)))
    end
    if outcome == "partly removed" then
        for _, line in ipairs(istable(result.notes) and result.notes or {}) do say("  " .. tostring(line)) end
    end
    -- The player's own values of the console settings RTX sessions changed (the loader puts them back at a start
    -- without RTX; it is gone).
    local restored = {}
    for _, pair in ipairs(istable(result.restore) and result.restore or {}) do
        if istable(pair) and isstring(pair[1]) and isstring(pair[2]) then
            RunConsoleCommand(pair[1], pair[2])
            restored[#restored + 1] = pair[1] .. " " .. pair[2]
        end
    end
    if #restored > 0 then say("Console settings put back: " .. table.concat(restored, ", ")) end
    tell(L(outcome == "removed" and TEXT.removed or TEXT.partly))
end)
