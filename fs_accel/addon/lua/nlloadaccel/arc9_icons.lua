-- The load accelerator, round 3 item F (ADR 0240): ARC9's attachment icons decoded when first drawn, not while a map
-- loads. ARC9 (sh_atts.lua, LoadAtts) runs every attachment file at its autorun, in both realms, and each file asks
-- Material("<icon>.png", "mips smooth") for its icon: 1,481 PNG calls for 853 icons in the user's game, about 2.3 s of
-- the server's Lua start. The material system caches a PNG material by name for the whole process, so in a game this
-- computer hosts the server decodes each icon and the client finds it decoded.
-- Here, while a map loads, a PNG asked for by an ARC9 attachment file gets a stand-in instead:
--   * the server realm, which never draws an icon, gets one shared material for all of them;
--   * the client realm gets one material per icon (by path and flags, as GMod's own cache), made without decoding;
--     the first time anything draws it (surface.SetMaterial, render.SetMaterial, the material overrides) or reads it
--     (its texture, size, values, IsError), the icon is decoded and its texture put into the stand-in.
-- Icons nobody opens are never decoded. With ARC9's arc9_atts_generate_entities on (it reads every icon's texture name
-- at load) and for flags other than mips, smooth and noclamp, Material is GMod's own. Documented in arc9_icons.lua.md.
if NLLOADACCEL_ICONS ~= nil then return end
NLLOADACCEL_ICONS = false

local switch = CreateConVar("nativeloader_load_accel_arc9", "1", FCVAR_ARCHIVE,
    "ARC9's attachment icons decoded when first drawn instead of while a map loads (0: as ARC9 does, from the next map)")
if not switch:GetBool() then return end
local nativeMaterial = Material
if not isfunction(nativeMaterial) then return end

local SOURCE = "arc9/common/attachments"
local TEXTURE_FLAGS = { mips = true, smooth = true, noclamp = true }
local loading = true
local state = { server = 0, standIns = 0, decoded = 0, broken = 0 }
NLLOADACCEL_ICONS = state

-- A caller up the stack is an ARC9 attachment file (directly, or through a helper it calls; the render guard's
-- Material wrapper may sit between).
local function fromAttachment()
    for level = 3, 9 do
        local info = debug.getinfo(level, "S")
        if not info then return false end
        local src = info.short_src
        if isstring(src) and src:find(SOURCE, 1, true) then return true end
    end
    return false
end

-- Flags that only the texture carries (the decoded texture brings them along); anything else stays GMod's.
local function textureFlagsOnly(params)
    if params == nil then return true end
    if not isstring(params) then return false end
    for word in params:gmatch("%S+") do
        if not TEXTURE_FLAGS[word:lower()] then return false end
    end
    return true
end

local function generatesEntities()
    local cv = GetConVar("arc9_atts_generate_entities")
    return cv ~= nil and cv:GetBool()
end

local sharedStandIn
local pending = {}    -- stand-in -> { path, params }
local made = {}       -- params .. "\n" .. path -> stand-in
local names = {}      -- material name -> the key it stands in for (two keys with one CRC get different names)
local broken = setmetatable({}, { __mode = "k" })
local remaining = 0

local function standIn(path, params)
    local key = (params or "") .. "\n" .. path:lower()
    local mat = made[key]
    if mat then return mat end
    -- Named by the icon: a later map's Lua state gets the same material back from the material system.
    local name = "nlloadaccel/arc9icon_" .. util.CRC(key)
    while names[name] ~= nil and names[name] ~= key do name = name .. "_" end
    names[name] = key
    mat = CreateMaterial(name, "UnlitGeneric",
        { ["$basetexture"] = "vgui/white", ["$vertexcolor"] = 1, ["$vertexalpha"] = 1 })
    if not mat then return nil end
    made[key] = mat
    pending[mat] = { path, params }
    remaining = remaining + 1
    state.standIns = state.standIns + 1
    return mat
end

-- The icon itself, decoded now, into its stand-in.
local function fill(mat)
    local want = pending[mat]
    if not want then return end
    pending[mat] = nil
    remaining = remaining - 1
    local ok, real = pcall(nativeMaterial, want[1], want[2])
    if not ok or not real then broken[mat] = true state.broken = state.broken + 1 return end
    state.decoded = state.decoded + 1
    if real:IsError() then
        broken[mat] = true
        state.broken = state.broken + 1
    end
    local texture = real:GetTexture("$basetexture")
    if texture then mat:SetTexture("$basetexture", texture) end
    local flags = real:GetInt("$flags")
    if flags and mat:GetInt("$flags") ~= flags then mat:SetInt("$flags", flags) end
end
state.fill = fill

Material = function(name, params, ...)
    if loading and isstring(name) and name:sub(-4):lower() == ".png" and fromAttachment() then
        if SERVER then
            -- The server never draws an icon: one material stands in for every one of them.
            sharedStandIn = sharedStandIn or nativeMaterial("vgui/white")
            state.server = state.server + 1
            return sharedStandIn, 0
        end
        if textureFlagsOnly(params) and not generatesEntities() then
            local mat = standIn(name, params)
            if mat then return mat, 0 end
        end
    end
    return nativeMaterial(name, params, ...)
end

if CLIENT then
    -- What draws a material: the icon is decoded first.
    local function filling(tbl, name, position)
        local original = istable(tbl) and tbl[name]
        if not isfunction(original) then return end
        if position == 2 then
            tbl[name] = function(a, mat, ...)
                if remaining > 0 and mat ~= nil and pending[mat] then fill(mat) end
                return original(a, mat, ...)
            end
        else
            tbl[name] = function(mat, ...)
                if remaining > 0 and mat ~= nil and pending[mat] then fill(mat) end
                return original(mat, ...)
            end
        end
    end
    filling(surface, "SetMaterial")
    filling(render, "SetMaterial")
    filling(render, "MaterialOverride")
    filling(render, "ModelMaterialOverride")
    filling(render, "BrushMaterialOverride")
    filling(render, "WorldMaterialOverride")
    filling(render, "MaterialOverrideByIndex", 2)
    -- What reads a material: decoded first, so the answer is the icon's. The name and the shader stay the
    -- stand-in's (UnlitGeneric, as GMod's PNG materials).
    local meta = FindMetaTable("IMaterial")
    if meta then
        for _, method in ipairs({ "GetTexture", "GetString", "GetInt", "GetFloat", "GetVector", "GetVector4D",
            "GetVectorLinear", "GetMatrix", "GetKeyValues", "Width", "Height", "GetColor" }) do
            local original = meta[method]
            if isfunction(original) then
                meta[method] = function(self, ...)
                    if remaining > 0 and pending[self] then fill(self) end
                    return original(self, ...)
                end
            end
        end
        local isError = meta.IsError
        if isfunction(isError) then
            meta.IsError = function(self, ...)
                if remaining > 0 and pending[self] then fill(self) end
                if broken[self] then return true end
                return isError(self, ...)
            end
        end
    end
end

-- ARC9 has registered its attachments once the map has loaded: from here Material is GMod's own again (the wrapper
-- only passes the call on), and a later reload of ARC9's attachments (its console command, Lua refresh) decodes as
-- ARC9 does.
hook.Add("InitPostEntity", "nlloadaccel_arc9_icons", function()
    loading = false
    local said = SERVER and state.server or state.standIns
    if said > 0 then
        print(string.format("[nativeloader] load accelerator (%s): %d ARC9 attachment icons %s", SERVER and "server" or
            "client", said, SERVER and "not decoded (the server never draws them)" or "left to be decoded when first drawn"))
    end
end)
