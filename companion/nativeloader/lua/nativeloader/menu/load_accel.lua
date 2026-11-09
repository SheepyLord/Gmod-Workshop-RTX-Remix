-- The load accelerator at menu start (R26, ADR 0140). The RTX client module runs this companion menu script once in
-- the menu realm of an RTX start, before loading_status.lua: it loads the nlfsaccel module (its gmsv_ copy) and hooks
-- filesystem_stdio.dll for the process, so every map load of this start has the cache of what is not in the loose
-- add-on folders from its first file; the load accelerator's add-on adopts the hooks in each realm. Documented in
-- load_accel.lua.md beside this file.
if not MENU_DLL or NativeLoaderLoadAccel ~= nil then return end
NativeLoaderLoadAccel = false

local enabled
do
    local ok, convar = pcall(CreateConVar, "nativeloader_load_accel", "1", FCVAR_ARCHIVE,
        "The load accelerator (0 off from the next start): answers file lookups GMod repeats across the loose add-on folders, and add-on searches, from memory")
    enabled = ok and convar or nil
end
if enabled and not enabled:GetBool() then return end

local loaded, problem = pcall(require, "nlfsaccel")
local accel = rawget(_G, "nlfsaccel")
if not loaded or not istable(accel) or not isfunction(accel.Install) then
    MsgN("[nativeloader] load accelerator (menu): the module did not load: " .. tostring(problem))
    return
end

-- The module leaves the hooks out once after a start that ended within 20 s of installing them (its own marker in
-- data/nativeloader: the menu realm cannot write files) and says why.
local installed, reason = accel.Install()
if not installed then
    MsgN("[nativeloader] load accelerator (menu): file lookups are GMod's own: " .. tostring(reason))
    return
end
NativeLoaderLoadAccel = accel
MsgN("[nativeloader] load accelerator (menu): " .. tostring(accel.Status().roots or 0) .. " loose add-on folders cached")
