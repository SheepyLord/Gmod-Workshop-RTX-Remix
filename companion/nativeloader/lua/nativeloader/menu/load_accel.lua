-- The load accelerator at menu start (R26, ADR 0140). The RTX client module runs this companion menu script once in
-- the menu realm of an RTX start, before loading_status.lua: it loads the nlfsaccel module (its gmsv_ copy) and hooks
-- filesystem_stdio.dll for the process, so every map load of this start has the cache of what is not in the loose
-- add-on folders from its first file; the load accelerator's add-on adopts the hooks in each realm. Documented in
-- load_accel.lua.md beside this file.
if not MENU_DLL or NativeLoaderLoadAccel ~= nil then return end
NativeLoaderLoadAccel = false

-- nativeloader_load_accel is the add-on's client convar, which the menu realm cannot see (RESEARCH, R24): its "off"
-- reaches the menu as a file the client keeps.
if file and isfunction(file.Exists) and file.Exists("nativeloader/load_accel_off.txt", "DATA") then
    MsgN("[nativeloader] load accelerator (menu): off (nativeloader_load_accel 0)")
    return
end

local loaded, problem = pcall(require, "nlfsaccel")
local accel = rawget(_G, "nlfsaccel")
if not loaded or not istable(accel) or not isfunction(accel.Install) then
    MsgN("[nativeloader] load accelerator (menu): the module did not load: " .. tostring(problem))
    return
end

-- The module leaves the hooks out once after a start that ended before a map had loaded with them (its own marker in
-- data/nativeloader: the menu realm cannot write files) and says why.
local installed, reason = accel.Install()
if not installed then
    MsgN("[nativeloader] load accelerator (menu): file lookups are GMod's own: " .. tostring(reason))
    return
end
NativeLoaderLoadAccel = accel

-- ADR 0242: while the menu is up, the module reads ahead what the last first load of a game read (its list in
-- data/nativeloader/prefetch, which loading_status.lua has the module record and save), so that the next load finds it
-- in Windows' file cache. nativeloader_load_accel_prefetch 0 (the add-on's) reaches this realm as a file.
if isfunction(accel.Prefetch) and not (isfunction(file.Exists) and file.Exists("nativeloader/load_accel_prefetch_off.txt", "DATA")) then
    local ok, started, map = pcall(accel.Prefetch)
    if ok and started then
        NativeLoaderLoadAccelPrefetched = map
        MsgN("[nativeloader] load accelerator (menu): reading ahead what the last load of " .. tostring(map) .. " read")
    end
end
local status = accel.Status()
local links = tonumber(status.links) or 0
MsgN("[nativeloader] load accelerator (menu): " .. tostring(status.roots or 0) .. " loose add-on folders cached" ..
    (links > 0 and (", " .. links .. " of them links or junctions") or ""))

-- Ten seconds after the first map load ends (most lookups are in a load, not at menu start), the module may take its
-- marker off: the hooks did not take the game down. The menu's Think runs whenever it draws, in a game too.
if isfunction(accel.Settled) and isfunction(IsInLoading) then
    local loadEnded = nil
    hook.Add("Think", "NativeLoaderLoadAccel", function()
        if IsInLoading() then
            loadEnded = false
            return
        end
        if loadEnded == nil then return end  -- no load yet
        if loadEnded == false then loadEnded = SysTime() end
        if SysTime() - loadEnded < 10 then return end
        hook.Remove("Think", "NativeLoaderLoadAccel")
        accel.Settled()
    end)
end
