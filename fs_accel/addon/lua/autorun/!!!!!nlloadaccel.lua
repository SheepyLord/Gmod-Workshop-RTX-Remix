-- The load accelerator (R26, ADR 0140): the nlfsaccel module answers two questions GMod's file system is slow to
-- answer with hundreds of add-ons. Its first part (a cache of what is NOT in the loose add-on folders) is hooked once
-- per process, at menu start by the companion's menu script; here the server and the client realm adopt it (or hook
-- it, if the menu did not). Its second part answers file.Find(pattern, title), for an add-on's title as the path, from
-- an index of GMod's add-on table instead of a walk of every add-on's every file; a self-test against GMod's own
-- answer comes first, and anything else goes to GMod. It runs in RTX starts: without RTX the loader leaves the RTX
-- package's add-on folders out (ADR 0013). Documented in !!!!!nlloadaccel.lua.md beside this file.
if NLLOADACCEL ~= nil then return end
NLLOADACCEL = false

local enabled = CreateConVar("nativeloader_load_accel", "1", FCVAR_ARCHIVE,
    "The load accelerator (0 off from the next start): answers file lookups GMod repeats across the loose add-on folders, and add-on searches, from memory")
local verify = CreateConVar("nativeloader_load_accel_verify", "0", FCVAR_NONE,
    "Load accelerator checks (1): every answer is also asked of GMod and Windows, and differences are counted and printed; nothing is faster")

local REALM = SERVER and "server" or "client"
local function say(text) print("[nativeloader] load accelerator (" .. REALM .. "): " .. text) end

if not enabled:GetBool() then return end
if not (util.IsBinaryModuleInstalled and util.IsBinaryModuleInstalled("nlfsaccel")) then return end
local loaded, problem = pcall(require, "nlfsaccel")
if not loaded or not istable(nlfsaccel) then
    say("the module did not load: " .. tostring(problem))
    return
end
local accel = nlfsaccel

-- Hooked once per process: here, or already at menu start, or by the other realm's copy, which this only adopts. The
-- module itself leaves the hooks out once after a start that ended within 20 s of installing them (its marker in
-- data/nativeloader) and says why.
local hooked, why = accel.Install()
if not hooked then say("file lookups are GMod's own: " .. tostring(why)) end
accel.SetVerify(verify:GetBool())
cvars.AddChangeCallback("nativeloader_load_accel_verify", function(_, _, value)
    accel.SetVerify(tobool(value))
end, "nlloadaccel")

-- Path IDs that are search paths, never add-on titles: GMod answers those itself.
local STANDARD = {}
for _, id in ipairs({ "GAME", "MOD", "LUA", "lsv", "lcl", "LuaMenu", "DATA", "DOWNLOAD", "BSP", "WORKSHOP", "THIRDPARTY",
    "MOD_WRITE", "BASE_PATH", "EXECUTABLE_PATH", "DEFAULT_WRITE_PATH", "GAMEBIN", "PLATFORM", "GAME_WRITE", "garrysmod",
    "hl2", "workshop", "download", "platform" }) do
    STANDARD[id] = true
end
if engine.GetGames then
    for _, game in ipairs(engine.GetGames()) do
        if isstring(game.folder) then STANDARD[game.folder] = true end
    end
end

local original = file.Find
local function same(a, b)
    if not istable(a) or not istable(b) or #a ~= #b then return false end
    for i = 1, #a do
        if a[i] ~= b[i] then return false end
    end
    return true
end
local function shown(list) return istable(list) and ("{" .. table.concat(list, ",", 1, math.min(#list, 8)) .. (#list > 8 and ",..." or "") .. "}") or tostring(list) end

-- GMod's answer and the index's must be the same for a few add-ons before the index answers anything.
local trusted = nil
local function selftest()
    local addons = engine.GetAddons()
    local tried = 0
    for i = 1, #addons, math.max(1, math.floor(#addons / 5)) do
        local addon = addons[i]
        if addon and addon.mounted and isstring(addon.title) and addon.title ~= "" and not STANDARD[addon.title] then
            for _, pattern in ipairs({ "*", "lua/*", "materials/*" }) do
                local files, dirs = original(pattern, addon.title)
                local ours, our_dirs = accel.FindInAddon(pattern, addon.title)
                if not ours then return false, "the index cannot answer for " .. addon.title .. ": " .. tostring(our_dirs) end
                if not same(files, ours) or not same(dirs, our_dirs) then
                    return false, string.format("for %q in %q GMod gave %s %s, the index %s %s", pattern, addon.title,
                        shown(files), shown(dirs), shown(ours), shown(our_dirs))
                end
            end
            tried = tried + 1
            if tried >= 3 then break end
        end
    end
    return true
end

local function reversed(list)
    local out = {}
    for i = #list, 1, -1 do out[#out + 1] = list[i] end
    return out
end

local mismatches = 0
local function find(name, path, sorting)
    if trusted ~= false and isstring(name) and isstring(path) and not STANDARD[path]
        and (sorting == nil or sorting == "nameasc" or sorting == "namedesc") then
        if trusted == nil then
            local ok, why = selftest()
            trusted = ok
            if not ok then say("add-on searches are GMod's own: " .. tostring(why)) end
        end
        if trusted then
            local files, dirs = accel.FindInAddon(name, path)
            if files then
                accel.CountFind(true)
                if sorting == "namedesc" then files, dirs = reversed(files), reversed(dirs) end
                if verify:GetBool() then
                    local real_files, real_dirs = original(name, path, sorting)
                    if not same(files, real_files) or not same(dirs, real_dirs) then
                        mismatches = mismatches + 1
                        if mismatches <= 10 then
                            say(string.format("check: %q in %q: GMod %s %s, the index %s %s", name, path, shown(real_files),
                                shown(real_dirs), shown(files), shown(dirs)))
                        end
                        return real_files, real_dirs
                    end
                end
                return files, dirs
            end
            accel.CountFind(false)
        end
    end
    return original(name, path, sorting)
end
file.Find = find
NLLOADACCEL = { find = find, original = original }

hook.Add("GameContentChanged", "nlloadaccel", function() accel.Invalidate() end)

if CLIENT then
    -- The load's tally, once the game is in.
    hook.Add("InitPostEntity", "nlloadaccel", function()
        timer.Simple(5, function()
            local status = accel.Status()
            local parts = {}
            if status.installed then
                parts[#parts + 1] = string.Comma(status.answered or 0) .. " file lookups answered from memory in " ..
                    tostring(status.roots or 0) .. " folders"
            else
                parts[#parts + 1] = "file lookups GMod's own"
            end
            parts[#parts + 1] = string.Comma(status.finds_served or 0) .. " add-on searches answered from the index"
            if (status.disagreements or 0) > 0 or mismatches > 0 then
                parts[#parts + 1] = "checks found " .. tostring(status.disagreements or 0) .. " lookups and " ..
                    tostring(mismatches) .. " searches different"
            end
            say(table.concat(parts, "; "))
        end)
    end)
end
