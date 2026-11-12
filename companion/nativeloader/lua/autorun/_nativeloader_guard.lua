-- NATIVELOADER_RENDER_GUARD_V2
-- Verified early startup installs this after stock includes/init.lua. A local RTX start without
-- that view installs it from this autorun instead, and the separate verified multiplayer bootstrap
-- route may run after community/server autoruns. Self-contained and idempotent.
-- Lua containment is not native SEH/GPU fault recovery.
if SERVER or MENU_DLL then return end
local environment = getfenv(1)
local early = __NATIVELOADER_RTX_GUARD_EARLY == true
local verifiedMultiplayer = environment ~= _G and rawget(environment, "NATIVELOADER_VERIFIED_MULTIPLAYER") == true
if NativeLoaderRenderGuard and NativeLoaderRenderGuard.version == 2 then return end
-- A listen host serves this file and its generated initializer to remote clients too. Outside the
-- private multiplayer environment, install only where this machine's own loader activated RTX in
-- this start. It rewrites status.json at every start, before any Lua runs, but that file stays after
-- the game exits, and a start through an off switch (-nonativeloader, NATIVE_LOADER_DISABLE=1, the
-- native-loader/disable file) never runs the loader: its "active" can be an earlier start's. Loader
-- 0.14.0 and later therefore also hold native-loader/rtx-session.txt open for the life of an RTX
-- start; Windows deletes it when the game exits, however it exits (R19, proxy F-02). An older
-- loader holds none, and its report alone decides, as before.
local sessionMarker, markingLoader = "native-loader/rtx-session.txt", {0, 14, 0}
local function markerHeld()
    if not file then return false end
    if file.Exists then
        local ok, found = pcall(file.Exists, sessionMarker, "DATA")
        if ok and found == true then return true end
    end
    -- A directory listing never opens the file, whatever the engine's existence check does.
    if file.Find then
        local ok, found = pcall(file.Find, sessionMarker, "DATA")
        if ok and type(found) == "table" then
            for _, name in ipairs(found) do
                if type(name) == "string" and name:lower() == "rtx-session.txt" then return true end
            end
        end
    end
    return false
end
local function marks(text)
    local version = {text:match('"loader_version":"(%d+)%.(%d+)%.(%d+)')}
    if #version ~= 3 then return false end
    for i = 1, 3 do
        local part = tonumber(version[i])
        if part ~= markingLoader[i] then return part > markingLoader[i] end
    end
    return true
end
local function localRTXStart()
    if not (file and file.Read) then return false end
    local ok, text = pcall(file.Read, "native-loader/status.json", "DATA")
    -- No report (it is written last, and can fail): the marker alone shows this start's RTX.
    if not ok or type(text) ~= "string" or text:find('"schema":1', 1, true) == nil then return markerHeld() end
    if text:find('\n"activation":{"outcome":"active"', 1, true) == nil then return false end
    return not marks(text) or markerHeld()
end
local installation
if verifiedMultiplayer then installation = "verified multiplayer bootstrap"
elseif localRTXStart() then installation = early and "early" or "autorun"
else return end
local late = installation == "verified multiplayer bootstrap"
-- Verified multiplayer chunks receive a scoped hook proxy. Change the real
-- hook table, not a field written only into that chunk's private proxy.
local hook = _G.hook
-- R23 (ADR 0130): the engine guard (the nlengineguard binary module) from here as well, before any
-- add-on's autorun. On a remote server this early view is the only companion code the client realm
-- runs; in a local game !!!!nativeloader_engine_guard.lua does the same. Not in the late multiplayer
-- route: too late there.
if not late and type(rawget(_G, "nlengineguard")) ~= "table" and type(require) == "function" then
    local loadedEngineGuard = pcall(require, "nlengineguard")
    local engineGuard = loadedEngineGuard and rawget(_G, "nlengineguard")
    if type(engineGuard) == "table" then
        -- The watchdog's message from the companion's own catalog where this game can include it (a local
        -- game); a remote server's start keeps the module's English. The module takes only this first call,
        -- and the function leaves the table: no server's Lua sets the text of a native message.
        if type(engineGuard.SetMessage) == "function" then
            local title, body = "", ""
            local found, words = pcall(include, "nativeloader/engine_guard_words.lua")
            if found and type(words) == "function" then
                local ok, t, b = pcall(words)
                if ok and type(t) == "string" and type(b) == "string" then title, body = t, b end
            end
            pcall(engineGuard.SetMessage, title, body)
            engineGuard.SetMessage = nil
        end
        -- Initialize (or the first tick) ends the watch; the gamemode's load bounds it to 150 s more.
        local function engineGuardDone()
            if type(engineGuard.StartupDone) ~= "function" then return end
            local done, recovered = pcall(engineGuard.StartupDone)
            if done and recovered == true and file.Delete then pcall(file.Delete, "native-loader/startup-stall.json") end
        end
        local function engineGuardLoaded()
            if type(engineGuard.StartupDone) == "function" then pcall(engineGuard.StartupDone, 150) end
        end
        if hook and hook.Add then
            hook.Add("OnGamemodeLoaded", "nativeloader_engine_guard", engineGuardLoaded)
            hook.Add("PostGamemodeLoaded", "nativeloader_engine_guard", engineGuardLoaded)
            hook.Add("Initialize", "nativeloader_engine_guard", engineGuardDone)
        end
        if timer and timer.Simple then timer.Simple(0, engineGuardDone) end
    end
end

local enabled = CreateClientConVar("nativeloader_guard", "1", true, false,
    "Keep incompatible add-on rendering from undoing the RTX session")
local playerMeta, convarMeta = FindMetaTable("Player"), FindMetaTable("ConVar")
-- The native getter: the motion-blur read compatibility below wraps ConVar:GetBool.
local getBool = convarMeta and convarMeta.GetBool
local state = {version = 2, installation = installation, policy = "inert screen-space shaders under RTX",
    blocked = {}, adapted = {}, errors = {}, cleanup_errors = {}, slow = {}, limitations = {
    "Lua errors only: native faults, GPU failures and infinite loops are not caught",
    "Unknown native state and partially built meshes cannot be universally restored",
    "Later API replacements or unwrapped native aliases can bypass these guards"}}
NativeLoaderRenderGuard = state
local function active()
    local on
    if getBool then on = getBool(enabled) else on = enabled:GetBool() end
    state.enabled = on
    return on
end
state.enabled_at_install = active()
local function pack(...) return {n = select("#", ...), ...} end
local getinfo, traceback, pcall, xpcall, unpack = debug.getinfo, debug.traceback, pcall, xpcall, unpack
local function finite(n) return type(n) == "number" and n == n and n > -math.huge and n < math.huge end
local function integer(n) return finite(n) and n % 1 == 0 end
-- Native size arguments are truncated toward zero, so ScrW() / 3 and similar sizes are valid.
local function whole(n) if finite(n) then return n < 0 and math.ceil(n) or math.floor(n) end end
local function virtual(s)
    s = tostring(s or "?"):gsub("\\", "/"):gsub("^@", "")
    local pos = s:find("/lua/", 1, true)
    if pos then s = s:sub(pos + 1) end
    if s:sub(1, 4) == "lua/" then return s:sub(1, 180) end
    if s:find("^[%a]:") or s:sub(1, 1) == "/" then return "<external Lua>" end
    if s:sub(1, 1) == "[" or s:sub(1, 1) == "=" then return "<dynamic Lua>" end
    return s:sub(1, 180)
end
local function location(info)
    return virtual(info and info.source) .. ":" .. tostring(info and info.currentline or 0)
end
local function caller() return location(getinfo(3, "Sl")) end
local function functionSource(fn)
    local info = type(fn) == "function" and getinfo(fn, "S")
    return virtual(info and info.source)
end
local guardSource = getinfo(1, "S").source
-- The first caller outside this guard and native frames, resolved only when a call is refused.
local function externalCaller()
    for level = 3, 32 do
        local info = getinfo(level, "Sl")
        if not info then break end
        if info.what ~= "C" and info.source ~= guardSource then return location(info) end
    end
    return "<unknown>"
