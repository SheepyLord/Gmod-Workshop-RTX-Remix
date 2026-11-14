-- Regression for the RTX fixes' automatic categorization (ADR 0213), without a game: the packaged
-- cl_remix_category_0_manager.lua against stand-ins for GMod, NikNaks and the native RemixMaterial API.
-- Usage: luajit tools/tests/category_manager_harness.lua <cl_remix_category_0_manager.lua>
local path = assert(arg[1], "usage: category_manager_harness.lua <cl_remix_category_0_manager.lua>")

BRANCH, CLIENT = "x86-64", true
bit = require("bit")
local clock = 0
function SysTime() clock = clock + 0.0005 return clock end -- every look at the clock costs half a millisecond
function CurTime() return clock end
function RealTime() return clock end
function Color(...) return {...} end
local log = {}
function MsgC(...) local parts = {...} log[#log + 1] = tostring(parts[#parts]) end
function print() end
function isstring(v) return type(v) == "string" end
function istable(v) return type(v) == "table" end
function isfunction(v) return type(v) == "function" end
function IsValid(v) return v ~= nil end
function string.EndsWith(s, e) return e == "" or s:sub(-#e) == e end
function string.StartsWith(s, p) return s:sub(1, #p) == p end
function string.Trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
function string.Explode(sep, s)
    local out, at = {}, 1
    while true do
        local i, j = s:find(sep, at, true)
        if not i then out[#out + 1] = s:sub(at) return out end
        out[#out + 1] = s:sub(at, i - 1)
        at = j + 1
    end
end
function table.Count(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end

-- VMT files on the GAME path, and how often each is read.
local vmts, reads = {}, {}
file = {Exists = function() return false end,
    Read = function(name) reads[name] = (reads[name] or 0) + 1 return vmts[name] end}

local values, callbacks, commands, hooks, timers = {}, {}, {}, {}, {}
function GetConVar(name)
    return {GetBool = function() return values[name] ~= nil and values[name] ~= "0" end,
        GetFloat = function() return tonumber(values[name]) or 0 end,
        GetInt = function() return tonumber(values[name]) or 0 end,
        GetString = function() return values[name] or "" end}
end
function CreateClientConVar(name, default) if values[name] == nil then values[name] = default end return GetConVar(name) end
cvars = {AddChangeCallback = function(name, fn) callbacks[name] = callbacks[name] or {} table.insert(callbacks[name], fn) end}
local function Set(name, value)
    local old = values[name]
    values[name] = value
    for _, fn in ipairs(callbacks[name] or {}) do fn(name, old, value) end
end
concommand = {Add = function(name, fn) commands[name] = fn end}
hook = {Add = function(event, name, fn) hooks[event] = hooks[event] or {} hooks[event][name] = fn end,
    Remove = function(event, name) if hooks[event] then hooks[event][name] = nil end end}
timer = {Simple = function(_, fn) timers[#timers + 1] = fn end, Create = function() end}
local mapName = "gm_test"
game = {GetMap = function() return mapName end}
ents = {GetAll = function() return {} end}
local propMaterials = {["models/props/crate.mdl"] = {"models/props/crate_sheet"}}
util = {GetModelMaterials = function(model) return propMaterials[model] or {} end}

-- Materials: name -> {shader, kv (key values), ints, throws}. Unknown names are error materials.
local mats = {}
local materialCalls = 0
function Material(name)
    materialCalls = materialCalls + 1
    local m = mats[name]
    if m and m.throws then error("unreadable material " .. name) end
    return {IsError = function() return not m end,
        GetShader = function() return m and m.shader or "LightmappedGeneric" end,
        GetKeyValues = function() return m and m.kv or {} end,
        GetInt = function(_, key) return m and m.ints and m.ints[key] end,
        GetFloat = function() return nil end,
        GetString = function(_, key) return m and m.kv and m.kv[key] end,
        GetTexture = function() return nil end,
        GetVector = function() return nil end,
        GetName = function() return name end}
end

-- The native side: hashes of materials drawn so far, categories, and every write with its automatic flag.
local hashes, categories, writes = {}, {}, {}
local lookups, worldList, clears, registered = 0, nil, 0, {}
local cached = {}
RemixMaterial = {
    GetAllTextureHashes = function(name) lookups = lookups + 1 return hashes[name] end,
    GetHashCategory = function(h) return categories[h] end,
    SetHashCategory = function(h, flags, automatic)
        writes[#writes + 1] = {hash = h, flags = flags, automatic = automatic}
        categories[h] = bit.bor(categories[h] or 0, flags)
        return true
    end,
    RemoveHashCategory = function(h) categories[h] = nil return true end,
    TrackMaterial = function() end,
    SetWorldTextureList = function(list) worldList = list end,
    ClearWorldTextureList = function() worldList = false clears = clears + 1 end,
    RegisterBSPWorldMaterial = function(name) registered[name] = true end,
    GetCachedMaterials = function() return cached end,
    ClearTextureCache = function() end, ClearBSPWorldMaterials = function() end, ClearForceAlbedoHashes = function() end,
    SetAutoCategorization = function() end, SetParticleCategorization = function() end,
    SetDecalCategorization = function() end, SetEmissiveCategorization = function() end, SetDebugOutput = function() end,
}

-- The map: two brushes, a $decal overlay, glass, a material that cannot be read, a blended displacement (its runtime
-- patch material's name) and a static prop.
local function face(material) return {IsDisplacement = function() return true end, GetMaterial = function() return Material(material) end} end
local bsp = {
    GetTextures = function() return {"concrete/wall", "concrete/wall", "decals/poster", "glass/window01", "broken/material", "tile/floor"} end,
    GetLeafs = function()
        return {{GetFaces = function() return {face("maps/gm_test/nature/blend_grass_wvt_patch")} end},
            {GetFaces = function() return {face("maps/gm_test/nature/blend_grass_wvt_patch")} end}}
    end,
    GetStaticProps = function() return {{PropType = "models/props/crate.mdl", Skin = 0}} end,
}
NikNaks = {CurrentMap = bsp}
mats["concrete/wall"] = {kv = {["$basetexture"] = "concrete/wall"}}
mats["tile/floor"] = {kv = {}}
mats["decals/poster"] = {kv = {["$decal"] = "1"}, ints = {["$decal"] = 1}}
mats["glass/window01"] = {kv = {["$basetexture"] = "glass/window01"}}
mats["broken/material"] = {throws = true}
mats["nature/blend_grass"] = {kv = {["$basetexture"] = "nature/grass"}}
mats["models/props/crate_sheet"] = {kv = {["$basetexture"] = "models/props/crate_sheet"}}
vmts["materials/tile/floor.vmt"] = '"LightmappedGeneric"\n{\n"$basetexture" "tile/floor"\n}\n'
for name, h in pairs({["concrete/wall"] = "0xA1", ["decals/poster"] = "0xA2", ["glass/window01"] = "0xA3",
        ["tile/floor"] = "0xA4", ["nature/blend_grass"] = "0xA5", ["models/props/crate_sheet"] = "0xA6"}) do
    hashes[name] = {h}
end

dofile(path)
assert(RemixCategoryManager and RemixCategoryManager.StartWorldScan, "the packaged manager has the scan job")
Set("rtx_auto_categorize_emissive", "0")

local function Think()
    for _, fn in pairs(hooks.Think) do fn() end
end
local function RunScan()
    local steps = 0
    repeat
        local before = materialCalls
        Think()
        steps = steps + 1
        assert(materialCalls - before <= 12, "a frame's step stays small: " .. (materialCalls - before) .. " material lookups")
        assert(steps < 500, "the scan ends")
    until not RemixCategoryManager.IsWorldScanRunning()
    return steps
end
local function FlagsFor(h)
    local flags = 0
    for _, w in ipairs(writes) do if w.hash == h then flags = bit.bor(flags, w.flags) end end
    return flags
end

-- 1. A map load: the delayed timer starts the scan as a job that takes several frames.
hooks.InitPostEntity.RemixCategoryManager_InitFlags()
assert(#timers == 1, "the map load sets one delayed start")
timers[1]()
assert(RemixCategoryManager.IsWorldScanRunning())
local steps = RunScan()
assert(steps > 2, "the scan is spread over frames, not one: " .. steps)
for _, w in ipairs(writes) do assert(w.automatic == true, "automatic writes say so: " .. w.hash) end
assert(FlagsFor("0xA1") == 0x1000 and FlagsFor("0xA4") == 0x1000, "brushes are world decals")
assert(FlagsFor("0xA2") == 0x1000, "the overlay is a decal")
assert(FlagsFor("0xA3") == 0x1000, "glass brushes keep the world rule")
assert(FlagsFor("0xA5") == 0x1000, "the blended displacement is found under the name the tracker uses")
assert(FlagsFor("0xA6") == 0x1000, "static props are world decals")
assert(type(worldList) == "table", "the C++ side gets the world list")
local seen = {}
for _, name in ipairs(worldList) do assert(not seen[name], "listed once: " .. name) seen[name] = true end
assert(seen["nature/blend_grass"] and not seen["maps/gm_test/nature/blend_grass_wvt_patch"])
assert(seen["models/props/crate_sheet"] and seen["concrete/wall"])
local unreadable = false
for _, line in ipairs(log) do if line:find("Unreadable: 1", 1, true) then unreadable = true end end
assert(unreadable, "a material that cannot be read is counted and the scan goes on")
assert((reads["materials/tile/floor.vmt"] or 0) == 1, "each VMT is read once a scan")

-- 2. Idempotence: Scan Now again gives the same categories and no second queue entry per material.
local pendingBefore = RemixCategoryManager.GetPendingCount()
local categoriesBefore = {}
for h, f in pairs(categories) do categoriesBefore[h] = f end
commands.rtx_smart_mark_world(nil, nil, {"force"})
RunScan()
assert(RemixCategoryManager.GetPendingCount() == pendingBefore, "no duplicate queue entries")
for h, f in pairs(categories) do assert(categoriesBefore[h] == f, "same categories: " .. h) end

-- 3. World Geometry off: map geometry is no longer marked, the C++ world list goes, overlays still are decals.
categories, writes = {}, {}
Set("rtx_auto_categorize_world", "0")
assert(worldList == false and clears >= 1, "switching World Geometry off empties the C++ world list")
commands.rtx_smart_mark_world(nil, nil, {"force"})
RunScan()
assert(worldList == false, "no world list is sent while World Geometry is off")
assert(FlagsFor("0xA1") == 0 and FlagsFor("0xA3") == 0 and FlagsFor("0xA4") == 0, "brushes stay as they are")
assert(FlagsFor("0xA5") == 0 and FlagsFor("0xA6") == 0, "displacements and props stay as they are")
assert(FlagsFor("0xA2") == 0x1000, "Overlay Decals still marks the overlay")
assert(registered["concrete/wall"], "world brushes still guard their hashes against particle tags")

-- 4. Overlay Decals off too: nothing is marked.
categories, writes = {}, {}
Set("rtx_auto_categorize_decals", "0")
commands.rtx_smart_mark_world(nil, nil, {"force"})
RunScan()
assert(#writes == 0, "with both switches off the scan marks nothing")
Set("rtx_auto_categorize_decals", "1")
Set("rtx_auto_categorize_world", "1")
assert(RemixCategoryManager.IsWorldScanRunning(), "World Geometry on scans the map again")
RunScan()

-- 5. The queue: one entry per material, merged; a frame looks at a bounded number of entries.
hooks.InitPostEntity.RemixCategoryManager_InitFlags()
timers = {}
RemixCategoryManager.SetMaterialCategory("unseen/a", 0x1000, nil, true)
RemixCategoryManager.SetMaterialCategory("unseen/a", 0x400, nil, true)
assert(RemixCategoryManager.GetPendingCount() == 1, "one entry per material")
for i = 1, 300 do RemixCategoryManager.SetMaterialCategory("unseen/m" .. i, 0x1000, nil, true) end
assert(RemixCategoryManager.GetPendingCount() == 301)
lookups = 0
hooks.Think.RemixCategoryManager_DrainPending()
assert(lookups <= 2 * 64, "a frame checks at most 64 entries: " .. lookups)
-- Drawn now: the merged entry applies both bits.
hashes["unseen/a"] = {"0xB1"}
writes = {}
for _ = 1, 10 do hooks.Think.RemixCategoryManager_DrainPending() end
assert(FlagsFor("0xB1") == 0x1400 and writes[1].automatic == true, "the merged entry applies both bits, automatically")

-- 6. A manual command is not automatic.
writes = {}
hashes["manual/m"] = {"0xC1"}
commands.rtx_set_material_category(nil, nil, {"manual/m", "0x400"})
assert(#writes == 1 and writes[1].hash == "0xC1" and not writes[1].automatic, "manual categories are the player's")

-- 7. Automatic categorization off: the scan stops and its queue goes; a manual entry stays.
RemixCategoryManager.SetMaterialCategory("unseen/manual", 0x1000)
RemixCategoryManager.StartWorldScan(true)
Think()
assert(RemixCategoryManager.IsWorldScanRunning())
Set("rtx_auto_categorize", "0")
assert(not RemixCategoryManager.IsWorldScanRunning(), "switching automatic categorization off stops the scan")
-- The two manual entries stay: the command's watch entry for manual/m and unseen/manual.
assert(RemixCategoryManager.GetPendingCount() == 2, "only the manual entries stay queued: " .. RemixCategoryManager.GetPendingCount())
Set("rtx_auto_categorize", "1")

-- 8. A map change stops the old map's scan, forgets its queue, and its pending timer starts nothing.
hooks.InitPostEntity.RemixCategoryManager_InitFlags()
local oldTimer = timers[#timers]
RemixCategoryManager.StartWorldScan(true)
Think()
assert(RemixCategoryManager.IsWorldScanRunning())
mapName = "gm_other"
hooks.InitPostEntity.RemixCategoryManager_InitFlags()
assert(not RemixCategoryManager.IsWorldScanRunning(), "the new map stops the old scan")
assert(RemixCategoryManager.GetPendingCount() == 0, "the old map's queue is gone")
oldTimer()
assert(not RemixCategoryManager.IsWorldScanRunning(), "the old map's delayed start does nothing")
timers[#timers]()
assert(RemixCategoryManager.IsWorldScanRunning(), "the new map's own start runs")
RunScan()

print = io.write
print("PASS category manager: scan job in steps, switches obeyed, tracker names, one VMT read, unreadable material skipped, idempotent, bounded merged queue, manual vs automatic, master switch and map change\n")
