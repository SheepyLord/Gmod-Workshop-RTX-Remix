-- Which sky a map shows in RTX starts (ADR 0249): the RTX sky, the map's own sky (its sky textures, and its 3D
-- skybox where it has one), or a sky the map's RTX version brings, and the words that say so. No Garry's Mod
-- function in it, so the tests run it under plain LuaJIT; nativeloader_sky.lua reads the map, the add-ons' files
-- and the player's choices and does what this decides. Documented in map_sky.lua.md beside this file.
local M = {}

-- Text marked for the translations (tools/companion_i18n.py extracts N("...")); the caller shows it through L.
local function N(text) return text end

M.VERSION = 1      -- the sky files' format
M.SCALE = 16       -- the sky_camera scale the runtime's reprojection is set for (rtx.skyReprojectScale, the package's layer)
M.MAX_FILES = 8    -- sky files read for one map
M.MAX_BYTES = 16384
M.MAX_TITLE = 64
-- Choices that are not a sky file's id.
M.AUTO, M.RTX, M.MAP, M.ADDON = "auto", "rtx", "map", "addon"
local RESERVED = { auto = true, rtx = true, map = true, addon = true }
-- Texinfo flags (bspflags.h): SURF_SKY2D, SURF_SKY.
local SKY_FLAGS = 0x2 + 0x4

---------------------------------------------------------------- names

-- A sky file's id: its file name without .json, lower case.
function M.validId(id)
    return type(id) == "string" and #id <= 48 and id:match("^[a-z0-9][a-z0-9_%-]*$") ~= nil and not RESERVED[id]
end

-- A map name the sky files' folder may be named after.
function M.validMap(name)
    return type(name) == "string" and #name >= 1 and #name <= 64 and name:match("^[%w_%-%.]+$") ~= nil
        and not name:find("..", 1, true)
end

-- A sky name as sv_skyname takes it: materials/skybox/<name><side>.vmt; subfolders allowed, nothing that climbs.
function M.validSkyname(name)
    return type(name) == "string" and #name >= 1 and #name <= 64 and name:match("^[%w_%-][%w_%-/]*$") ~= nil
        and not name:find("//", 1, true) and name:sub(-1) ~= "/"
end

-- A choice for one map: automatic, the RTX sky, the map's own sky, the add-on's sky or a sky file's id.
function M.validChoice(choice)
    return choice == M.AUTO or choice == M.RTX or choice == M.MAP or choice == M.ADDON or M.validId(choice)
end

-- A title as shown in the chat and the panel: no control characters, at most 64 bytes, whole UTF-8 characters.
function M.title(text)
    if type(text) ~= "string" then return nil end
    text = text:gsub("[%z\1-\31\127]", " "):gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", " ")
    if #text > M.MAX_TITLE then
        text = text:sub(1, M.MAX_TITLE)
        -- Drop a character cut in two: trailing continuation bytes and the lead byte before them.
        local last = #text
        while last > 0 and text:byte(last) >= 0x80 and text:byte(last) < 0xC0 do last = last - 1 end
        if last > 0 and text:byte(last) >= 0xC0 then
            local lead, need = text:byte(last), 0
            need = lead >= 0xF0 and 4 or lead >= 0xE0 and 3 or 2
            if #text - last + 1 < need then text = text:sub(1, last - 1) end
        end
        text = text:gsub("%s+$", "")
    end
    return text ~= "" and text or nil
end

---------------------------------------------------------------- the map

-- The sky camera among a map's entities (sky_model.parseEntities): its scale (16 when the key is missing or not a
-- number above 0), or nil when the map has no 3D skybox.
function M.skyCamera(entities)
    for _, e in ipairs(entities or {}) do
        if e.classname == "sky_camera" then
            local scale = tonumber(e.scale)
            if not scale or scale <= 0 or scale ~= scale then scale = 16 end
            return { scale = scale }
        end
    end
    return nil
end

-- How many texinfos of a texinfo lump (72-byte records, the flags at byte 64) are sky. `band` is bit.band.
function M.skyTexinfos(lump, band)
    if type(lump) ~= "string" or #lump < 72 then return 0 end
    local count = 0
    for offset = 65, #lump - 7, 72 do
        local b1, b2, b3, b4 = lump:byte(offset, offset + 3)
        local flags = b1 + b2 * 256 + b3 * 65536 + b4 * 16777216
        if band(flags, SKY_FLAGS) ~= 0 then count = count + 1 end
    end
    return count
end

-- A lump Source compressed (its first bytes "LZMA", then the size unpacked, the size packed and five property
-- bytes) as the stream util.Decompress reads: the properties, the size unpacked as 8 bytes, the packed data.
function M.lzmaStream(lump)
    if type(lump) ~= "string" or #lump < 17 or lump:sub(1, 4) ~= "LZMA" then return nil end
    return lump:sub(13, 17) .. lump:sub(5, 8) .. "\0\0\0\0" .. lump:sub(18)
end