end
local told, reportCounts = {}, {}
local function report(kind, api, reason, source)
    source = virtual(source)
    local key = kind .. "|" .. api .. "|" .. source .. (kind == "blocked" and "" or "|" .. reason)
    local count = reportCounts[kind] or 0
    -- Each category has its own cap, so a flood of refusals cannot hide later error records.
    if told[key] or count >= 128 then return end
    told[key], reportCounts[kind] = true, count + 1
    local list = state[kind]
    list[#list + 1] = {api = api, reason = reason, source = source}
    if MsgN then MsgN("[nativeloader] RTX guard: " .. api .. ": " .. reason .. " (" .. source .. ")") end
end
local function reject(api, reason, source)
    report("blocked", api, reason, source or externalCaller())
    return false
end
local function rejectNul(api, value, source)
    if type(value) == "string" and value:find("%z") then
        reject(api, "embedded NUL in native string", source)
        return true
    end
end

-- Keep the existing pin exemptions and motion-blur read compatibility.
local pinned = {}
local session = file and file.Read and file.Read("cfg/nativeloader_session.cfg", "MOD") or ""
for line in session:gmatch("[^\r\n]+") do
    local name, value = line:match('^%s*([%w_%.]+)%s+"([^"]*)"')
    if not name then name, value = line:match("^%s*([%w_%.]+)%s+([^%s;]+)") end
    if name then pinned[name:lower()] = value end
end
pinned.mat_motion_blur_enabled = pinned.mat_motion_blur_enabled or "0"
-- r_forcehwlight 1 sends every model Source skins on the GPU through fixed-function hardware
-- skinning, which gives Remix no bones: player models and other vanilla characters draw in bind
-- pose around the pelvis (R3-016: Modern House RTX; R8: a Backrooms map add-on). No Lua may set it.
pinned.r_forcehwlight = "0"
for _, name in ipairs({"mat_dxlevel", "mat_hdr_level"}) do
    local value = GetConVar(name)
    if value then pinned[name] = pinned[name] or value:GetString() end
end
-- Video/depth allocations cannot be changed safely during this D3D9 session.
for _, name in ipairs({"r_flashlightdepthres", "mat_antialias", "mat_aaquality", "mat_disable_d3d9ex"}) do
    local value = GetConVar(name)
    if value then pinned[name] = pinned[name] or value:GetString() end
end
local function exempt(s)
    return s:find("remixbinary", 1, true) or s:find("remixlua", 1, true) or s:find("nativeloader", 1, true)
end
local criticalPins = {mat_dxlevel = true, mat_hdr_level = true, r_flashlightdepthres = true,
    mat_antialias = true, mat_aaquality = true, mat_disable_d3d9ex = true, r_forcehwlight = true}
-- RTX map remasters (lua/autorun/<name>_rtx.lua and lua/<name>_rtx/, such as the Backrooms' br_rtx.lua)
-- scope the engine's visibility to their own maps: gm_br_complex draws at about 13 ms with r_novis 0 and
-- the fixes' PAS patch, but ran at 9 FPS with the session's r_novis 1 (R8 field check). They may set that
-- pin only; critical pins stay enforced.
local function remaster(source)
    return source:match("^lua/autorun/[%w_]+_rtx%.lua") ~= nil or source:match("^lua/[%w_]+_rtx/") ~= nil
end
local function allowPin(name, value, source, query)
    if not active() then return true end
    local key = tostring(name or ""):lower()
    if key == "r_novis" and remaster(source) then return true end
    local csm = source:find("lua/realcsm/", 1, true) == 1 or source:find("lua/entities/edit_csm/", 1, true) == 1
        or source:find("lua/autorun/realcsm_client.lua", 1, true) == 1
    if csm and value ~= nil and (key == "r_ambientlightingonly" or key == "r_lightstyle" or key == "r_radiosity"
        or key == "r_shadows_gamecontrol" or key == "r_shadowrendertotexture" or key == "r_shadowdist" or key == "r_farz") then
        report("blocked", key, "Real CSM raster world-lighting settings are inert under RTX", source) return false
    end
    if source:find("lua/autorun/client/cl_bloom_config.lua", 1, true)
        and (key == "mat_bloomscale" or key == "mat_bloom_scalefactor_scalar") then
        report("blocked", key, "Quick Bloom raster bloom settings are inert under RTX", source) return false
    end
    local want = pinned[key]
    if want == nil or (exempt(source) and not criticalPins[key]) or (query and value == nil) then return true end
    if type(value) == "boolean" then value = value and "1" or "0" end
    local a, b = tonumber(value), tonumber(want)
    if tostring(value) == want or (a ~= nil and b ~= nil and finite(a) and a == b) then return true end
    report("blocked", tostring(name), "kept session value " .. want, source)
    return false
end
local function tokens(text)
    local out, part, quoted = {}, {}, false
    local function finish() if #part > 0 then out[#out + 1] = table.concat(part) part = {} end end
    for i = 1, #text do
        local ch = text:sub(i, i)
        if ch == '"' then quoted = not quoted
        elseif not quoted and ch:match("%s") then finish()
        else part[#part + 1] = ch end
    end
    finish()
    return out
end
local function segments(text)
    local out, part, quoted, comment = {}, {}, false, false
    for i = 1, #text do
        local ch = text:sub(i, i)
        if comment then
            if ch == "\n" or ch == "\r" then comment = false out[#out + 1] = table.concat(part) part = {} end
        elseif not quoted and ch == "/" and text:sub(i + 1, i + 1) == "/" then comment = true
        elseif ch == '"' then quoted = not quoted part[#part + 1] = ch
        elseif not quoted and (ch == ";" or ch == "\n" or ch == "\r") then out[#out + 1] = table.concat(part) part = {}
        else part[#part + 1] = ch end
    end
    out[#out + 1] = table.concat(part)
    return out
end
local indirect = {toggle = true, incrementvar = true, multvar = true, cycle = true}
local unsafeCommands = {mat_setvideomode = true, mat_restart = true, vid_restart = true}
local checkCommands
local function checkTokens(args, source, depth)
    local name = tostring(args[1] or ""):lower()
    if unsafeCommands[name] or name:match("^mat_reload") then
        report("blocked", name, "renderer reload/video transitions require an RTX restart", source) return false
    end
    local target = tostring(args[2] or ""):lower()
    if indirect[name] and pinned[target] and (criticalPins[target] or not exempt(source)) then
        report("blocked", name, "indirect write to a session setting", source) return false
    end
    if (name == "alias" or name == "bind") and args[3] then
        if depth >= 4 then report("blocked", name, "nested command limit", source) return false end
        if not checkCommands(table.concat(args, " ", 3), source, depth + 1) then return false end
    end
    return allowPin(name, args[2], source, true)
end
checkCommands = function(text, source, depth)
    for _, command in ipairs(segments(text)) do
        if not checkTokens(tokens(command), source, depth or 0) then return false end
    end
    return true
end
if RunConsoleCommand then
    local original = RunConsoleCommand
    RunConsoleCommand = function(name, ...)
        if not active() then return original(name, ...) end
        local source = caller()
        if rejectNul("RunConsoleCommand", name, source) then return end
        for i = 1, select("#", ...) do if rejectNul("RunConsoleCommand", select(i, ...), source) then return end end
        if checkTokens({name, ...}, source, 0) then return original(name, ...) end
    end
end
if playerMeta and playerMeta.ConCommand then
    local original = playerMeta.ConCommand
    playerMeta.ConCommand = function(self, command, ...)
        if not active() then return original(self, command, ...) end
        local source = caller()
        if rejectNul("Player.ConCommand", command, source) then return end
        if type(command) ~= "string" or checkCommands(command, source, 0) then return original(self, command, ...) end
    end
end
if game and game.ConsoleCommand then
    local original = game.ConsoleCommand
    game.ConsoleCommand = function(command, ...)
        if not active() then return original(command, ...) end
        local source = caller()
        if rejectNul("game.ConsoleCommand", command, source) then return end
        if type(command) ~= "string" or checkCommands(command, source, 0) then return original(command, ...) end
    end
end
if convarMeta then
    local getName = convarMeta.GetName
    for _, method in ipairs({"SetInt", "SetFloat", "SetBool", "SetString"}) do
        local original = convarMeta[method]
        if original and getName then
            convarMeta[method] = function(self, value, ...)
                -- pcall(cv.SetString, cv, value) puts a native frame first; name the Lua caller instead.
                local source = caller()
                if source:sub(1, 13) == "<dynamic Lua>" then source = externalCaller() end
                if allowPin(getName(self), value, source, false) then return original(self, value, ...) end
            end
        end
    end
    if pinned.mat_motion_blur_enabled == "0" then
        local blur = GetConVar("mat_motion_blur_enabled")
        for method, on in pairs({GetInt = 1, GetFloat = 1, GetBool = true, GetString = "1"}) do
            local original = convarMeta[method]
            if original then
                convarMeta[method] = function(self, ...)
                    if rawequal(self, blur) and active() then return on end
                    return original(self, ...)
                end
            end
        end
    end
end

-- The policy is self-contained because the verified early initializer embeds this file alone.
local policy = {inertTextures = setmetatable({}, {__mode = "k"}), inertMaterials = setmetatable({}, {__mode = "k"})}
do
    local sources = {
        ["lua/autorun/!!shaderlib.lua"] = true,
        ["lua/autorun/client/worldpos.lua"] = true,
        ["lua/autorun/client/depthbuffer.lua"] = true,
        ["lua/autorun/client/bumps_building.lua"] = true,
        ["lua/autorun/client/lightmaps_building.lua"] = true,
        ["lua/autorun/client/lut_writing.lua"] = true,
        ["lua/autorun/client/stencil_masks.lua"] = true,
        ["lua/autorun/client/translucent_crutch.lua"] = true,
        ["lua/autorun/client/fixes_for_workshop_addons.lua"] = true,
        ["lua/postprocess/shader_lib.lua"] = true,
        ["lua/postprocess/fxaa.lua"] = true,
        ["lua/postprocess/ssdo.lua"] = true,
        ["lua/postprocess/pp_ssr.lua"] = true,
    }
    function policy.effect(source)
        source = source:lower():gsub(":%d+$", "")
        return sources[source] or source:find("lua/lifemod/render/modules/", 1, true) == 1
    end
    function policy.csm(source)
        source = source:lower()
        return source:find("lua/realcsm/", 1, true) == 1 or source:find("lua/entities/edit_csm/", 1, true) == 1
    end
    -- Initialization still defines the add-ons' API and receives real engine-backed fallbacks.
    -- Rendering/reconstruction/world-mesh callbacks are inert even through cached hook.Call.
    function policy.skipCallback(fn, event)
        if event == "Initialize" or event == "InitReconstruction" or event == "InitPostReconstruction"
            or event == "OnScreenSizeChanged" or event == "OnReloaded" or event == "ShutDown" then return false end
        if not policy.effect(functionSource(fn)) then return false end
        reject("hook." .. tostring(event), "screen-space shader effect is inert under RTX", functionSource(fn))
        return true
    end
    local wrapperPaths = { ["lua/autorun/!!projected_texture_wrapper.lua"] = true,
        ["lua/autorun/!!dynamic_light_wrapper.lua"] = true }
    local function wrapper(source) return wrapperPaths[source:gsub(":%d+$", "")] end
    local function copy(tbl) local out = {} for k, v in pairs(tbl) do out[k] = v end return out end
    -- GShader repeatedly edits the shared native PT __index, nesting it once per created lamp.
    -- Its dlight wrapper also replaces native userdata metatables. Keep those edits in Lua copies.
    local findMeta = FindMetaTable
    FindMetaTable = function(name, ...)
        local result = findMeta(name, ...)
        if active() and wrapper(caller()) and type(result) == "table" then
            reject("FindMetaTable", "native light metatable edits isolated", caller())
            return copy(result)
        end
        return result
    end
    local getMeta, setMeta = debug.getmetatable, debug.setmetatable
    local privateMetas = setmetatable({}, {__mode = "k"})
    debug.getmetatable = function(obj)
        local result = getMeta(obj)
        if active() and wrapper(caller()) and type(result) == "table" then return privateMetas[obj] or copy(result) end
        return result
    end
    debug.setmetatable = function(obj, meta)
        if active() and wrapper(caller()) then
            reject("debug.setmetatable", "native light metatable replacement ignored", caller())
            privateMetas[obj] = meta
            return obj
        end
        return setMeta(obj, meta)
    end
end
-- Exact bundled virtual paths, checked against the indexed package inputs/companion by tests.
-- Source labels omit the add-on directory. This is a compatibility exemption, not authentication:
-- a colliding file or forged chunk label can bypass these material filters (ADR 0086).
do
    local bundled = {}
    for path in ([[
lua/advanced_bodygroup_tool/cl_i18n.lua
lua/advanced_bodygroup_tool/cl_uv_hide.lua
lua/advanced_bodygroup_tool/cl_vertex_keep_editor.lua
lua/advmat/cl_05_i18n.lua
lua/advmat/cl_19_help_i18n.lua
lua/advmat/cl_20_help.lua
lua/advmat/cl_23_backend.lua
lua/advmat/cl_27_rtx_bridge.lua
lua/advmat/cl_28_rtx_enhance.lua
lua/advmat/cl_29_rtx_normals.lua
lua/advmat/cl_30_theme.lua
lua/advmat/cl_31_windowux.lua
lua/advmat/cl_40_store.lua
lua/advmat/cl_41_rtx_store.lua
lua/advmat/cl_50_apply.lua
lua/advmat/cl_55_normalgen.lua
lua/advmat/cl_56_texops.lua
lua/advmat/cl_57_surfacegen.lua
lua/advmat/cl_58_meshuv.lua
lua/advmat/cl_59_assets.lua
lua/advmat/cl_60_texpicker.lua
lua/advmat/cl_61_import.lua
lua/advmat/cl_65_rows.lua
lua/advmat/cl_67_gendialog.lua
lua/advmat/cl_68_surfacedialog.lua
lua/advmat/cl_70_ui.lua
lua/advmat/cl_71_rtx_source.lua
lua/advmat/cl_72_canvas.lua
lua/advmat/cl_73_modelview.lua
lua/advmat/cl_74_texeditor.lua
lua/advmat/cl_75_rtx_nodes.lua
lua/advmat/cl_76_rtx_editor.lua
lua/advmat/cl_78_vmtexport.lua
lua/advmat/cl_80_browser.lua
lua/advmat/cl_88_dispatch.lua
lua/advmat/cl_90_probe.lua
lua/advmat/sh_00_config.lua
lua/advmat/sh_10_util.lua
lua/advmat/sh_15_mmd.lua
lua/advmat/sh_20_net.lua
lua/advmat/sh_25_vmt.lua
lua/advmat/sh_30_shaderdb.lua
lua/advmat/sh_31_shaderdb_ext.lua
lua/advmat/sh_35_matname.lua
lua/advmat/sh_36_rtx_schema.lua
lua/advmat/sh_40_gen.lua
lua/advmat/sh_41_sel.lua
lua/advmat/sh_42_gen_normal.lua
lua/advmat/sh_43_texedit.lua
lua/advmat/sh_44_gen_surface.lua
lua/advmat/sh_45_assets.lua
lua/advmat/sh_50_finalise.lua
lua/advmat/sv_29_assets.lua
lua/advmat/sv_30_store.lua
lua/advmat/sv_31_rtx_store.lua
lua/advmat/sv_32_rtx_tool.lua
lua/advmat/sv_40_apply.lua
lua/autorun/!!!!nativeloader_engine_guard.lua
lua/autorun/_nativeloader_effect_categories.lua
lua/autorun/_nativeloader_guard.lua
lua/autorun/advanced_bodygroup_tool.lua
lua/autorun/advmat_loader.lua
lua/autorun/bullet_break_simulator_loader.lua
lua/autorun/cl_rtx.lua
lua/autorun/client/cl_remix_portals.lua
lua/autorun/client/cl_render_core.lua
lua/autorun/client/hl2rtx_model_compat_viewmodels.lua
lua/autorun/client/nativeloader.lua
lua/autorun/client/nativeloader_dragdrop.lua
lua/autorun/client/nativeloader_eye_whites.lua
lua/autorun/client/nativeloader_guide.lua
lua/autorun/client/nativeloader_imported_normals.lua
lua/autorun/client/nativeloader_imported_parts.lua
lua/autorun/client/nativeloader_menu.lua
lua/autorun/client/nativeloader_mmd_alpha.lua
lua/autorun/client/nativeloader_model_layers.lua
lua/autorun/client/nativeloader_motion_tab.lua
lua/autorun/client/nativeloader_pbr_progress.lua
lua/autorun/client/nativeloader_toolgun.lua
lua/autorun/client/nativeloader_upscaling_hint.lua
lua/autorun/client/nativeloader_vram.lua
lua/autorun/client/removehalo.lua
lua/autorun/client/rtx_agent.lua
lua/autorun/client/rtx_debug.lua
lua/autorun/matdebug.lua
lua/autorun/mmd_vmd_npc.lua
lua/autorun/mmdhl.lua
lua/autorun/nativeloader_defaults.lua
lua/autorun/nativeloader_i18n.lua
lua/autorun/nativeloader_lag_report.lua
lua/autorun/nativeloader_sky.lua
lua/autorun/nlglass.lua
lua/autorun/poolrooms_rtx.lua
lua/autorun/rtx_water.lua
lua/autorun/server/hl2rtx_model_compat.lua
lua/autorun/server/sv_portals_pvs.lua
lua/autorun/server/sv_prop_teleport.lua
lua/autorun/sh_detours.lua
lua/autorun/sh_player_teleport.lua
lua/autorun/sh_rtx.lua
lua/autorun/sv_rtx.lua
lua/autorun/tmc.lua
lua/bullet_break_simulator/cl_10_i18n.lua
lua/bullet_break_simulator/cl_20_filters.lua
lua/bullet_break_simulator/cl_21_mdl_bodyparts.lua
lua/bullet_break_simulator/cl_22_shape.lua
lua/bullet_break_simulator/cl_25_profiler.lua
lua/bullet_break_simulator/cl_29_mesh_preparation.lua
lua/bullet_break_simulator/cl_30_overlay.lua
lua/bullet_break_simulator/cl_32_mesh_persistence.lua
lua/bullet_break_simulator/cl_39_material_safety.lua
lua/bullet_break_simulator/cl_40_damage.lua
lua/bullet_break_simulator/cl_90_settings.lua
lua/bullet_break_simulator/sh_00_config.lua
lua/bullet_break_simulator/sh_10_network.lua
lua/bullet_break_simulator/sv_20_hits.lua
lua/entities/gmod_lamp.lua
lua/entities/gmod_light.lua
lua/entities/mmdhl_attach_link.lua
lua/entities/mmdhl_prop/cl_init.lua
lua/entities/mmdhl_prop/init.lua
lua/entities/mmdhl_prop/shared.lua
lua/entities/mmdhl_ragdoll/cl_init.lua
lua/entities/mmdhl_ragdoll/init.lua
lua/entities/mmdhl_ragdoll/shared.lua
lua/entities/mmdhl_ragdoll/tool_api.lua
lua/entities/nlglass_pane/cl_init.lua
lua/entities/nlglass_pane/init.lua
lua/entities/nlglass_pane/shared.lua
lua/entities/remix_rt_light/cl_init.lua
lua/entities/remix_rt_light/init.lua
lua/entities/remix_rt_light/shared.lua
lua/entities/remix_sky_editor/cl_init.lua
lua/entities/remix_sky_editor/init.lua
lua/entities/remix_sky_editor/shared.lua
lua/entities/rtx_pseudoplayer.lua
lua/entities/rtx_pseudoweapon.lua
lua/entities/seamless_portal/cl_init.lua
lua/entities/seamless_portal/init.lua
lua/entities/seamless_portal/sh_init.lua
lua/includes/modules/niknaks.lua
lua/mmd_vmd_npc/cl_camera.lua
lua/mmd_vmd_npc/cl_flashlight.lua
lua/mmd_vmd_npc/cl_import_bake.lua
lua/mmd_vmd_npc/cl_import_data.lua
lua/mmd_vmd_npc/cl_importer.lua
lua/mmd_vmd_npc/cl_menu.lua
lua/mmd_vmd_npc/cl_radial.lua
lua/mmd_vmd_npc/sh_core.lua
lua/mmd_vmd_npc/sv_cache.lua
lua/mmd_vmd_npc/sv_commands.lua
lua/mmdhl/actors.lua
lua/mmdhl/bodygroups.lua
lua/mmdhl/bone_mapper.lua
lua/mmdhl/bone_mapper_rules.lua
lua/mmdhl/bone_mapper_ui.lua
lua/mmdhl/carrier.lua
lua/mmdhl/client.lua
lua/mmdhl/client_ragdolls.lua
lua/mmdhl/collision_editor.lua
lua/mmdhl/compat.lua
lua/mmdhl/compatibility_policy.lua
lua/mmdhl/debug.lua
lua/mmdhl/entity_editor.lua
lua/mmdhl/faceposer.lua
lua/mmdhl/file_access.lua
lua/mmdhl/first_person.lua
lua/mmdhl/i18n.lua
lua/mmdhl/installation.lua
lua/mmdhl/installation_ui.lua
lua/mmdhl/instances.lua
lua/mmdhl/library.lua
lua/mmdhl/materials.lua
lua/mmdhl/menu.lua
lua/mmdhl/names.lua
lua/mmdhl/native_policy.lua
lua/mmdhl/native_render.lua
lua/mmdhl/native_tools.lua
lua/mmdhl/performance.lua
lua/mmdhl/persistence.lua
lua/mmdhl/physics_editor.lua
lua/mmdhl/physics_editor_ui.lua
lua/mmdhl/physics_lod.lua
lua/mmdhl/physics_profile.lua
lua/mmdhl/physics_reset.lua
lua/mmdhl/physics_settings.lua
lua/mmdhl/player_copies.lua
lua/mmdhl/props/collision.lua
lua/mmdhl/props/editor.lua
lua/mmdhl/props/library.lua
lua/mmdhl/props/render.lua
lua/mmdhl/props/server.lua
lua/mmdhl/props/shared.lua
lua/mmdhl/props/tool.lua
lua/mmdhl/scene_sharing.lua
lua/mmdhl/secondary_backend.lua
lua/mmdhl/secondary_collision.lua
lua/mmdhl/secondary_water.lua
lua/mmdhl/server.lua
lua/mmdhl/server_settings.lua
lua/mmdhl/settings.lua
lua/mmdhl/sharing.lua
lua/mmdhl/terms.lua
lua/mmdhl/ui.lua
lua/mmdhl/workshop.lua
lua/mmdhl/workshop_export.lua
lua/nativeloader/classic_defaults.lua
lua/nativeloader/engine_guard_words.lua
lua/nativeloader/eye_white_names.lua
lua/nativeloader/eye_white_vtf.lua
lua/nativeloader/guide_pages.lua
lua/nativeloader/i18n.lua
lua/nativeloader/menu/load_accel.lua
lua/nativeloader/menu/loading_status.lua
lua/nativeloader/menu/multiplayer_notice.lua
lua/nativeloader/menu/unsubscribed_notice.lua
lua/nativeloader/notice.lua
lua/nativeloader/painted_shadows.lua
lua/nativeloader/sky_model.lua
lua/nativeloader/solid_hair.lua
lua/nativeloader/weather_presets.lua
lua/niknaks/framework/sh_localbsp.lua
lua/niknaks/modules/sh_bignumber.lua
lua/niknaks/modules/sh_bitbuffer.lua
lua/niknaks/modules/sh_bsp_brushes.lua
lua/niknaks/modules/sh_bsp_entities.lua
lua/niknaks/modules/sh_bsp_faces.lua
lua/niknaks/modules/sh_bsp_leafs.lua
lua/niknaks/modules/sh_bsp_module.lua
lua/niknaks/modules/sh_bsp_pvspas.lua
lua/niknaks/modules/sh_bsp_staticprops.lua
lua/niknaks/modules/sh_bsp_trace.lua
lua/niknaks/modules/sh_bsp_worldlights.lua
lua/niknaks/modules/sh_color_extended.lua
lua/niknaks/modules/sh_datapackage.lua
lua/niknaks/modules/sh_datetime.lua
lua/niknaks/modules/sh_enums.lua
lua/niknaks/modules/sh_file_extended.lua
lua/niknaks/modules/sh_hooks.lua
lua/niknaks/modules/sh_linq_module.lua
lua/niknaks/modules/sh_model_extended.lua
lua/niknaks/modules/sh_randomizer.lua
lua/niknaks/modules/sh_sound_module.lua
lua/niknaks/modules/sh_timedelta.lua
lua/niknaks/modules/sh_util_extended.lua
lua/niknaks/submodules/ai/sh_file.lua
lua/niknaks/submodules/ai/sh_map.lua
lua/niknaks/submodules/ai/sh_node.lua
lua/niknaks/submodules/ai/sh_pathfinder.lua
lua/niknaks/submodules/sh_submodules.lua
lua/nlglass/client.lua
lua/nlglass/config.lua
lua/nlglass/damage.lua
lua/nlglass/debris.lua
lua/nlglass/debris_batches.lua
lua/nlglass/debris_bullets.lua
lua/nlglass/debris_detail.lua
lua/nlglass/debris_draw.lua
lua/nlglass/debris_expiry.lua
lua/nlglass/debris_fallback.lua
lua/nlglass/debris_melee.lua
lua/nlglass/debris_mesh.lua
lua/nlglass/debris_scene.lua
lua/nlglass/debris_settings.lua
lua/nlglass/debris_view.lua
lua/nlglass/fracture.lua
lua/nlglass/geometry.lua
lua/nlglass/i18n.lua
lua/nlglass/i18n_data.lua
lua/nlglass/menu.lua
lua/nlglass/protocol.lua
lua/nlglass/server.lua
lua/nlglass/world.lua
lua/patcher/addons/cl_arc9.lua
lua/patcher/addons/cl_mwbase.lua
lua/patcher/cl_init.lua
lua/patcher/cl_intercepts.lua
lua/patcher/sh_core.lua
lua/patcher/tests/cl_mwbase_dependency_tests.lua
lua/patcher/tests/cl_patcher_core_tests.lua
lua/patcher/tests/cl_patcher_intercepts_tests.lua
lua/patcher/tests/cl_patcher_loader_tests.lua
lua/poolrooms_rtx/cl_lights_data.lua
lua/poolrooms_rtx/cl_main.lua
lua/poolrooms_rtx/sh_config.lua
lua/remixlua/cl/cl_fix_bft_materials.lua
lua/remixlua/cl/cl_fix_pbr_materials.lua
lua/remixlua/cl/cl_fix_refract_materials.lua
lua/remixlua/cl/cl_fix_solid_color_materials.lua
lua/remixlua/cl/cl_map_fixes.lua
lua/remixlua/cl/cl_map_markers.lua
lua/remixlua/cl/cl_material_inspector.lua
lua/remixlua/cl/cl_material_pipeline.lua
lua/remixlua/cl/cl_nonapi_flashlight.lua
lua/remixlua/cl/cl_remove_detail_textures.lua
lua/remixlua/cl/cl_rtx_light_updater.lua
lua/remixlua/cl/cl_rtx_material_fixer.lua
lua/remixlua/cl/cl_rtx_misc.lua
lua/remixlua/cl/cl_rtx_settings.lua
lua/remixlua/cl/cl_rtx_topbr_conversion.lua
lua/remixlua/cl/cl_viewmodel_materials.lua
lua/remixlua/cl/customrender/cl_2d_skybox_renderer.lua
lua/remixlua/cl/customrender/cl_build_progress.lua
lua/remixlua/cl/customrender/cl_displacement_renderer.lua
lua/remixlua/cl/customrender/cl_rtx_meshed_world_renderer.lua
lua/remixlua/cl/customrender/cl_rtx_skybox_boundary_renderer.lua
lua/remixlua/cl/customrender/cl_static_prop_renderer.lua
lua/remixlua/cl/customrender/render_core.lua
lua/remixlua/cl/remixapi/cl_physgun_color_sync.lua
lua/remixlua/cl/remixapi/cl_remix_category_0_manager.lua
lua/remixlua/cl/remixapi/cl_remix_category_1_pseudoplayer.lua
lua/remixlua/cl/remixapi/cl_remix_category_debug.lua
lua/remixlua/cl/remixapi/cl_remix_flashlight.lua
lua/remixlua/cl/remixapi/cl_remix_light_cmd.lua
lua/remixlua/cl/remixapi/cl_remix_map_configs.lua
lua/remixlua/cl/remixapi/debug_hash_hud.lua
lua/remixlua/cl/remixapi/rtx_hash_lookup.lua
lua/remixlua/cl/remixapi/wrappers/cl_remix_api_map_lights.lua
lua/remixlua/cl/remixapi/wrappers/cl_remix_api_map_lights_menu.lua
lua/remixlua/cl/remixapi/wrappers/cl_remix_dynamiclight_wrapper.lua
lua/remixlua/cl/remixapi/wrappers/cl_remix_dynamiclight_wrapper_menu.lua
lua/remixlua/cl/remixapi/wrappers/cl_remix_light_wrapper.lua
lua/remixlua/cl/remixapi/wrappers/cl_remix_light_wrapper_menu.lua
lua/remixlua/cl/remixapi/wrappers/cl_remix_maplight_animator.lua
lua/remixlua/cl/remixapi/wrappers/cl_remix_projectedtexture_wrapper.lua
lua/remixlua/cl/remixapi/wrappers/cl_remix_projectedtexture_wrapper_menu.lua
lua/remixlua/sh/sh_flashlight_override.lua
lua/remixlua/sv/sv_nonapi_flashlight.lua
lua/remixlua/sv/sv_remix_flashlight.lua
lua/remixlua/sv/sv_remix_maplight_bridge.lua
lua/remixlua/sv/sv_remove_entities.lua
lua/remixlua/sv/sv_skybox_fix.lua
lua/rtx_water/cl_bodies.lua
lua/rtx_water/cl_core.lua
lua/rtx_water/cl_data.lua
lua/rtx_water/cl_menu.lua
lua/rtx_water/cl_native.lua
lua/rtx_water/cl_ripples.lua
lua/rtx_water/cl_splash.lua
lua/rtx_water/cl_surface.lua
lua/rtx_water/sv_bullets.lua
lua/tmc/init.lua
lua/tmc/types.lua
lua/unittest/niknaks/bignumber.lua
lua/unittest/niknaks/bitbuffer.lua
lua/unittest/niknaks/bsp.lua
lua/unittest/niknaks/color.lua
lua/unittest/niknaks/datetime.lua
lua/unittest/niknaks/gunit_emmy.lua
lua/unittest/niknaks/linq.lua
lua/unittest/niknaks/main.lua
lua/unittest/niknaks/timedelta.lua
lua/weapons/gmod_tool/stools/advanced_bodygroup.lua
lua/weapons/gmod_tool/stools/advmateditor.lua
lua/weapons/gmod_tool/stools/mmd_vmd_npc.lua
lua/weapons/gmod_tool/stools/mmdhl_prop.lua
lua/weapons/gmod_tool/stools/portal_creator_tool.lua
lua/weapons/gmod_tool/stools/portal_fitter_tool.lua
lua/weapons/gmod_tool/stools/portal_resizer_tool.lua
lua/weapons/gmod_tool/stools/procedural_glass_tool.lua
lua/weapons/gmod_tool/stools/remix_rt_light_bonemerge.lua
lua/weapons/gmod_tool/stools/remix_rt_light_cylinder.lua
lua/weapons/gmod_tool/stools/remix_rt_light_disk.lua
lua/weapons/gmod_tool/stools/remix_rt_light_distant.lua
lua/weapons/gmod_tool/stools/remix_rt_light_rect.lua
lua/weapons/gmod_tool/stools/remix_rt_light_sphere.lua
lua/weapons/portal_gun.lua
lua/weapons/weapon_mmdhl.lua
    ]]):gmatch("%S+") do bundled[path] = true end
    function policy.bundled(source) return bundled[source:lower():gsub(":%d+$", "")] == true end
end
local nativeRender = {}
for name, value in pairs(render or {}) do nativeRender[name] = value end
local nativeCam = {}
for name, value in pairs(cam or {}) do nativeCam[name] = value end
local nativeRT, nativeRTEx, nativeMaterial, nativeCreate = GetRenderTarget, GetRenderTargetEx, Material, CreateMaterial
local function canonical(name) return name:gsub("\\", "/"):lower():gsub("%.[^./]*$", "") end
function policy.reserved(name)
    -- GLua's type() can report "ITexture", rather than LuaJIT's ordinary "userdata".
    if name ~= nil and type(name) ~= "string" then
        local ok, value = pcall(function() return name:GetName() end)
        if not ok then return false end
        name = value
    end
    if type(name) ~= "string" then return false end
    local base = canonical(name):match("([^/]+)$") or ""
    return base:match("^_rt_shadowdepthtexture") or base:match("^_rt_resolvedfullframedepth")
        or base:match("^_nativeloader_inert_rt")
end
-- R27 (ADR 0141). Names of render targets the guard refused and allocated nothing for: a material whose base texture
-- names one would show a missing texture. Exact names only (a .vtf suffix aside), never an engine `_rt_` target (those
-- exist whatever an add-on asks), cleared when the name is allocated later, at most 1,024.
local refusedNames, refusedCount = {}, 0
local function targetKey(name)
    local key = name:gsub("\\", "/"):lower()
    return (key:gsub("%.vtf$", ""))
end
function policy.refuseName(name)
    if type(name) ~= "string" or #name == 0 or #name > 256 or name:find("%z") or refusedCount >= 1024 then return end
    local key = targetKey(name)
    if key:find("^_rt_") or key:find("/_rt_") or refusedNames[key] then return end
    refusedNames[key], refusedCount = true, refusedCount + 1
end
function policy.allowName(name)
    if type(name) ~= "string" then return end
    local key = targetKey(name)
    if refusedNames[key] then refusedNames[key], refusedCount = nil, refusedCount - 1 end
end
function policy.refusedName(value)
    if refusedCount == 0 or value == nil then return false end
    if type(value) ~= "string" then
        local ok, name = pcall(function() return value:GetName() end)
        if not ok or type(name) ~= "string" then return false end
        value = name
    end
    return refusedNames[targetKey(value)] == true
end
-- R27 (ADR 0141). Materials that lost their base texture: Lua created them (CreateMaterial) and the guard refused the
-- texture their `$basetexture` was set to, so drawn they would show their placeholder (HUD Mk.2's
-- models/debug/debugwhite over the whole screen). Untrusted bindings of them bind the transparent material until a
-- `$basetexture` binding goes through. Kept by material name, since two Lua objects can stand for one material; loaded
-- materials are shared (the world, other add-ons) and are never marked.
local materialNames = setmetatable({}, {__mode = "k"})
local function materialKey(mat)
    if mat == nil then return nil end
    local key = materialNames[mat]
    if key ~= nil then return key or nil end
    local ok, name = pcall(function() return mat:GetName() end)
    key = ok and type(name) == "string" and (name:lower():gsub("^!", "")) or false
    local kind = type(mat)
    if kind == "userdata" or kind == "table" or kind == "IMaterial" then materialNames[mat] = key end
    return key or nil
end
local lostBase, createdNames, createdCount = {}, {}, 0
function policy.lost(mat)
    if mat == nil or next(lostBase) == nil then return false end
    local key = materialKey(mat)
    return key ~= nil and lostBase[key] == true
end
function policy.setLost(mat, on)
    if not on and next(lostBase) == nil then return end
    local key = materialKey(mat)
    if key == nil then return end
    if not on then lostBase[key] = nil
    elseif createdNames[key] then lostBase[key] = true end
end
-- Returns whether this is the first creation of that name (CreateMaterial returns a cached material for a repeat).
function policy.created(name)
    if type(name) ~= "string" then return false end
    local key = name:lower():gsub("^!", "")
    if createdNames[key] or createdCount >= 8192 then return false end
    createdNames[key], createdCount = true, createdCount + 1
    return true
end
do
    local meta = FindMetaTable("ProjectedTexture")
    local remove = meta and meta.Remove
    if remove then
        meta.Remove = function(self, ...)
            local result = pack(remove(self, ...))
            if active() then
                -- GShader's Remove replacement lives in its private copy. Retire its public
                -- caches here instead, otherwise that list retains every removed native lamp.
                local lights, indices, cache = rawget(_G, "ENV_PROJTEXS"), rawget(_G, "ENV_PROJTEXS_I"), rawget(_G, "ptCache")
                if type(lights) == "table" and type(indices) == "table" and type(cache) == "table" then
                    rawset(cache, self, nil)
                    local count, kept = #lights, 0
                    for i = 1, count do
                        local light = rawget(lights, i)
                        local ok, valid = pcall(IsValid, light)
                        if light ~= self and ok and valid then kept = kept + 1 rawset(lights, kept, light) end
                    end
                    for i = kept + 1, count do rawset(lights, i, nil) end
                    for id in pairs(indices) do rawset(indices, id, nil) end
                    for i = 1, kept do
                        local id = rawget(cache, rawget(lights, i))
                        if id ~= nil then rawset(indices, id, i) end
                    end
                end
            end
            return unpack(result, 1, result.n)
        end
    end
    for _, method in ipairs({"Update", "SetEnableShadows", "SetFOV", "SetHorizontalFOV", "SetVerticalFOV",
        "SetNearZ", "SetFarZ", "SetShadowDepthBias", "SetShadowSlopeScaleDepthBias", "SetBrightness"}) do
        local original = meta and meta[method]
        if original then
            meta[method] = function(self, ...)
                if active() then
                    local source, value = caller(), ...
                    if policy.csm(source) and (method == "Update" or method == "SetEnableShadows") then
                        reject("ProjectedTexture." .. method, "Real CSM raster shadow pass is inert under RTX", source) return
                    end
                    if method ~= "Update" and method ~= "SetEnableShadows" and (not finite(value)
                        or (method:find("FOV", 1, true) and (value <= 0 or value >= 180))) then
                        reject("ProjectedTexture." .. method, "invalid projection parameter ignored", source) return
                    end
                end
                return original(self, ...)
            end
        end
    end
end
function policy.inertTarget()
    if policy.target then return policy.target end
    local ok, target
    if nativeRTEx then
        ok, target = pcall(nativeRTEx, "_nativeloader_inert_rt_v1", 1, 1, 8, 2, 0, 0, 0)
    elseif nativeRT then ok, target = pcall(nativeRT, "_nativeloader_inert_rt_v1", 1, 1) end
    -- An allocator can itself fail (Lua error, not native/GPU recovery). Reuse an engine texture.
    if (not ok or not target) and nativeRender.GetScreenEffectTexture then
        ok, target = pcall(nativeRender.GetScreenEffectTexture)
    end
    if ok and target then policy.target = target policy.inertTextures[target] = true end
    return policy.target
end
function policy.inertMaterial()
    if not policy.material then
        policy.material = nativeCreate("_nativeloader_inert_material_v1", "UnlitGeneric", {
            ["$basetexture"] = "vgui/white", ["$translucent"] = "1", ["$alpha"] = "0", ["$ignorez"] = "1"})
        policy.inertMaterials[policy.material] = true
    end
    return policy.material
end
-- A reviewed color subset, not every IMAGE_FORMAT enum exported by this engine or by an add-on.
-- Raw R32F27 remains supported for MMDHL. Depth/INTZ/NULL/compressed/RGB32F/R16F and unreviewed
-- formats become the single shared RGBA8 target, even when an add-on exports their enum names.
do
    local formats = {[-1] = 4, [0] = 4, [1] = 4, [2] = 4, [3] = 4, [4] = 2,
        [11] = 4, [12] = 4, [16] = 4, [24] = 8, [25] = 8, [27] = 4}
    -- Stock D3D9 enum values: late multiplayer globals may already have been replaced.
    local fullFrame = {[3] = true, [4] = true, [6] = true}
    -- R27 (ADR 0141): the 8-bit colour formats a "depth-only" request may come in as a colour target. Float, 16-bit,
    -- R32F and default formats are what real depth passes use, and keep the inert target.
    local colourOnly = {[0] = true, [1] = true, [2] = true, [3] = true, [4] = true, [11] = true, [12] = true, [16] = true}
    local allocations, counts, bytes, total = {}, {}, {}, 0
    state.allocations_by_source, state.allocation_bytes_by_source = counts, bytes
    local function check(name, w, h, sizeMode, format, source)
        if type(name) ~= "string" or #name == 0 or #name > 256 or name:find("%z") then return "invalid target name" end
        if policy.reserved(name) then return "engine-owned shadow/depth target kept unchanged" end
        if policy.effect(source) then return "screen-space shader target is inert under RTX" end
        w, h = whole(w), whole(h)
        if not w or not h then return "target dimensions must be finite numbers" end
        local fw, fh = w, h
        if fullFrame[sizeMode] then
            if w < -1 or h < -1 or w == 0 or h == 0 then return "invalid full-frame dimensions" end
            fw, fh = ScrW(), ScrH()
            if sizeMode == 6 and finite(fw) and finite(fh) and fw > 0 and fh > 0 then
                fw, fh = 2 ^ math.ceil(math.log(fw) / math.log(2)), 2 ^ math.ceil(math.log(fh) / math.log(2))
            end
        elseif w <= 0 or h <= 0 then return "target dimensions must be positive" end
        if not finite(fw) or not finite(fh) or fw <= 0 or fh <= 0 or fw > 16384 or fh > 16384
            or fw * fh > 67108864 then return "render-target allocation exceeds the guard limit" end
        if not formats[format] then return "unreviewed RTX color format; using inert RGBA8 target" end
        local key, owner = canonical(name), source:gsub(":%d+$", "")
        local cost = fw * fh * formats[format]
        if not allocations[key] then
            if (counts[owner] or 0) >= 128 then return "caller render-target name limit" end
            if cost > 134217728 or (bytes[owner] or 0) + cost > 536870912 or total + cost > 1073741824 then
                return "render-target byte budget exceeded"
            end
            return nil, key, owner, cost
        end
    end
    local function allocated(target, key, owner, cost, name)
        if not target or not key then return end
        policy.allowName(name)
        allocations[key], counts[owner] = true, (counts[owner] or 0) + 1
        bytes[owner], total = (bytes[owner] or 0) + cost, total + cost
        state.allocation_bytes = total
    end
    local function fallback(api, reason, source, name)
        reject(api, reason, source)
        -- A name already allocated natively keeps its texture: only a name the engine never got is refused by name.
        if type(name) == "string" and not policy.reserved(name) and not allocations[canonical(name)] then
            policy.refuseName(name)
        end
        -- The getter only fetches Source's texture; NeedsDepthPass is suppressed below. Never
        -- call GetRenderTarget[Ex] with the reserved name (that may reconfigure a live resource).
        if type(name) == "string" and canonical(name) == "_rt_resolvedfullframedepth"
            and nativeRender.GetResolvedFullFrameDepth then return nativeRender.GetResolvedFullFrameDepth() end
        return policy.inertTarget()
    end
    if nativeRT then
        GetRenderTarget = function(name, w, h, ...)
            if not active() then return nativeRT(name, w, h, ...) end
            local source = caller()
            local reason, key, owner, cost = check(name, w, h, nil, -1, source)
            if reason then return fallback("GetRenderTarget", reason, source, name) end
            local result = pack(nativeRT(name, w, h, ...))
            allocated(result[1], key, owner, cost, name)
            return unpack(result, 1, result.n)
        end
    end
    if nativeRTEx then
        GetRenderTargetEx = function(name, w, h, size, depth, flags, rtFlags, format, ...)
            if not active() then return nativeRTEx(name, w, h, size, depth, flags, rtFlags, format, ...) end
            local source, reason = caller()
            if not integer(size) or size < 0 or size > 9 then reason = "unknown size mode"
            elseif not integer(depth) or depth < 0 or depth > 3 then reason = "unknown depth mode"
            elseif depth == 3 and not colourOnly[format] then reason = "depth-only targets are unsupported under RTX"
            elseif not integer(flags) or not integer(rtFlags) or flags < 0 or flags > 4294967295
                or rtFlags < 0 or rtFlags > 4294967295 then reason = "flags must be finite unsigned integers"
            elseif math.floor(flags / 16384) % 2 == 1 then reason = "cubemap render targets are unsafe" end
            if reason then return fallback("GetRenderTargetEx", reason, source, name) end
            local key, owner, cost
            reason, key, owner, cost = check(name, w, h, size, format, source)
            if reason then return fallback("GetRenderTargetEx", reason, source, name) end
            -- R27 (ADR 0141): "depth-only" in a colour format is how some add-ons ask for a colour target they draw
            -- into (HUD Mk.2 draws its whole HUD into one, then that target over the screen; stock GMod gives them
            -- a colour target). Under RTX it becomes a colour target with its own depth buffer, never a depth texture.
            if depth == 3 then
                depth = 1
                report("adapted", "GetRenderTargetEx", "depth-only colour target given its own depth buffer under RTX", source)
            end
            local result = pack(nativeRTEx(name, w, h, size, depth, flags, rtFlags, format, ...))
            allocated(result[1], key, owner, cost, name)
            return unpack(result, 1, result.n)
        end
    end
end
local unsupported = {depthwrite = true, screenspace_general = true, screenspace_general_dx9 = true,
    lux_custom = true, lux_screenspace_general = true}
local shaderNames = setmetatable({}, {__mode = "k"})
local function shaderMethod(mat) return mat.GetShader end
local function shaderName(mat)
    if mat == nil then return end
    local name = shaderNames[mat]
    if name ~= nil then return name or nil end
    name = false
    local ok, method = pcall(shaderMethod, mat)
    if ok and type(method) == "function" then
        local success, value = pcall(method, mat)
        if success and type(value) == "string" then name = value:lower() end
    end
    local kind = type(mat)
    if kind == "userdata" or kind == "table" or kind == "IMaterial" then shaderNames[mat] = name end
    return name or nil
end
function policy.shader(shader, data)
    if type(shader) == "string" and (unsupported[shader:lower()] or shader:lower():match("^lux_")
        or shader:lower():match("^screenspace_general") or shader:find("%z")) then return true end
    if type(data) == "table" then
        for key, value in pairs(data) do
            if type(key) == "string" and (key:lower() == "$pixshader" or key:lower() == "$vertexshader") then return true end
            if policy.reserved(value) then return true end
        end
    end
    return false
end
do
    local checks, creationHints = setmetatable({}, {__mode = "k"}), setmetatable({}, {__mode = "k"})
    -- Inspect only at an untrusted binding. Loading/reading a material is native, including
    -- ExoPBR/GPBR conversion and MMDHL's immediate shaders. No guard VMT/FS lookup is needed.
    function policy.incompatibleMaterial(mat)
        if mat == nil then return false end
        if policy.inertMaterials[mat] or creationHints[mat] or policy.lost(mat) then return true end
        if checks[mat] ~= nil then return checks[mat] end
        local denied = policy.shader(shaderName(mat))
        if not denied then
            local ok, method = pcall(function() return mat.GetString end)
            if ok and type(method) == "function" then
                for _, key in ipairs({"$pixshader", "$vertexshader", "$basetexture"}) do
                    local success, value = pcall(method, mat, key)
                    if success and type(value) == "string" and value ~= "" then
                        if key ~= "$basetexture" or policy.reserved(value) then denied = true break end
                    end
                end
            end
        end
        checks[mat] = denied
        return denied
    end
    if nativeCreate then
        CreateMaterial = function(name, shader, data, ...)
            local on = active()
            if on and (rejectNul("CreateMaterial", name) or rejectNul("CreateMaterial", shader)) then
                return policy.inertMaterial()
            end
            local result = pack(nativeCreate(name, shader, data, ...))
            -- CreateMaterial caches by name: safe parameters on a later call cannot clear a hint.
            if on and result[1] and policy.shader(shader, data) then creationHints[result[1]] = true end
            -- R27: a material first created with a refused target's name as its base texture has lost it already.
            if result[1] ~= nil and policy.created(name) and on and type(data) == "table" then
                for key, value in pairs(data) do
                    if type(key) == "string" and key:lower() == "$basetexture" and policy.refusedName(value) then
                        policy.setLost(result[1], true)
                        break
                    end
                end
            end
            return unpack(result, 1, result.n)
        end
    end
    if nativeMaterial then
        Material = function(path, ...)
            if active() and rejectNul("Material", path) then return policy.inertMaterial() end
            return nativeMaterial(path, ...)
        end
    end
    local meta = FindMetaTable("IMaterial")
    for _, method in ipairs({"SetShader", "SetShaderAndParams", "SetTexture", "SetString", "SetInt", "SetFloat",
        "SetVector", "SetVector4D", "SetMatrix", "SetUndefined", "SetDynamicImage", "Recompute"}) do
        local original = meta and meta[method]
        if original then
            meta[method] = function(self, ...)
                local key, value = ...
                if active() then
                    local source = caller()
                    local denied = policy.inertMaterials[self]
                    local base, valueDenied = false, false
                    if not policy.bundled(source) then
                        denied = denied or policy.effect(source)
                        if method == "SetShader" or method == "SetShaderAndParams" then
                            denied = denied or policy.shader(key, value)
                        elseif method == "SetTexture" or method == "SetString" then
                            base = type(key) == "string" and key:lower() == "$basetexture"
                            valueDenied = policy.inertTextures[value] or policy.reserved(value)
                                or (base and policy.refusedName(value)) or false
                            denied = denied or valueDenied
                        end
                    end
                    if denied then
                        -- R27: the refused texture itself (not the caller) leaves the material's placeholder in place,
                        -- which then draws nothing instead (policy.lost).
                        if base and valueDenied and not policy.inertMaterials[self] and not policy.effect(source) then
                            policy.setLost(self, true)
                        end
                        reject("IMaterial." .. method, "incompatible material mutation ignored", source) return
                    end
                end
                shaderNames[self], checks[self] = nil, nil
                if method == "SetShader" or method == "SetShaderAndParams" then creationHints[self] = nil end
                if method == "SetShaderAndParams" or ((method == "SetTexture" or method == "SetString")
                    and type(key) == "string" and key:lower() == "$basetexture") then
                    policy.setLost(self, false)
                end
                return original(self, ...)
            end
        end
    end
end
do
    local meta = FindMetaTable("Entity")
    -- Resolve named bindings through the native material cache, including !CreateMaterial names.
    -- Weak values and per-material decisions avoid extra lookups while the object is live.
    local boundPaths = setmetatable({}, {__mode = "v"})
    local function materialPath(path)
        if type(path) ~= "string" or path == "" or not nativeMaterial then return false end
        local mat = boundPaths[path]
        if not mat then
            mat = nativeMaterial(path:sub(1, 1) == "!" and path:sub(2) or path)
            boundPaths[path] = mat
        end
        return policy.incompatibleMaterial(mat)
    end
    for _, method in ipairs({"SetMaterial", "SetSubMaterial"}) do
        local original = meta and meta[method]
        if original then
            meta[method] = function(self, ...)
                local path = method == "SetMaterial" and select(1, ...) or select(2, ...)
                if active() then
                    local source = caller()
                    if rejectNul("Entity." .. method, path, source) then return end
                    if not policy.bundled(source) and (policy.effect(source) or materialPath(path)) then
                        reject("Entity." .. method, "unsupported world/entity material replacement ignored", source) return
                    end
                end
                return original(self, ...)
            end
        end
    end
    local setMaterial = surface and surface.SetMaterial
    if setMaterial then
        surface.SetMaterial = function(mat, ...)
            local on, source = active()
            if on then source = caller() end
            local trusted = on and policy.bundled(source)
            local lost = on and not trusted and policy.lost(mat)
            policy.surfaceInert = on and (policy.inertMaterials[mat] or lost or
                (not trusted and (policy.effect(source) or policy.incompatibleMaterial(mat))))
            if policy.surfaceInert then
                reject("surface.SetMaterial", lost and "its base texture was refused: drawn as nothing, not its placeholder"
                    or "unsupported RTX surface material", source)
                return setMaterial(policy.inertMaterial(), ...)
            end
            return setMaterial(mat, ...)
        end
    end
    -- R27: a texture bound by ID (draw.RoundedBox's corners, draw.TexturedQuad) replaces an earlier refused material,
    -- so the next textured draws are that texture's, not inert.
    local setTexture = surface and surface.SetTexture
    if setTexture then
        surface.SetTexture = function(...)
            policy.surfaceInert = false
            return setTexture(...)
        end
    end
    for _, method in ipairs({"DrawTexturedRect", "DrawTexturedRectUV", "DrawTexturedRectRotated", "DrawPoly"}) do
        local original = surface and surface[method]
        if original then
            surface[method] = function(...)
                if active() and (policy.surfaceInert or policy.effect(caller()) or (policy.suppressed and policy.suppressed())) then
                    reject("surface." .. method, "screen-space effect surface draw is inert", caller()) return
                end
                return original(...)
            end
        end
    end
end
for _, name in ipairs({"SetMaterial", "MaterialOverride", "BrushMaterialOverride", "WorldMaterialOverride"}) do
    local original = nativeRender[name]
    if original then
        render[name] = function(mat, ...)
            local on, source = active()
            if on then source = caller() end
            local trusted = on and policy.bundled(source)
            local lost = on and not trusted and policy.lost(mat)
            local denied = on and (policy.inertMaterials[mat] or lost or
                (not trusted and (policy.effect(source) or policy.incompatibleMaterial(mat))))
            if name == "SetMaterial" then policy.boundInert = denied end
            if name == "MaterialOverride" and not denied then policy.modelOverride = mat end
            if denied then
                reject("render." .. name, lost and "its base texture was refused: drawn as nothing, not its placeholder"
                    or "unsupported RTX shader draw", source)
                if name == "SetMaterial" then return original(policy.inertMaterial(), ...) end
                return
            end
            return original(mat, ...)
        end
    end
end
for _, name in ipairs({"DrawScreenQuad", "DrawScreenQuadEx", "DrawQuad", "DrawQuadEasy", "DrawSprite"}) do
    local original = nativeRender[name]
    if original then
        render[name] = function(...)
            if active() and (policy.boundInert or (policy.suppressed and policy.suppressed()) or policy.effect(caller())) then
                reject("render." .. name, "screen-space shader draw is inert under RTX", caller()) return
            end
            return original(...)
        end
    end
end
if nativeRender.RedownloadAllLightmaps then
    render.RedownloadAllLightmaps = function(...)
        if active() then reject("render.RedownloadAllLightmaps", "RTX lightmap rebuild ignored", caller()) return end
        return nativeRender.RedownloadAllLightmaps(...)
    end
end
-- Native color-material helpers also change the sprite/quad binding. A valid white binding must
-- clear an earlier rejected shader, including engines whose helpers do not call Lua SetMaterial.
for _, name in ipairs({"SetColorMaterial", "SetColorMaterialIgnoreZ"}) do
    local original = nativeRender[name]
    if original then
        render[name] = function(...)
            if active() and ((policy.suppressed and policy.suppressed()) or policy.effect(caller())) then
                reject("render." .. name, "inert effect material binding ignored", caller()) return
            end
            policy.boundInert = false
            return original(...)
        end
    end
end

-- Track only observed Lua pushes. Never guess native contexts or use mesh.End as an abort.
local frame, busy = nil, 0
local stacks = {rt = {}, camera = {}, clip = {}, model = {}}
-- An entry is live while its owner, or one of the owner's callers, is a protected callback still running.
local function live(action)
    local owner = action.owner
    while owner do
        if owner.completed == nil then return true end
        owner = owner.parent
    end
    return false
end
-- A push left open by code that failed outside a protected callback (the stock toolgun screen around
-- a tool's DrawToolScreen, an ENT:Draw error between cam.Start3D2D and End3D2D) is never popped.
-- At each frame boundary (a new FrameNumber, or PreRender where that is unavailable), forget the
-- tracked entries no running callback owns. Native state is neither guessed nor popped: only the
-- guard's own bookkeeping is resynchronized.
local function resync()
    for _, stack in pairs(stacks) do
        local kept = 0
        for i = 1, #stack do
            local action = stack[i]
            if live(action) then kept = kept + 1 stack[kept] = action else action.active = false end
        end
        for i = #stack, kept + 1, -1 do stack[i] = nil end
    end
end
local frameNumber, seenFrame = FrameNumber, nil
local function sync()
    if not frameNumber then return end
    local ok, now = pcall(frameNumber)
    if ok and now ~= seenFrame then
        if seenFrame ~= nil then resync() end
        seenFrame = now
    end
end
-- Only the running callback chain's own scopes count toward its limit; unowned leftovers never do.
local function chainDepth(stack)
    if not frame then return 0 end
    local count = 0
    for i = 1, #stack do if live(stack[i]) then count = count + 1 end end
    return count
end
-- A protected callback's entry render target, recorded when it first changes render targets.
local function noteTarget()
    local f = frame
    while f and f.haveTarget == nil do
        if nativeRender.GetRenderTarget then f.haveTarget, f.target = pcall(nativeRender.GetRenderTarget)
        else f.haveTarget = false end
        f = f.parent
    end
end
local function log(f)
    local list = f.actions
    if not list then list = {} f.actions = list end
    return list
end
local function pushed(kind, undo, replay)
    local action = {stack = stacks[kind], owner = frame, undo = undo, replay = replay, active = true}
    action.stack[#action.stack + 1] = action
    if frame then local list = log(frame) list[#list + 1] = action end
end
local function descendant(owner, ancestor)
    while owner do
        if owner == ancestor then return true end
        owner = owner.parent
    end
    return false
end
local function popped(kind)
    local action = table.remove(stacks[kind])
    if not action then return end
    action.active = false
    if action.skipped then return end -- no native state to replay after a virtual pop
    -- A completed Pre hook may deliberately leave a scope for its Post hook.
    -- If that later callback fails, retain the exact known RT push for replay.
    -- A descendant's scope was created after our entry and is already gone.
    if frame and action.owner ~= frame and not descendant(action.owner, frame) then
        local list = log(frame)
        list[#list + 1] = {restore = action, previous = stacks[kind][#stacks[kind]], depth = #stacks[kind]}
    end
end
local function invokeBusy(fn, ...)
    busy = busy + 1
    local result = pack(pcall(fn, ...))
    busy = busy - 1
    if not result[1] then error(result[2], 0) end
    return unpack(result, 2, result.n)
end
-- Failed pushes get a virtual scope. Its matching pop must not consume the caller's real
-- native scope. Repeated suppressed pushes share a counter, keeping runaway loops bounded.
function policy.suppressed()
    for _, stack in pairs(stacks) do
        local top = stack[#stack]
        if top and top.skipped then return true end
    end
    return false
end
-- Install each closer once. End and End3D share the native 3D counter; End2D has its own
-- painter counter. Capturing an already wrapped pop as an undo hid aliases (ADR 0122).
local closers = {}
local function pair(tbl, push, pop, kind, validate, family, describe)
    local registered = tbl and closers[tbl]
    if not registered and tbl then registered = {} closers[tbl] = registered end
    local first, last = tbl and tbl[push], registered and registered[pop] or (tbl and tbl[pop])
    if not first or not last then return end
    family = family or kind
    tbl[push] = function(...)
        if busy > 0 then return first(...) end
        sync()
        local scopeFamily, undo = family, last
        if describe then scopeFamily, undo = describe(...) end
        if active() then
            local top = stacks[kind][#stacks[kind]]
            local skip = top and top.skipped
            if chainDepth(stacks[kind]) >= 32 then reject(push, "tracked stack limit") skip = true end
            if validate and validate(nil, ...) == false then skip = true end
            if skip then
                if top and top.skipped and top.owner == frame and top.family == scopeFamily then top.count = top.count + 1
                else
                    pushed(kind, function() end, function() end)
                    top = stacks[kind][#stacks[kind]]
                    top.skipped, top.count, top.family = true, 1, scopeFamily
                end
                return
            end
        end
        if kind == "rt" and frame then noteTarget() end
        local replay
        if kind == "rt" then
            local args = pack(...)
            replay = function()
                if validate and validate("<tracked render-target push>", unpack(args, 1, args.n)) == false then return end
                return first(unpack(args, 1, args.n))
            end
        end
        local result = pack(invokeBusy(first, ...))
        pushed(kind, undo, replay)
        stacks[kind][#stacks[kind]].family = scopeFamily
        return unpack(result, 1, result.n)
    end
    if registered[pop] then return end
    registered[pop] = last
    tbl[pop] = function(...)
        if busy > 0 then return last(...) end
        sync()
        local top = stacks[kind][#stacks[kind]]
        if active() then
            if not top then reject(pop, "no tracked Lua push to pop") return end
            if top.family ~= family then reject(pop, "closer does not match tracked Lua push") return end
            if frame and top.owner ~= frame and (not top.owner or not top.owner.completed) then
                reject(pop, "protected callback cannot consume caller-owned state") return
            end
        end
        if top and top.skipped then
            top.count = top.count - 1
            if top.count == 0 then popped(kind) end
            return
        end
        if kind == "rt" and frame then noteTarget() end
        local result = pack(invokeBusy(last, ...))
        popped(kind)
        return unpack(result, 1, result.n)
    end
end
local function viewValues(api, source, view)
    if view == nil then return true end
    if type(view) ~= "table" then return reject(api, "view must be a table", source) end
    for _, key in ipairs({"x", "y", "w", "h", "fov", "znear", "zfar", "zNear", "zFar", "aspect"}) do
        if view[key] ~= nil and not finite(view[key]) then return reject(api, "non-finite view parameter " .. key, source) end
    end
    for _, key in ipairs({"w", "h"}) do
        if view[key] ~= nil and (view[key] < 1 or view[key] > 16384) then return reject(api, "invalid explicit viewport", source) end
    end
    if view.fov ~= nil and (view.fov <= 0 or view.fov >= 180) then return reject(api, "invalid field of view", source) end
    for _, key in ipairs({"origin", "angles"}) do
        if view[key] ~= nil then
            local ok, a, b, c = pcall(function()
                if key == "origin" then return view[key].x, view[key].y, view[key].z end
                return view[key].p, view[key].y, view[key].r
            end)
            if not ok or not finite(a) or not finite(b) or not finite(c) then return reject(api, "invalid " .. key, source) end
        end
    end
    return true
end
local function dimensions(texture) return texture:Width(), texture:Height() end
local validTextures = setmetatable({}, {__mode = "k"})
local function targetValues(source, texture, x, y, w, h)
    if texture ~= nil then
        if policy.inertTextures[texture] then return reject("render target", "inert target cannot be bound or copied", source) end
        if not validTextures[texture] then
            local ok, width, height = pcall(dimensions, texture)
            if not ok or not finite(width) or not finite(height) or width <= 0 or height <= 0
                or width > 16384 or height > 16384 then return reject("render target", "invalid texture", source) end
            local named, name = pcall(function() return texture:GetName() end)
            if named and policy.reserved(name) then return reject("render target", "engine-owned depth target cannot be bound or copied", source) end
            local kind = type(texture)
            if kind == "userdata" or kind == "table" or kind == "ITexture" then validTextures[texture] = true end
        end
    end
    if (x ~= nil and not finite(x)) or (y ~= nil and not finite(y)) or (w ~= nil and not finite(w)) or (h ~= nil and not finite(h)) then
        return reject("PushRenderTarget", "non-finite viewport", source)
    end
    if (w and (w < 1 or w > 16384)) or (h and (h < 1 or h > 16384)) then
        return reject("PushRenderTarget", "invalid explicit viewport", source)
    end
    return true
end
pair(render, "PushRenderTarget", "PopRenderTarget", "rt", targetValues)
pair(render, "PushCustomClipPlane", "PopCustomClipPlane", "clip")
pair(cam, "PushModelMatrix", "PopModelMatrix", "model")
pair(cam, "Start", "End", "camera", function(s, view) return viewValues("cam.Start", s, view) end,
    "camera3d", function(view)
        if type(view) == "table" and type(view.type) == "string" and view.type:sub(1, 1) == "2" then
            return "camera2d", nativeCam.End2D
        end
        return "camera3d", nativeCam.End
    end)
pair(cam, "Start2D", "End2D", "camera", nil, "camera2d")
pair(cam, "Start3D", "End3D", "camera", function(s, pos, angle, fov, x, y, w, h, near, far)
    return viewValues("cam.Start3D", s, {origin = pos, angles = angle, fov = fov, x = x, y = y, w = w, h = h, znear = near, zfar = far})
end, "camera3d")
-- Start3D2D also pushes a model matrix. An ordinary camera closer cannot unwind that scope,
-- nor may End3D2D consume an ordinary camera and an unrelated caller-owned matrix.
pair(cam, "Start3D2D", "End3D2D", "camera", nil, "camera3d2d")
pair(cam, "StartOrthoView", "EndOrthoView", "camera", nil, "cameraortho")
if nativeRender.SetRenderTarget then
    render.SetRenderTarget = function(texture, ...)
        if active() and (policy.suppressed() or not targetValues(nil, texture)) then return end
        if frame and busy == 0 then noteTarget() end
        local result = pack(nativeRender.SetRenderTarget(texture, ...))
        if frame and busy == 0 then frame.targetChanged = true end
        return unpack(result, 1, result.n)
    end
end
if nativeRender.SetRenderTargetEx then
    render.SetRenderTargetEx = function(index, texture, ...)
        if active() then
            if index == 0 and policy.suppressed() then return end
            if not integer(index) or index < 0 or index > 3 then reject("render.SetRenderTargetEx", "unknown render-target slot") return
            elseif index ~= 0 and texture ~= nil then reject("render.SetRenderTargetEx", "MRT is unsupported by the RTX path") return
            elseif not targetValues(nil, texture) then return end
        end
        local primary = index == 0 and frame ~= nil and busy == 0
        if primary then noteTarget() end
        local result = pack(nativeRender.SetRenderTargetEx(index, texture, ...))
        if primary then frame.targetChanged = true end
        return unpack(result, 1, result.n)
    end
end
for _, name in ipairs({"Clear", "ClearDepth", "ClearStencil", "DepthRange", "OverrideDepthEnable",
    "OverrideColorWriteEnable", "OverrideAlphaWriteEnable", "OverrideBlend", "SetBlend", "SetLightingMode",
    "FogMode", "FogColor", "FogStart", "FogEnd", "FogMaxDensity", "UpdateScreenEffectTexture", "UpdateRefractTexture"}) do
    local original = nativeRender[name]
    if original then
        render[name] = function(...)
            if active() and (policy.suppressed() or policy.effect(caller())) then
                reject("render." .. name, "inert effect state change ignored", caller()) return
            end
            return original(...)
        end
    end
end
for _, name in ipairs({"CopyRenderTargetToTexture", "CopyTexture"}) do
    local original = nativeRender[name]
    if original then
        render[name] = function(...)
            local target, other = ...
            if active() then
                local source = caller()
                if policy.effect(source) or target == nil or (name == "CopyTexture" and other == nil)
                    or not targetValues(source, target) or (other ~= nil and not targetValues(source, other)) then
                    reject("render." .. name, "incompatible color/depth copy ignored", source) return
                end
                if policy.suppressed() then return end
                if name == "CopyRenderTargetToTexture" and nativeRender.GetRenderTarget then
                    local current = nativeRender.GetRenderTarget()
                    if current and not targetValues(source, current) then return end
                end
            end
            return original(...)
        end
    end
end
-- R28 (ADR 0143): a screen read-back (render.CapturePixels) waits until the GPU has drawn everything queued, which
-- under the path tracer is one to two whole frames: 20-28 ms a call at 80 frames a second, about 200 ms at 7 (the
-- issue 2 report: HyperReal FX read a 1x1 target twice a second and took 67 ms of every frame). Each reader (the
-- calling file, together with the file that called it: two add-ons that read through one shared library are two
-- readers) has an allowance: BURST read-backs at once, refilled at RATE a second, so a tool that reads a handful
-- of targets once, and a reader that asks about once a second, are never limited. A reader that uses its
-- allowance up is a periodic reader (eye adaptation, a tint measured from the screen): its read-backs stop until
-- its requests have fallen back under half the allowance, or it has asked nothing for QUIET seconds.
-- render.ReadPixel is then answered from the last picture really read by the same call, which is the calling line
-- and the render target it read: a pixel that picture does not hold gets the picture's last pixel, and while it
-- holds none the engine's own last picture is read (and remembered). A call that was never made yet is made. A
-- file that reads more than PIXELS pixels of its own picture is scanning an image (an icon, a map), which cannot
-- be answered from memory: it is never limited. Nor are a screenshot (render.Capture) and the package's own tools.
do
    local allow = CreateClientConVar("nativeloader_guard_readbacks", "0", true, false,
        "1 lets add-ons read the screen back as often as they ask under RTX (each read waits for the path tracer)")
    local capture, readPixel, readTarget = nativeRender.CapturePixels, nativeRender.ReadPixel, nativeRender.GetRenderTarget
    local RATE, BURST, QUIET, READERS, PICTURES, PIXELS = 1.25, 8, 5, 256, 8, 1024
    local readClock = SysTime or RealTime or os.clock
    local readers, readerCount = {}, 0
    -- The picture the next render.ReadPixel calls belong to: one being filled, after a read-back that was made, or
    -- one that answers, after a read-back that was refused. nil after a read-back that is not limited.
    local current, answering, answeredAt = nil, false, 0
    local counts = {allowed = 0, refused = 0}
    state.readbacks = counts
    local function fileOf(source) return (source:gsub(":%-?%d+$", "")) end
    local function limited()
        if getBool then return not getBool(allow) end
        return not allow:GetBool()
    end
    local function nameOf(target) return target:GetName() end
    local function targetName()
        if not readTarget then return "" end
        local ok, target = pcall(readTarget)
        if not ok or target == nil then return "" end
        local named, name = pcall(nameOf, target)
        return named and type(name) == "string" and name:sub(1, 96) or "?"
    end
    -- The file that called the function a read-back was made from (level 4 from the wrapper's helper).
    local function outerFile()
        local info = getinfo(4, "S")
        return info and virtual(info.source) or ""
    end
    if capture and readPixel then
        render.CapturePixels = function(...)
            if not active() or not limited() then current = nil return capture(...) end
            local source = caller()
            -- Called through pcall or another native function: the first Lua caller outside the guard.
            if source:sub(1, 13) == "<dynamic Lua>" then source = externalCaller() end
            if policy.bundled(source) then current = nil return capture(...) end
            local file = fileOf(source)
            local who = file .. "<" .. outerFile()
            local reader = readers[who]
            if not reader then
                -- Beyond the table's bound a caller is simply not limited.
                if readerCount >= READERS then current = nil return capture(...) end
                reader = {last = -math.huge, level = 0, blocked = false, scans = false, pictures = {}, count = 0}
                readers[who], readerCount = reader, readerCount + 1
            end
            if reader.scans then current = nil return capture(...) end
            local now = readClock()
            local gap = now - reader.last
            reader.last = now
            -- Every request counts, made or refused, so a reader that keeps coming stays refused, and one that
            -- only overran once is let in again when its requests are back under half the allowance.
            local level = reader.level - gap * RATE
            level = (level > 0 and level or 0) + 1
            if level > BURST * 2 then level = BURST * 2 end
            if reader.blocked then
                if gap >= QUIET then
                    reader.blocked, level = false, 1
                elseif level <= BURST / 2 then
                    reader.blocked = false
                end
            elseif level > BURST then
                reader.blocked = true
            end
            reader.level = level
            local pictures = reader.pictures
            local name = source .. "|" .. targetName()
            local picture = pictures[name]
            if not picture then
                -- More calls than a reader has pictures: the others share one.
                if reader.count >= PICTURES then name = "*" picture = pictures[name] end
                if not picture then
                    picture = {reader = reader, file = file, held = 0}
                    pictures[name] = picture
                    if name ~= "*" then reader.count = reader.count + 1 end
                end
            end
            if reader.blocked and picture.made then
                counts.refused = counts.refused + 1
                current, answering, answeredAt = picture, true, now
                reject("render.CapturePixels", "repeated screen read-backs wait for the path tracer: answered from the"
                    .. " last picture read (nativeloader_guard_readbacks 1 allows them)", source)
                return
            end
            counts.allowed = counts.allowed + 1
            -- What the picture held stays until this read-back's first pixel is read.
            picture.made, picture.fresh = true, true
            current, answering = picture, false
            return capture(...)
        end
        -- The engine truncates a pixel's coordinates.
        local function key(x, y)
            x, y = whole(x), whole(y)
            if x and y and x >= 0 and y >= 0 and x < 65536 and y < 65536 then return x * 65536 + y end
        end
        local function keep(picture, x, y, ...)
            local r, g, b, a = ...
            local at = key(x, y)
            if at and integer(r) and integer(g) and integer(b) and r >= 0 and r < 256 and g >= 0 and g < 256
                and b >= 0 and b < 256 then
                if picture.fresh or not picture.values then
                    picture.values, picture.held, picture.latest, picture.fresh = {}, 0, nil, false
                end
                local values = picture.values
                if values[at] == nil then
                    if picture.held >= PIXELS then
                        -- More pixels than a picture holds. Read by the file that made the read-back, this is
                        -- an image scan: that reader is not limited any more.
                        if fileOf(externalCaller()) == picture.file then
                            local reader = picture.reader
                            reader.scans, reader.blocked = true, false
                        end
                        current = nil
                        return ...
                    end
                    picture.held = picture.held + 1
                end
                local packed = ((r * 256 + g) * 256 + b) * 256 + (integer(a) and a >= 0 and a < 256 and a or 255)
                values[at], picture.latest = packed, packed
            end
            return ...
        end
        render.ReadPixel = function(x, y, ...)
            local picture = current
            if not picture then return readPixel(x, y, ...) end
            if not answering then return keep(picture, x, y, readPixel(x, y, ...)) end
            -- A refused read-back answers until the guard or the limit is switched off, or QUIET seconds pass.
            if not active() or not limited() or readClock() - answeredAt > QUIET then
                current = nil
                return readPixel(x, y, ...)
            end
            local values = not picture.fresh and picture.values
            local at = key(x, y)
            local value = values and (at and values[at] or picture.latest)
            -- Nothing remembered for this call (its read-backs were made, but no pixel read after the last one):
            -- the engine still has the last picture really read.
            if not value then return keep(picture, x, y, readPixel(x, y, ...)) end
            local a = value % 256
            value = (value - a) / 256
            local b = value % 256
            value = (value - b) / 256
            local g = value % 256
            return (value - g) / 256, g, b, a
        end
    end
end
local viewDepth = 0
if nativeRender.RenderView then
    render.RenderView = function(view, ...)
        if not active() then return nativeRender.RenderView(view, ...) end
        if policy.suppressed() then reject("render.RenderView", "ignored render scope has no secondary view", caller()) return end
        if not viewValues("render.RenderView", caller(), view) then return end
        if policy.effect(caller()) then reject("render.RenderView", "screen-space secondary view is inert", caller()) return end
        if viewDepth >= 4 then reject("render.RenderView", "nested view limit", caller()) return end
        viewDepth = viewDepth + 1
        local result = pack(pcall(nativeRender.RenderView, view, ...))
        viewDepth = viewDepth - 1
        if not result[1] then error(result[2], 0) end
        return unpack(result, 2, result.n)
    end
end
-- A function that times another one (the companion's nativeloader_lag_report) enters itself here with the function
-- it times. The guard's records then name that function, and a callback the guard leaves out stays left out under
-- its timer. An entry can only add to what is left out: what a callback may do never follows from this table.
local timed = setmetatable({}, {__mode = "k"})
state.timed = timed
local function timedFunction(fn)
    local original = timed[fn]
    return type(original) == "function" and original or nil
end
local function sourceOf(f)
    local source = f.source
    if not source then source = functionSource(timedFunction(f.fn) or f.fn) f.source = source end
    return source
end
-- PostRender's suppressed-lighting previews need a raster-safe material after RTX injection.
-- Studio overrides preserve the caller's entity and its exact submaterial strings.
do
    local installedModel, installedSuppress
    state.model_preview = {installations = 0, draws = 0}
    local override, byIndex = nativeRender.MaterialOverride, nativeRender.MaterialOverrideByIndex
    local materials, count, indexed = {}, 0, {}
    local suppressed = false
    if byIndex then
        render.MaterialOverrideByIndex = function(index, mat, ...)
            if active() and (policy.inertMaterials[mat] or policy.effect(caller()) or
                (not policy.bundled(caller()) and policy.incompatibleMaterial(mat))) then
                reject("render.MaterialOverrideByIndex", "unsupported RTX shader draw", caller()) return
            end
            local result = pack(byIndex(index, mat, ...))
            if index == nil then indexed = {} else indexed[index] = mat end
            return unpack(result, 1, result.n)
        end
    end
    local function previewMaterial(original)
        if not original or original:IsError() then return end
        local tex = original:GetTexture("$basetexture")
        if not tex or tex:IsError() then return end
        local texture, flags = tex:GetName(), original:GetInt("$flags") or 0
        local key = original:GetName() .. "\0" .. texture .. "\0" .. flags
        local cached = materials[key]
        if cached then return cached.material end
        if count >= 256 then return end
        count = count + 1
        local params = {["$basetexture"] = texture}
        local mat = CreateMaterial("_nativeloader_model_preview_v1_" .. count, "UnlitGeneric", params)
        materials[key] = {material = mat}
        state.model_preview.materials = count
        return mat
    end
    local function installPreview()
        if render.SuppressEngineLighting and render.SuppressEngineLighting ~= installedSuppress then
            local suppress = render.SuppressEngineLighting
            installedSuppress = function(on, ...)
                suppressed = on and true or false
                if on and frame then frame.previewSuppressed = true end
                return suppress(on, ...)
            end
            render.SuppressEngineLighting = installedSuppress
        end
        local model = render.Model
        if not model or model == installedModel or not override then return end
        state.model_preview.installations = state.model_preview.installations + 1
        installedModel = function(data, entity, ...)
            state.model_preview.lastEvent = frame and frame.event or "none"
            state.model_preview.suppressed = suppressed
            state.model_preview.requested = frame and frame.previewSuppressed or false
            state.model_preview.overridden = policy.modelOverride ~= nil
            if policy.previewBusy or not (active() and frame and frame.event == "PostRender" and
                (suppressed or frame.previewSuppressed) and
                policy.modelOverride == nil and entity and entity.GetMaterials and entity.GetSubMaterial) then
                return model(data, entity, ...)
            end
            local parts, changes = entity:GetMaterials(), {}
            if next(indexed) ~= nil then return model(data, entity, ...) end
            for i, name in ipairs(parts) do
                if i > 32 then break end
                if indexed[i - 1] == nil then
                    local old = entity:GetSubMaterial(i - 1) or ""
                    local mat = previewMaterial(Material(old ~= "" and old or name))
                    if mat then changes[1] = {index = i - 1, material = mat} break end
                end
            end
            -- The DX7 studio path's indexed/submaterial overrides still take its black lighting
            -- branch. A representative base map through the global unlit override remains readable.
            if #changes == 0 or next(indexed) ~= nil then return model(data, entity, ...) end
            state.model_preview.draws = state.model_preview.draws + 1
            policy.previewBusy = true
            local result = pack(pcall(function(...)
                override(changes[1].material)
                return model(...)
            end, data, entity, ...))
            local ok = pcall(override, nil)
            if not ok then report("cleanup_errors", "render.Model", "preview material restoration failed") end
            policy.previewBusy = false
            if not result[1] then error(result[2], 0) end
            return unpack(result, 2, result.n)
        end
        render.Model = installedModel
    end
    installPreview()
    hook.Add("Initialize", "nativeloader_model_preview", installPreview)
    hook.Add("InitPostEntity", "nativeloader_model_preview", installPreview)
    hook.Add("OnReloaded", "nativeloader_model_preview", installPreview)
end

local function cleanup(f)
    local actions = f.actions
    busy = busy + 1
    for i = actions and #actions or 0, 1, -1 do
        local action = actions[i]
        if action.restore then
            local prior = action.restore
            if #prior.stack ~= action.depth or prior.stack[#prior.stack] ~= action.previous then
                report("cleanup_errors", f.event, "tracked state changed before popped-scope restoration", sourceOf(f))
            elseif not prior.replay then
                -- Camera/clip/matrix defaults and mutable arguments are not
                -- enough to reconstruct an earlier native context safely.
                report("cleanup_errors", f.event, "completed camera/clip/matrix pop cannot be safely replayed", sourceOf(f))
            else
                local ok = pcall(prior.replay)
                if ok then prior.stack[#prior.stack + 1] = prior prior.active = true
                else report("cleanup_errors", f.event, "popped render-target restoration failed", sourceOf(f)) end
            end
        elseif action.active then
            if action.stack[#action.stack] == action then
                local ok = pcall(action.undo)
                if ok then table.remove(action.stack) action.active = false
                else report("cleanup_errors", f.event, "tracked stack restoration failed", sourceOf(f)) end
            else report("cleanup_errors", f.event, "untracked state prevents stack restoration", sourceOf(f)) end
        end
    end
    if f.targetChanged and f.haveTarget and nativeRender.SetRenderTarget then
        local ok = pcall(nativeRender.SetRenderTarget, f.target)
        if not ok then report("cleanup_errors", f.event, "target restoration failed", sourceOf(f)) end
    end
    busy = busy - 1
end
-- A failure prints the original error and its stack through the engine's own error output, at most
-- once per callback every ten seconds; the guard's records keep virtual sources only. Three
-- consecutive failures within ten seconds quarantine a hook, timer or cvar callback. Gamemode
-- methods are never quarantined: base GM:PostDrawViewModel draws the hands for every weapon.
local clock = SysTime or RealTime or os.clock
local reportInterval, quarantineWindow, quarantineFailures = 10, 10, 3
local failures = setmetatable({}, {__mode = "k"})
local function printError(text)
    if ErrorNoHaltWithStack then ErrorNoHaltWithStack(text)
    elseif ErrorNoHalt then ErrorNoHalt(traceback(text, 3) .. "\n")
    elseif MsgN then MsgN(traceback(text, 3)) end
end
local function failed(f, text)
    local now = clock()
    local record = failures[f.fn]
    if not record then record = {streak = 0, first = now, suppressed = 0} failures[f.fn] = record end
    if record.streak == 0 or now - record.first > quarantineWindow then record.streak, record.first = 1, now
    else record.streak = record.streak + 1 end
    if record.reported and now - record.reported < reportInterval then
        record.suppressed = record.suppressed + 1
        return
    end
    local suppressed = record.suppressed
    record.reported, record.suppressed = now, 0
    pcall(printError, text)
    report("errors", f.event, "Lua error contained; its message and stack are in the console", sourceOf(f))
    if suppressed > 0 and MsgN then
        MsgN("[nativeloader] RTX guard: " .. f.event .. ": " .. suppressed .. " further Lua errors from "
            .. sourceOf(f) .. " since the last report")
    end
end
-- The xpcall message handler runs where the error was raised, so the printed stack is the callback's.
local function handler(err)
    local text = tostring(err)
    if frame then pcall(failed, frame, text) end
    return text
end
local function quarantined(fn, event)
    local record = failures[fn]
    if not record or record.streak < quarantineFailures then return false end
    report("errors", event, "callback quarantined after " .. quarantineFailures .. " consecutive Lua errors",
        functionSource(timedFunction(fn) or fn))
    return true
end
-- R28 (ADR 0143): what each protected render callback costs. One that takes SLOW_MS or more of every frame over a
-- window of SLOW_WINDOW seconds is named once in the console and kept in state.slow, with its hook's name: the
-- companion's nativeloader_lag_report lists them. Nothing is stopped: a slow HUD is still the player's HUD.
local SLOW_MS, SLOW_WINDOW, SLOW_RECORDS, SLOW_NAMES = 4, 5, 32, 2048
-- A hook added under a name is known by its event and name, so a function put in its place (a timing wrapper, a
-- closure added again) continues the same count; a hook of an object, and a call outside hook.Call, by function.
local costs, slowRecords = setmetatable({}, {__mode = "k"}), setmetatable({}, {__mode = "k"})
local namedCosts, namedCount, namedRecords = {}, 0, {}
local framesSeen, pendingId = 0, nil
local function spent(f, finished)
    local fn, took = f.fn, finished - f.began
    local name = type(f.id) == "string" and f.id or nil
    local cost, named
    if name then
        named = namedCosts[f.event]
        cost = named and named[name]
    else
        cost = costs[fn]
    end
    if not cost then
        -- This frame's PreRender is already counted: the first call belongs to one frame.
        cost = {sum = 0, worst = 0, since = f.began, frames = framesSeen - 1}
        if not name then
            costs[fn] = cost
        else
            -- Names made up anew all the time are not kept for ever.
            if namedCount >= SLOW_NAMES then namedCosts, namedCount, named = {}, 0, nil end
            if not named then
                named = {}
                namedCosts[f.event] = named
            end
            named[name], namedCount = cost, namedCount + 1
        end
    end
    cost.sum = cost.sum + took
    if took > cost.worst then cost.worst = took end
    -- A window is at least SLOW_WINDOW seconds and thirty frames, so a slide show is measured too.
    local frames = framesSeen - cost.frames
    if finished - cost.since < SLOW_WINDOW or frames < 30 then return end
    local share, worst = cost.sum / frames * 1000, cost.worst * 1000
    cost.sum, cost.worst, cost.since, cost.frames = 0, 0, finished, framesSeen
    if share < SLOW_MS then return end
    local records = name and namedRecords[f.event]
    local record
    if name then record = records and records[name] else record = slowRecords[fn] end
    if record then
        if share > record.ms then record.ms = share end
        if worst > record.worst_ms then record.worst_ms = worst end
        return
    end
    if #state.slow >= SLOW_RECORDS then return end
    local id = f.id
    if type(id) ~= "string" then id = id == nil and "?" or "<" .. type(id) .. ">" end
    record = {api = f.event, id = id:sub(1, 120), source = sourceOf(f), ms = share, worst_ms = worst}
    record.reason = string.format("%.1f ms of every frame", share)
    if not name then
        slowRecords[fn] = record
    else
        if not records then
            records = {}
            namedRecords[f.event] = records
        end
        records[name] = record
    end
    state.slow[#state.slow + 1] = record
    if MsgN then
        MsgN(string.format("[nativeloader] RTX guard: %s: %s takes %.1f ms of every frame (worst %.0f ms): %s",
            record.api, record.id, share, worst, record.source))
    end
end
local function settle(f, ok, ...)
    frame = f.parent
    f.completed = ok
    spent(f, clock())
    if not ok then cleanup(f) return false end
    local record = failures[f.fn]
    if record then record.streak = 0 end
    -- Successful nested work is part of its active caller's chronological
    -- undo log. Failed children already cleaned their own log and must not
    -- replay those restores a second time if an ancestor subsequently fails.
    local parent, actions = f.parent, f.actions
    if parent then
        if actions then
            local list = log(parent)
            for i = 1, #actions do list[#list + 1] = actions[i] end
        end
        if f.targetChanged then parent.targetChanged = true end
    end
    return true, ...
end
local function protectedCall(fn, event, ...)
    local id = pendingId
    pendingId = nil
    if policy.skipCallback(fn, event) then return true end
    local original = timedFunction(fn)
    if original and policy.skipCallback(original, event) then return true end
    local f = {event = event, fn = fn, parent = frame, id = id, began = clock()}
    frame = f
    return settle(f, xpcall(fn, handler, ...))
end
local events = {Initialize = true, InitPostEntity = true, OnReloaded = true,
    PreRender = true, PostRender = true, RenderScene = true, RenderScreenspaceEffects = true,
    PreDrawEffects = true, PostDrawEffects = true, PreDrawOpaqueRenderables = true,
    PostDrawOpaqueRenderables = true, PreDrawTranslucentRenderables = true, PostDrawTranslucentRenderables = true,
    PreDrawViewModel = true, PostDrawViewModel = true, PostDrawPlayerHands = true, PreDrawViewModels = true,
    HUDPaint = true, PreDrawHUD = true, PostDrawHUD = true, PostRenderVGUI = true,
    SetupWorldFog = true, SetupSkyboxFog = true, NeedsDepthPass = true,
    InitPostShaderlib = true, InitPostReconstruction = true, PreDrawReconstruction = true, PostDrawReconstruction = true}
local getHooks, quarantine = hook.GetTable, {}
local function gamemodeResult(ok, ...) if ok then return ... end end
if not late then
    local originalCall = hook.Call
    hook.Call = function(name, gm, ...)
        if not events[name] or not active() then return originalCall(name, gm, ...) end
        if name == "NeedsDepthPass" then return false end
        if name == "PreRender" then
            framesSeen = framesSeen + 1
            if not frameNumber and frame == nil and busy == 0 then resync() end
        end
        local entries = getHooks()[name]
        local stopped = quarantine[name]
        if not stopped then stopped = setmetatable({}, {__mode = "k"}) quarantine[name] = stopped end
        if entries then
            for id, fn in pairs(entries) do
                local out = stopped[id]
                if type(id) ~= "string" and not IsValid(id) then entries[id] = nil
                elseif out == nil or (out ~= fn and out ~= timedFunction(fn)) then
                    local ok, a, b, c, d, e, g
                    pendingId = id
                    if type(id) == "string" then ok, a, b, c, d, e, g = protectedCall(fn, name, ...)
                    else ok, a, b, c, d, e, g = protectedCall(fn, name, id, ...) end
                    if not ok then
                        -- Stopped as the function itself, also when it failed under a timer of it.
                        if quarantined(fn, name) then stopped[id] = timedFunction(fn) or fn end
                    elseif a ~= nil then return a, b, c, d, e, g end
                end
            end
        end
        local fn = gm and gm[name]
        if fn then
            pendingId = "the gamemode"
            return gamemodeResult(protectedCall(fn, name, gm, ...))
        end
    end
end
-- Capability policy applies to remote callbacks too, without catching their unrelated errors.
-- Wrapping these entries also covers an engine/add-on that cached the original hook.Call.
do
    local allowed = {Initialize = true, InitReconstruction = true, InitPostReconstruction = true,
        OnScreenSizeChanged = true, OnReloaded = true, ShutDown = true}
    local filtered = setmetatable({}, {__mode = "k"})
    local function filter(event, fn)
        if type(fn) ~= "function" or (event ~= "NeedsDepthPass"
            and (allowed[event] or not policy.effect(functionSource(fn)))) then return fn end
        local entries = filtered[fn]
        if not entries then entries = {} filtered[fn] = entries end
        if not entries[event] then
            entries[event] = function(...)
                if active() then
                    if event == "NeedsDepthPass" then return false end
                    if policy.skipCallback(fn, event) then return end
                end
                return fn(...)
            end
        end
        return entries[event]
    end
    policy.filter = filter
    for event, entries in pairs(getHooks()) do
        for id, fn in pairs(entries) do entries[id] = filter(event, fn) end
    end
    local originalAdd = hook.Add
    hook.Add = function(event, id, fn, ...) return originalAdd(event, id, filter(event, fn), ...) end
end
local function callback(fn, event)
    local stopped = false
    local function finish(ok, ...)
        if ok then return ... end
        if quarantined(fn, event) then stopped = true end
    end
    return function(...)
        if not active() then return fn(...) end
        if policy.skipCallback(fn, event) then return end
        if stopped then return end
        return finish(protectedCall(fn, event, ...))
    end
end
-- In the verified multiplayer route the remote server's own Lua stays as it is (ADR 0052): only
-- callbacks defined in the owned, hash-verified environments are protected, recognized by the
-- private marker raw-set in their environment.
local function owned(fn)
    if type(fn) ~= "function" then return false end
    local ok, env = pcall(getfenv, fn)
    return ok and type(env) == "table" and env ~= _G and rawget(env, "NATIVELOADER_VERIFIED_MULTIPLAYER") == true
end
local function protects(fn) return type(fn) == "function" and (not late or owned(fn)) end
if late then
    -- The engine may already hold the original hook.Call. Protect owned render
    -- functions themselves in this late path. Loading-hook identity stays intact
    -- for the verified bootstrap's initialization replay.
    local loadingEvents = {Initialize = true, InitPostEntity = true, OnReloaded = true}
    local lateEvents, registrations = {}, {}
    for event in pairs(events) do
        if not loadingEvents[event] then lateEvents[event] = true end
    end
    local function renderCallback(event, id, fn)
        local entries = registrations[event]
        if not entries then
            entries = setmetatable({}, {__mode = "k"})
            registrations[event] = entries
        end
        local prior = entries[id]
        if prior and (prior.original == fn or prior.wrapper == fn) then return prior.wrapper end
        local wrapper = callback(fn, event)
        entries[id] = {original = fn, wrapper = wrapper}
        return wrapper
    end
    for event, entries in pairs(getHooks()) do
        if lateEvents[event] and type(entries) == "table" then
            for id, fn in pairs(entries) do
                if owned(fn) then entries[id] = renderCallback(event, id, fn) end
            end
        end
    end
    local originalAdd = hook.Add
    hook.Add = function(event, id, fn, ...)
        if lateEvents[event] and id ~= nil and owned(fn) then fn = renderCallback(event, id, fn) end
        return originalAdd(event, id, fn, ...)
    end
    state.late_render_wrappers = true
end
if timer and timer.Create then
    local original = timer.Create
    timer.Create = function(id, delay, count, fn, ...)
        if protects(fn) then fn = callback(fn, "timer.Create") end
        fn = policy.filter("timer.Create", fn)
        return original(id, delay, count, fn, ...)
    end
end
if timer and timer.Simple then
    local original = timer.Simple
    timer.Simple = function(delay, fn, ...)
        if protects(fn) then fn = callback(fn, "timer.Simple") end
        fn = policy.filter("timer.Simple", fn)
        return original(delay, fn, ...)
    end
end
if cvars and cvars.AddChangeCallback then
    local original = cvars.AddChangeCallback
    cvars.AddChangeCallback = function(name, fn, id, ...)
        if protects(fn) then fn = callback(fn, "cvars.AddChangeCallback") end
        fn = policy.filter("cvars.AddChangeCallback", fn)
        return original(name, fn, id, ...)
    end
end
-- R28 (ADR 0143): surface.CreateFont for a name that already has that definition makes the engine build every
-- font's glyph pages again; twenty such calls a frame (a font made in a paint hook) took a 12 ms frame to 29 ms
-- (PoC). The same definition again changes nothing, so it is made once; a changed one is made as before.
do
    local createFont = surface and surface.CreateFont
    if createFont then
        -- The same definition is made again once FONT_REFRESH seconds have passed, in case the engine's font
        -- was changed by a route this wrapper does not see.
        local fonts, fontCount, FONTS, FONT_REFRESH = {}, 0, 4096, 10
        local fontClock = SysTime or RealTime or os.clock
        local skipped = {calls = 0}
        state.fonts = skipped
        local function same(known, data)
            local values, count = known.values, 0
            for k, v in pairs(data) do
                count = count + 1
                if values[k] ~= v then return false end
            end
            return count == known.count
        end
        surface.CreateFont = function(name, data, ...)
            if not active() or type(name) ~= "string" or type(data) ~= "table" or select("#", ...) > 0
                or getmetatable(data) ~= nil then
                return createFont(name, data, ...)
            end
            -- The engine knows a font by its name without case.
            local id, now = name:lower(), fontClock()
            local known = fonts[id]
            if known and now - known.at < FONT_REFRESH and same(known, data) then
                skipped.calls = skipped.calls + 1
                return
            end
            local result = pack(createFont(name, data, ...))
            if known or fontCount < FONTS then
                if not known then fontCount = fontCount + 1 end
                -- A copy: the caller may reuse and change its table.
                local copy, count = {}, 0
                for k, v in pairs(data) do copy[k], count = v, count + 1 end
                fonts[id] = {values = copy, count = count, at = now}
            end
            return unpack(result, 1, result.n)
        end
    end
end
local postprocess = {"DrawBloom", "DrawColorModify", "DrawSharpen", "DrawMotionBlur", "DrawToyTown",
    "DrawMaterialOverlay", "DrawSobel", "DrawSunbeams", "DrawTexturize", "DrawBokehDOF"}
local wrappedPost = {}
local function installPost()
    for _, name in ipairs(postprocess) do
        local original = _G[name]
        if type(original) == "function" and original ~= wrappedPost[name] then
            local wrapper = function(...) if not active() then return original(...) end end
            wrappedPost[name], _G[name] = wrapper, wrapper
        end
    end
    if halo and type(halo.Render) == "function" and halo.Render ~= wrappedPost.halo then
        local original = halo.Render
        local wrapper = function(...) if not active() then return original(...) end end
        wrappedPost.halo, halo.Render = wrapper, wrapper
    end
end
installPost()
hook.Add("Initialize", "nativeloader_guard", installPost)