-- What the map has of its own: `info` from the map (texinfos: sky texinfos counted, nil when unread; faces: the
-- sky name's materials exist; camera: M.skyCamera's).
--   open    the map shows sky somewhere (or it could not be read)
--   own     it has a sky of its own to show: sky faces and its sky name's materials
--   own3D   it has a 3D skybox (a sky_camera)
--   fits3D  its 3D skybox can be shown: at the scale the runtime's reprojection is set for
function M.facts(info)
    info = info or {}
    local open = info.texinfos == nil or info.texinfos > 0
    local camera = info.camera
    return {
        open = open,
        own = open and info.faces == true,
        own3D = camera ~= nil,
        fits3D = camera ~= nil and camera.scale == M.SCALE,
        scale = camera and camera.scale or nil,
        skyname = info.skyname,
    }
end

---------------------------------------------------------------- sky files

-- A sky file (data_static/nativeloader/sky/<map>/<id>.json) checked: a table, or nil and why not. `decode` is
-- util.JSONToTable. Fields: version 1; sky "map" (the map's own sky, which the add-on's Remix mod may have
-- replaced) or "skybox" (another sky by its name, in materials/skybox); skyname with "skybox"; optional title,
-- skybox3d (default true: the map's 3D skybox too), default (default true: it comes above the RTX sky) and
-- priority (-100 to 100, default 0: the higher first when two files name one map).
function M.declaration(id, text, decode)
    if not M.validId(id) then return nil, "its file name is not an id (a-z, 0-9, _ and -, at most 48; not auto, rtx, map or addon)" end
    if type(text) ~= "string" or text == "" then return nil, "it is empty" end
    if #text > M.MAX_BYTES then return nil, "it is larger than 16 KiB" end
    local ok, t = pcall(decode, text)
    if not ok or type(t) ~= "table" then return nil, "it is not a JSON object" end
    if tonumber(t.version) ~= M.VERSION then return nil, "its version is not 1" end
    if t.sky ~= "map" and t.sky ~= "skybox" then return nil, 'its sky is not "map" or "skybox"' end
    for _, key in ipairs({ "skybox3d", "default" }) do
        if t[key] ~= nil and type(t[key]) ~= "boolean" then return nil, "its " .. key .. " is not true or false" end
    end
    local priority = t.priority == nil and 0 or tonumber(t.priority)
    if not priority or priority ~= math.floor(priority) or priority < -100 or priority > 100 then
        return nil, "its priority is not a whole number from -100 to 100"
    end
    local d = {
        id = id, kind = t.sky, title = M.title(t.title) or id, skybox3d = t.skybox3d ~= false,
        default = t.default ~= false, priority = priority,
    }
    if d.kind == "skybox" then
        if not M.validSkyname(t.skyname) then return nil, "its skyname is not a sky name (letters, digits, _, - and /)" end
        d.skyname = t.skyname
    end
    return d
end

-- Sky files in the order they count: the higher priority first, then by id.
function M.sorted(list)
    local out = {}
    for _, d in ipairs(list or {}) do out[#out + 1] = d end
    table.sort(out, function(a, b)
        if a.priority ~= b.priority then return a.priority > b.priority end
        return a.id < b.id
    end)
    return out
end

---------------------------------------------------------------- which sky

-- Which sky the map shows, before a setting changed in the session. `s`:
--   choice   the player's choice for this map: auto (default), rtx, map, addon or a sky file's id
--   global   "1": the RTX sky on maps without a choice of their own (the default); "0": the map's own sky
--   facts    M.facts
--   files    the map's sky files, M.sorted
--   addon    the map's RTX add-on that sets the sky from Lua: { name = ..., fixed = bool }, or nil
--   single   a single-player game (a sky by its name is set through sv_skyname, which every player shares)
-- The result: sky "rtx", "map" (the map's own), "file" (a sky file's) or "addon"; reason "default", "choice",
-- "global", "package" (the map's RTX version's sky comes above the RTX sky) or "missing" (the map's own sky was
-- chosen and it has none); file, addon; threeD (the map's 3D skybox too); blocked3D (it has one at another
-- scale); skyname (another sky by name); package (the title of the sky "auto" gives from the map's RTX version,
-- whichever is shown, or nil).
function M.resolve(s)
    local f = s.facts or M.facts()
    local function usable(d) return d.kind ~= "skybox" or s.single == true end
    local files = s.files or {}
    -- The map's RTX version's sky, which comes above the RTX sky (the user's choice of 2026-11-20): the add-on's
    -- that sets it from Lua first, then the first sky file that is not only offered.
    local pick
    if s.addon then
        pick = { sky = "addon", addon = s.addon, title = s.addon.name }
    else
        for _, d in ipairs(files) do
            if d.default and usable(d) then pick = { sky = "file", file = d, title = d.title } break end
        end
    end
    local function done(r)
        r.package = pick and pick.title or nil
        return r
    end
    local function own(reason, d)
        local r = { sky = d and "file" or "map", reason = reason, file = d }
        local want3D = not d or d.skybox3d
        r.threeD = want3D and f.fits3D or false
        r.blocked3D = (want3D and f.own3D and not f.fits3D) or false
        if d and d.kind == "skybox" then r.skyname = d.skyname end
        return done(r)
    end
    local choice = s.choice
    if choice == M.RTX then return done({ sky = "rtx", reason = "choice" }) end
    if choice == M.MAP then
        if f.own then return own("choice") end
        return done({ sky = "rtx", reason = "missing" })
    end
    if choice == M.ADDON and s.addon then return done({ sky = "addon", reason = "choice", addon = s.addon }) end
    for _, d in ipairs(files) do
        if d.id == choice and usable(d) then return own("choice", d) end
    end
    -- Automatic: the map's RTX version's sky; then the player's sky for all other maps.
    if pick and pick.sky == "addon" then return done({ sky = "addon", reason = "package", addon = pick.addon }) end
    if pick then return own("package", pick.file) end
    if s.global == "0" and f.own then return own("global") end
    return done({ sky = "rtx", reason = "default" })
end

-- What the player can choose on this map, in the order the panel lists them: { value, label, argument }.
function M.choices(s)
    local f = s.facts or M.facts()
    local out = { { M.AUTO, N("Automatic") }, { M.RTX, N("RTX sky") } }
    if f.own then out[#out + 1] = { M.MAP, N("The map's own sky") } end
    if s.addon then out[#out + 1] = { M.ADDON, N("Sky of %s"), s.addon.name } end
    for _, d in ipairs(s.files or {}) do
        if d.kind ~= "skybox" or s.single == true then out[#out + 1] = { d.id, N("Sky of %s"), d.title } end
    end
    return out
end

---------------------------------------------------------------- what it says

-- What shows now, as { text, arguments... }. `e` is M.resolve's table with `shown` set by the caller: "rtx" (the
-- RTX sky, the companion's), "own" (the map's own or a file's sky, the companion's), "addon" (the add-on's sky) or
-- "taken" (the RTX sky until the next map: a sky or weather setting changed in the session); `follows` is true for
-- an add-on that sets the RTX sky itself (Modern House RTX), not a fixed sky.
function M.state(e, f)
    f = f or M.facts()
    if not f.open then return { N("This map has no open sky.") } end
    if e.shown == "taken" then
        -- An add-on sets its sky at the map's start: it comes back then.
        if e.sky == "addon" and e.addon then
            return { N("This map shows the RTX sky until the next map starts, when the sky of %s returns."), e.addon.name }
        end
        return { N("This map shows the RTX sky until the next map starts: a sky or weather setting changed.") }
    end
    if e.shown == "addon" then
        if e.follows then return { N("On this map %s sets the RTX sky."), e.addon.name } end
        return { N("This map shows the sky of %s."), e.addon.name }
    end
    if e.shown == "own" then
        if e.file then return { N("This map shows the sky of %s."), e.file.title } end
        local chosen = e.reason == "choice"
        if e.threeD then
            return { chosen and N("This map shows its own sky and its 3D skybox, as you chose for it.")
                or N("This map shows its own sky and its 3D skybox.") }
        end
        return { chosen and N("This map shows its own sky, as you chose for it.") or N("This map shows its own sky.") }
    end
    return { e.reason == "choice" and N("This map shows the RTX sky, as you chose for it.") or N("This map shows the RTX sky.") }
end

-- How to switch, or why one cannot, as { text, arguments... } or nil.
function M.advice(e, f)
    f = f or M.facts()
    if not f.open or e.shown == "taken" then return nil end
    if e.shown == "addon" and e.follows then
        return { N("For your own time of day and weather: type nativeloader_sky_here rtx in the console, or use RTX Remix > Sky and weather in the spawn menu.") }
    end
    if e.shown == "own" or e.shown == "addon" then
        return { N("For the RTX sky: type nativeloader_sky_here rtx in the console, or use RTX Remix > Sky and weather in the spawn menu.") }
    end
    if e.package then
        return { N("Its RTX version has a sky of its own, from %s: type nativeloader_sky_here auto in the console, or use RTX Remix > Sky and weather in the spawn menu."), e.package }
    end
    -- An add-on that sets a fixed sky but names itself only while its sky shows (the player chose another one).
    if e.packageUnnamed then
        return { N("Its RTX version has a sky of its own: type nativeloader_sky_here auto in the console, or use RTX Remix > Sky and weather in the spawn menu.") }
    end
    if f.own then
        if f.own3D and f.fits3D then
            return { N("It also has a sky of its own, with a 3D skybox: type nativeloader_sky_here map in the console, or use RTX Remix > Sky and weather in the spawn menu.") }
        end
        return { N("It also has a sky of its own: type nativeloader_sky_here map in the console, or use RTX Remix > Sky and weather in the spawn menu.") }
    end
    return { N("It has no sky of its own to switch to. Time of day and weather: RTX Remix > Sky and weather in the spawn menu.") }
end

-- A note on the map's 3D skybox when it cannot be shown, or nil.
function M.limit(e, f)
    f = f or M.facts()
    if e.shown == "own" and e.blocked3D then return { N("Its 3D skybox (scale %d) cannot be shown under RTX yet."), f.scale } end
    return nil
end

return M
