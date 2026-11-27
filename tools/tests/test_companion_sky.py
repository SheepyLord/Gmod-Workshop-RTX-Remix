"""The companion's sky under LuaJIT: the arithmetic (companion/nativeloader/lua/nativeloader/sky_model.lua)
and the session logic (autorun/nativeloader_sky.lua) with the GMod functions it uses mocked: what it
gives Remix at the start of a map, a change of weather blending over time, the clock, a map whose
add-on sets the sky, the map's own skybox and a night map. Skipped when LuaJIT is not installed."""
import hashlib
import json
import math
import os
import shutil
import struct
import subprocess
import tempfile
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
LUA = REPO / 'companion' / 'nativeloader' / 'lua'
LUAJIT = shutil.which('luajit') or next((str(p) for p in [Path(os.environ.get('LOCALAPPDATA', '')) / 'Programs/LuaJIT/bin/luajit.exe']
                                          if p.is_file()), None)


def lua_string(data: bytes) -> str:
    """Any bytes as a Lua string literal (decimal escapes for everything but plain ASCII)."""
    return '"' + ''.join(chr(b) if 32 <= b < 127 and chr(b) not in '"\\' else f'\\{b:03d}' for b in data) + '"'


def bsp(entities: str, texinfo_flags=None) -> bytes:
    """A BSP as far as the companion reads it: the header with lump 0 (the entity lump) and its text, and with
    `texinfo_flags` lump 6, one 72-byte texinfo for each flags value (ADR 0249: 0x4 is a sky face)."""
    text = entities.encode('latin-1')
    start = 8 + 64 * 16
    texinfo = b''
    if texinfo_flags is not None:
        texinfo = b''.join(bytes(64) + struct.pack('<ii', flags, 0) for flags in texinfo_flags)
    header = b'VBSP' + struct.pack('<i', 20)
    for index in range(64):
        if index == 0:
            header += struct.pack('<iiii', start, len(text), 0, 0)
        elif index == 6 and texinfo:
            header += struct.pack('<iiii', start + len(text), len(texinfo), 0, 0)
        else:
            header += bytes(16)
    return header + text + texinfo


CONSTRUCT = ('{\n"skyname" "painted"\n"classname" "worldspawn"\n}\n'
             '{\n"pitch" "-56"\n"angles" "0 306 0"\n"_light" "242 234 218 560"\n"classname" "light_environment"\n}\n'
             '{\n"pitch" "-50"\n"angles" "0 306 0"\n"classname" "env_sun"\n}\n')

MODEL = r'''
local M = dofile(LUA .. "/nativeloader/sky_model.lua")
local function out(key, ...) local t = {} for i = 1, select("#", ...) do t[i] = string.format("%.4f", (select(i, ...))) end print(key .. " " .. table.concat(t, " ")) end
for name, day in pairs(M.SEASONS) do
  local s = M.sky(12, day, 0.5, 0).sun
  out("noon_" .. name, s.elevation, s.bearing, M.timeForElevation(-0.83, true, day), M.timeForElevation(-0.83, false, day))
end
local s = M.mapSun(-56, 306)
out("mapsun", s.elevation, s.bearing)
print("mapsun_up " .. tostring(M.mapSun(10, 0)) .. " " .. tostring(M.mapSun("x", 0)))
for i, sun in ipairs({ { 56, 324 }, { 20, 10 }, { 73, 200 }, { 85, 90 }, { 5, 270 } }) do
  local hours, north = M.followMap({ elevation = sun[1], bearing = sun[2] }, M.SEASONS.summer)
  local at = M.sky(hours, M.SEASONS.summer, 0.5, north).sun
  out("follow" .. i, hours, at.elevation, at.bearing)
end
for _, p in ipairs({ 0, 0.25, 0.5 }) do
  local sky = M.sky(20, M.SEASONS.spring, p, 0)
  out("moon" .. p, sky.moon.elevation, sky.moon.bearing, sky.sun.elevation, sky.sun.bearing)
end
local a, b = M.sky(22, 172, 0.5, 30).stars, M.sky(23, 172, 0.5, 30).stars
out("stars", a.rotation, b.rotation, a.poleElevation, a.poleBearing)
local entities = M.parseEntities(CONSTRUCT, { light_environment = true, env_sun = true })
local sun = M.sunOfEntities(entities)
out("entities", #entities, sun.elevation, sun.bearing)
local only = M.sunOfEntities(M.parseEntities('{ "classname" "env_sun" "angles" "-40 90 0" }'))
out("env_sun", only.elevation, only.bearing)
print("none " .. tostring(M.sunOfEntities({})))
print("names " .. tostring(M.skyTimeOfName("sky_borealis01")) .. " " .. tostring(M.skyTimeOfName("sky_day01_01"))
  .. " " .. tostring(M.skyTimeOfName("Dusk_Sky")))
out("blend", M.blend("angle", 350, 10, 0.5), M.blend("extinction", 100, 1000, 0.5), M.blend("scalar", 1, 3, 0.25),
  M.blend("color", { 0, 1, 2 }, { 1, 1, 0 }, 0.5)[3])
print("step " .. tostring(M.blend("step", false, true, 0.49)) .. " " .. tostring(M.blend("step", false, true, 0.5)))
print("text " .. M.optionText(true) .. "|" .. M.optionText({ 0.5, 1, 0.25 }) .. "|" .. M.optionText(2.4, true)
  .. "|" .. M.optionText(0.00330001))
print("clock " .. M.clock(0) .. " " .. M.clock(13.999) .. " " .. M.clock(-1) .. " " .. tostring(M.parseClock("7:05"))
  .. " " .. tostring(M.parseClock("24:00")) .. " " .. tostring(M.parseClock("x")))
out("drift", M.drift(0, 0), M.drift(150, 0), M.drift(0, 6))
out("lunar", M.eclipseSeparation("lunar", 0, 0.8), M.eclipseSeparation("lunar", 0.3, 0.8),
  M.eclipseSeparation("lunar", 0.5, 0.8), M.eclipseSeparation("lunar", 0.7, 0.8), M.eclipseSeparation("lunar", 1, 0.8))
out("solar", M.eclipseSeparation("solar", 0, 0.8), M.eclipseSeparation("solar", 0.45, 0.8),
  M.eclipseSeparation("solar", 0.9, 0.8), M.eclipseSeparation("solar", 1, 0.8), M.moonLatitude(nil, 1, 0.8))
print("phases " .. tostring(M.eclipsePhase("lunar")) .. " " .. tostring(M.eclipsePhase("solar")) .. " "
  .. tostring(M.eclipsePhase(nil)) .. " " .. M.MOON_PHASES.waxingCrescent .. " " .. M.MOON_PHASES.waningCrescent)
-- The moon off the ecliptic: its distance from the antisolar point (full) or the sun (new) is its
-- latitude, whatever the hour and season.
local function dir(e, b) e, b = math.rad(e), math.rad(b) return { math.cos(e) * math.sin(b), math.sin(e), math.cos(e) * math.cos(b) } end
local function angle(a, b) return math.deg(math.acos(math.max(-1, math.min(1, a[1] * b[1] + a[2] * b[2] + a[3] * b[3])))) end
for i, case in ipairs({ { 0, M.SEASONS.summer, 0.5, 2.12 }, { 3, M.SEASONS.winter, 0.5, 5.64 }, { 12, M.SEASONS.spring, 0, 0.71 } }) do
  local sky = M.sky(case[1], case[2], case[3], 25, nil, case[4])
  local sun, moon = dir(sky.sun.elevation, sky.sun.bearing), dir(sky.moon.elevation, sky.moon.bearing)
  out("offset" .. i, angle(moon, case[3] == 0 and sun or { -sun[1], -sun[2], -sun[3] }))
end
'''

# GMod as far as nativeloader_sky.lua (and nativeloader/i18n.lua, which it includes) uses it. The
# console runs commands at once here; GMod runs them on the next frame, which the module allows for.
GMOD_MOCKS = r'''
CLIENT, SERVER = true, false
local calls = {}
RemixConfig = {
  SetConfigVariable = function(k, v) calls[#calls + 1] = { k, v } return true end,
  GetConfigVariable = function(k) return CONF[k] or "" end,
}
if NOAPI then RemixConfig = nil end
istable = function(v) return type(v) == "table" end
isfunction = function(v) return type(v) == "function" end
isstring = function(v) return type(v) == "string" end
local convars, callbacks, commands, hooks, timers = {}, {}, {}, {}, {}
function CreateClientConVar(name, default, archived)
  -- PRESET: saved settings the session starts with, as GMod's client.vdf gives them.
  local c = { value = PRESET and PRESET[name] or default, archived = archived, default = default }
  -- Most scenarios inspect a fixed sky/weather in isolation. Freeze the clock explicitly; the
  -- defaults scenarios below exercise the real moving default and its migration instead.
  if name == "nativeloader_sky_time_passes" and not RUNNING_DEFAULTS then c.value = "0" end
  -- ADR 0253: the chat line is off by default. The scenarios read it, so they start as a player who ticked "Say which
  -- sky shows" (the line on, its migration done below) unless LINE_DEFAULT (a new player's game) or LINE_MIGRATION (a
  -- game saved before the change) asks otherwise.
  if name == "nativeloader_sky_message" and not LINE_DEFAULT and not LINE_MIGRATION and not (PRESET and PRESET[name]) then
    c.value = "1"
  end
  -- The Enhanced sky is the default (the user, 2026-11-26). The scenarios written for the Standard sky keep it unless
  -- PRESET chooses; SKY_DEFAULT starts a new player's game with the real default.
  if name == "nativeloader_sky_enhanced" and not SKY_DEFAULT and not (PRESET and PRESET[name]) then c.value = "0" end
  function c:GetString() return self.value end
  function c:GetBool() return (tonumber(self.value) or 0) ~= 0 end
  function c:GetFloat() return tonumber(self.value) or 0 end
  function c:GetInt() return math.floor(tonumber(self.value) or 0) end
  function c:SetString(value)
    local old = self.value
    self.value = tostring(value)
    if old ~= self.value then for _, fn in ipairs(callbacks[name] or {}) do fn(name, old, self.value) end end
  end
  convars[name] = c
  return c
end
-- ADR 0249: the engine's convars the map's own 3D skybox and a sky file's sky name change (as an RTX session sets
-- them), and the RTX fixes' Lua convars beside them. The engine's refuse SetString from Lua, as GMod's do; every
-- change is logged, r_3dsky's with the fixes' warning switch as its change callback sees it.
local engine = { r_3dsky = "0", r_novis = "1", sv_skyname = SKYNAME or "" }
local luaEngine = { rtx_patch_forcenovis = "1", rtx_patch_vis_pas = "0", rtx_show_3dsky_warning = "1" }
-- ENGINE_START: values an earlier map left (a level change keeps convars).
for name, value in pairs(ENGINE_START or {}) do
  if engine[name] ~= nil then engine[name] = value else luaEngine[name] = value end
end
local engineLog = {}
local function engineChanged(name, v)
  engineLog[#engineLog + 1] = name .. "=" .. v .. (name == "r_3dsky" and ("(warn " .. luaEngine.rtx_show_3dsky_warning .. ")") or "")
end
function GetConVar(name)
  if engine[name] ~= nil then
    return { GetString = function() return engine[name] end,
      SetString = function() error("attempted to modify ConVar not created by Lua") end }
  end
  if luaEngine[name] ~= nil then
    return { GetString = function() return luaEngine[name] end,
      SetString = function(_, v) luaEngine[name] = tostring(v) engineChanged(name, tostring(v)) end }
  end
  return convars[name]
end
cvars = { AddChangeCallback = function(name, fn) callbacks[name] = callbacks[name] or {} table.insert(callbacks[name], fn) end }
function RunConsoleCommand(name, ...)
  local args = { ... }
  local c = convars[name]
  if engine[name] ~= nil or luaEngine[name] ~= nil then
    local store = engine[name] ~= nil and engine or luaEngine
    store[name] = tostring(args[1])
    engineChanged(name, store[name])
  elseif c then
    local old = c.value
    c.value = tostring(args[1])
    if old ~= c.value then for _, fn in ipairs(callbacks[name] or {}) do fn(name, old, c.value) end end
  elseif commands[name] then
    commands[name](nil, name, args)
  end
end
concommand = { Add = function(name, fn) commands[name] = fn end }
local simple, delays = {}, {}
timer = {
  Create = function(name, delay, reps, fn) timers[name] = fn delays[name] = delay end,
  Adjust = function(name, delay) delays[name] = delay return timers[name] ~= nil end,
  Simple = function(delay, fn) simple[#simple + 1] = fn end,
  Remove = function(name) timers[name] = nil end,
}
hook = {
  Add = function(event, name, fn) hooks[event] = hooks[event] or {} hooks[event][name] = fn end,
  Run = function(event, ...)
    for _, fn in pairs(hooks[event] or {}) do local r = fn(...) if r ~= nil then return r end end
  end,
}
-- ADR 0248: a map's add-on with a fixed sky (space around a station) answers both hooks from its load,
-- before the map starts.
if FIXED_SKY_ADDON then
  -- As gm_stelliferous RTX does it: it names itself only while its sky shows, asking takenOver() from this very answer.
  hook.Add("NativeLoaderSkyOwner", "station", function()
    if not (NATIVELOADER_SKY and NATIVELOADER_SKY.takenOver and NATIVELOADER_SKY.takenOver()) then return "Station RTX" end
  end)
  hook.Add("NativeLoaderSkyFixed", "station", function() return true end)
end
local now = 1000
function CurTime() return now end
function RealTime() return now end
local function bspFile(data)
  local pos = 0
  return {
    Seek = function(self, p) pos = p end,
    Read = function(self, n) local s = data:sub(pos + 1, pos + n) pos = pos + n return s end,
    ReadLong = function(self)
      local b1, b2, b3, b4 = data:byte(pos + 1, pos + 4) pos = pos + 4
      local v = b1 + b2 * 256 + b3 * 65536 + b4 * 16777216
      return v >= 2147483648 and v - 4294967296 or v
    end,
    Close = function() end,
  }
end
local data = {}
if not LINE_DEFAULT and not LINE_MIGRATION then data["nativeloader_companion/sky_message_client_v1.txt"] = "done\n" end
-- ADR 0249: a map's sky faces are there (materials/skybox/<name><side>.vmt) unless FACES is false or a table of the
-- paths that are; sky files (SKY_FILES: path -> text) are add-ons' data_static; JSON maps a file's text to the
-- table util.JSONToTable gives (none for text it cannot read); SAVED_CHOICES is sky_maps.txt from an earlier game.
local function skyFile(path) return SKY_FILES and SKY_FILES[path] end
file = {
  Open = function(path) if BSP and path == "maps/" .. MAP .. ".bsp" then return bspFile(BSP) end end,
  Exists = function(path, where)
    if data[path] ~= nil or skyFile(path) then return true end
    if where == "GAME" and FACES ~= false and path:find("^materials/skybox/") then
      return type(FACES) ~= "table" or FACES[path] == true
    end
    return false
  end,
  Read = function(path, where)
    if where == "GAME" then return skyFile(path) end
    if path == "native-loader/status.json" and where == "DATA" then return LOADER_STATUS end
    if path == "nativeloader_companion/sky_maps.txt" then return data[path] or SAVED_CHOICES end
    return nil
  end,
  Find = function(pattern, where)
    local folder = pattern:match("^(.*/)%*%.json$")
    local names = {}
    for path in pairs(SKY_FILES or {}) do
      if folder and path:sub(1, #folder) == folder and not path:sub(#folder + 1):find("/", 1, true) then
        names[#names + 1] = path:sub(#folder + 1)
      end
    end
    return names, {}
  end,
  Size = function(path) local text = skyFile(path) return text and #text or 0 end,
  CreateDir = function() end,
  Write = function(path, value) data[path] = value end,
}
game = { GetMap = function() return MAP end, SinglePlayer = function() return SINGLE ~= false end }
-- The chat line (ADR 0249), printed as "chat <its text>".
function Color(r, g, b) return { r = r, g = g, b = b } end
chat = { AddText = function(...)
  local parts = {}
  for _, v in ipairs({ ... }) do if type(v) == "string" then parts[#parts + 1] = v end end
  print("chat " .. table.concat(parts))
end }
local vector = {}
vector.__index = vector
vector.__add = function(a, b) return setmetatable({ x = a.x + b.x, y = a.y + b.y, z = a.z + b.z }, vector) end
function Vector(x, y, z) return setmetatable({ x = x, y = y, z = z }, vector) end
function EyePos() return Vector(300, 288, -60) end
function LocalPlayer() return {} end
MASK_SOLID = 1
util = {
  GetSunInfo = function() return nil end,
  TraceLine = function() return { Hit = true, HitSky = not COVERED } end,
  JSONToTable = function(text) return JSON and JSON[text] or nil end,
}
math.Clamp = function(v, lo, hi) return math.min(math.max(v, lo), hi) end
spawnmenu = { AddToolMenuOption = function() end }
function include(path) return dofile(LUA .. "/" .. path) end
function AddCSLuaFile() end
print = print
SortedPairs = pairs
MsgN = function() end
'''

SESSION_SETUP = GMOD_MOCKS + r'''
-- The engine guard's read-only poster status (ADR 0226), as the client realm of an RTX start has it.
if POSTER_SIM then nlengineguard = { PosterStatus = function() return POSTER_STATE and { state = POSTER_STATE } or nil end } end
local M = dofile(LUA .. "/nativeloader/sky_model.lua")
dofile(LUA .. "/autorun/nativeloader_defaults.lua")
dofile(LUA .. "/autorun/nativeloader_sky.lua")
-- The RTX Remix tab's Remix settings, for the fog presets.
if MENU then dofile(LUA .. "/autorun/client/nativeloader_menu.lua") end

local function value(option)
  for i = #calls, 1, -1 do if calls[i][1] == option then return calls[i][2] end end
  return nil
end
local function report(tag, ...)
  local parts = {}
  for _, option in ipairs({ ... }) do parts[#parts + 1] = option .. "=" .. tostring(value(option)) end
  print(tag .. " " .. #calls .. " " .. table.concat(parts, " "))
end
local function tick(seconds)
  now = now + seconds
  for _, fn in pairs(timers) do fn() end
end
local function cmd(name, ...) RunConsoleCommand(name, ...) end
'''

SESSION = SESSION_SETUP + r'''
for _, fn in pairs(hooks.InitPostEntity or {}) do fn() end
for _, fn in ipairs(simple) do fn() end
report("start", "rtx.skyMode", "rtx.ignoreGameDirectionalLights", "rtx.atmosphere.timeCycleEnable",
  "rtx.atmosphere.moon0.enabled", "rtx.atmosphere.sunElevation", "rtx.atmosphere.sunRotation",
  "rtx.atmosphere.cloudDensity", "rtx.volumetrics.transmittanceMeasurementDistanceMeters",
  "rtx.weather.precipitation.intensity", "rtx.atmosphere.starAxisElevation",
  "rtx.atmosphere.surfaceMoonBrightness", "rtx.atmosphere.noHorizon", "rtx.atmosphere.daytimeMoonBrightness")
print("convars " .. convars.nativeloader_sky_hour.value .. " " .. convars.nativeloader_sky_direction.value
  .. " " .. convars.nativeloader_sky_follow_map.value)
if SCRIPT == "defaults" then
  print("defaults " .. convars.nativeloader_sky_time_passes.value .. " " .. convars.nativeloader_sky_day_minutes.value)
  print("marker " .. tostring(data["nativeloader_companion/sky_defaults_client_v1.txt"]):gsub("\n", ""))
  local before = NATIVELOADER_SKY.clock()
  for _ = 1, 3000 do tick(0.02) end
  print("elapsed " .. tostring((NATIVELOADER_SKY.clock() - before) % 24))
  report("afterminute")
  return
end
if SCRIPT == "poster" then
  -- A second of the clock, a minute of a poster rendering, then a second again.
  cmd("nativeloader_sky_time_passes", "1")
  local before = NATIVELOADER_SKY.clock()
  for _ = 1, 50 do tick(0.02) end
  local ran = (NATIVELOADER_SKY.clock() - before) % 24
  POSTER_STATE = "rendering"
  local held, sent = NATIVELOADER_SKY.clock(), #calls
  for _ = 1, 3000 do tick(0.02) end
  print("held " .. string.format("%.9f", (NATIVELOADER_SKY.clock() - held) % 24) .. " " .. (#calls - sent))
  POSTER_STATE = "done"
  local resumed = NATIVELOADER_SKY.clock()
  for _ = 1, 50 do tick(0.02) end
  print("ran " .. string.format("%.9f %.9f", ran, (NATIVELOADER_SKY.clock() - resumed) % 24))
  return
end
if SCRIPT == "ownership" then
  tick(1)
  report("owned")
  print("interval " .. tostring(delays.nativeloader_sky))
  cmd("nativeloader_sky_interval", "0.1")  -- how often, not what: the map's sky stays its own
  tick(1)
  report("adjusted")
  print("interval_now " .. tostring(delays.nativeloader_sky))
  cmd("nativeloader_weather", "overcast")
  tick(31)
  report("taken", "rtx.skyMode", "rtx.atmosphere.cloudDensity")
  return
end
if SCRIPT == "fixed" then
  -- ADR 0248: the fixed sky stays, whatever Follow the map's sun says, until a setting changes here.
  print("taken_start " .. tostring(NATIVELOADER_SKY.takenOver()))
  tick(31)
  report("owned", "rtx.skyMode", "rtx.atmosphere.cloudDensity")
  cmd("nativeloader_sky_status")
  vgui = { Create = function() return setmetatable({ GetChildren = function() return {} end },
    { __index = function() return function() end end }) end }
  NATIVELOADER_SKY.buildPanel(setmetatable({}, { __index = function(_, kind)
    return function(_, text)
      print("panel " .. kind .. "|" .. tostring(text))
      return setmetatable({}, { __index = function() return function() end end })
    end
  end }))
  cmd("nativeloader_weather", "overcast")
  tick(1)
  report("taken", "rtx.skyMode", "rtx.atmosphere.cloudDensity")
  print("taken_after " .. tostring(NATIVELOADER_SKY.takenOver()))
  return
end
if SCRIPT == "mapsky" then
  -- ADR 0249: which sky the map shows, the engine's settings for its 3D skybox and the choice saved for it, at the
  -- start and after each of STEPS ({ command, value }; "tick" waits that long, "shutdown" leaves the map).
  local function engineState(tag)
    print(string.format("%s r_3dsky=%s r_novis=%s forcenovis=%s vis_pas=%s warn=%s skyname=%s saved=%s here=%s", tag,
      engine.r_3dsky, engine.r_novis, luaEngine.rtx_patch_forcenovis, luaEngine.rtx_patch_vis_pas,
      luaEngine.rtx_show_3dsky_warning, engine.sv_skyname, convars.nativeloader_sky_engine_saved.value,
      convars.nativeloader_sky_here.value))
  end
  local function api(tag)
    local s = NATIVELOADER_SKY.mapSky()
    print(string.format("%s %s %s %s %s %s %s", tag, s.shown, s.sky, s.reason, tostring(s.threeD), tostring(s.package),
      tostring(NATIVELOADER_SKY.takenOver())))
    print("line" .. tag:sub(4) .. " " .. NATIVELOADER_SKY.line())
  end
  engineState("engine0")
  report("sky0", "rtx.skyMode", "rtx.ignoreGameDirectionalLights", "rtx.atmosphere.cloudDensity")
  api("api0")
  for i, step in ipairs(STEPS or {}) do
    if step[1] == "tick" then tick(step[2])
    elseif step[1] == "shutdown" then for _, fn in pairs(hooks.ShutDown or {}) do fn() end
    else cmd(step[1], step[2]) end
    tick(0.02)
    engineState("engine" .. i)
    report("sky" .. i, "rtx.skyMode", "rtx.ignoreGameDirectionalLights", "rtx.atmosphere.cloudDensity")
    api("api" .. i)
  end
  print("choices " .. (data["nativeloader_companion/sky_maps.txt"] or ""):gsub("\n", ";"))
  print("enginelog " .. table.concat(engineLog, ","))
  print("message " .. convars.nativeloader_sky_message.value .. " "
    .. tostring(data["nativeloader_companion/sky_message_client_v1.txt"]):gsub("\n", ""))
  local lines, realPrint = {}, print
  print = function(text) lines[#lines + 1] = text end
  cmd("nativeloader_sky_status")
  print = realPrint
  for _, line in ipairs(lines) do
    local tag = line:match("^%[nativeloader%] (%a+ %a+):")
    if tag == "this map" then print("status_message " .. line) elseif tag == "map sky" then print("status_map " .. line) end
  end
  return
end
if SCRIPT == "entry" then
  -- R16: the player chose a time (Follow the map's sun unticked). Modern House RTX loads after the map
  -- started, sets its sky once its own timer runs, and again later; the player's sky stays.
  report("entered", "rtx.skyMode", "rtx.atmosphere.sunElevation", "rtx.atmosphere.cloudDensity")
  MHRTX_Config = {}
  MHRTX = { ApplySettings = function()
    RemixConfig.SetConfigVariable("rtx.atmosphere.sunElevation", "21")
    RemixConfig.SetConfigVariable("rtx.atmosphere.cloudDensity", "4")
  end }
  tick(0.02)
  print("followed " .. tostring(MHRTX.ApplySettings == MHRTX.nativeLoaderApply))
  MHRTX.ApplySettings()
  report("after", "rtx.atmosphere.sunElevation", "rtx.atmosphere.cloudDensity")
  tick(1)
  report("later", "rtx.atmosphere.sunElevation")
  return
end
if SCRIPT == "follow" then
  -- Modern House RTX setting its sky again (its timer, 23, 43 and 63 s into the map) before and
  -- after the player took the sky over; no timer of the companion runs in between.
  MHRTX.ApplySettings(true)
  report("theirs", "rtx.atmosphere.sunElevation")
  cmd("nativeloader_sky_time", "midnight")
  report("mine", "rtx.atmosphere.sunElevation")
  MHRTX.ApplySettings(true)
  report("again", "rtx.atmosphere.sunElevation", "rtx.atmosphere.cloudDensity")
  print("followed " .. tostring(MHRTX.ApplySettings == MHRTX.nativeLoaderApply))
  -- A reload of the add-on's Lua replaces the function: wrapped again by the 10 s timer.
  MHRTX.ApplySettings = function() RemixConfig.SetConfigVariable("rtx.atmosphere.sunElevation", "35") end
  tick(10)
  MHRTX.ApplySettings(true)
  report("reloaded", "rtx.atmosphere.sunElevation")
  return
end
if SCRIPT == "release" then
  cmd("nativeloader_weather_seconds", "0")
  cmd("nativeloader_weather", "rainstorm")
  tick(0.25)
  report("rain", "rtx.atmosphere.cloudDensity", "rtx.weather.precipitation.intensity",
    "rtx.weather.precipitation.spawnRadiusMeters", "rtx.atmosphere.lightningStrikesPerMinute")
  cmd("nativeloader_weather", "")
  report("released", "rtx.atmosphere.cloudDensity", "rtx.weather.precipitation.intensity",
    "rtx.weather.precipitation.spawnRadiusMeters", "rtx.atmosphere.lightningStrikesPerMinute")
  local P = include("nativeloader/weather_presets.lua")
  print("defaults " .. P.defaults["rtx.weather.precipitation.spawnRadiusMeters"] .. " "
    .. P.defaults["rtx.atmosphere.lightningStrikesPerMinute"] .. " " .. P.defaults["rtx.weather.precipitation.intensity"])
  local before = #calls
  tick(10)
  print("quiet " .. (#calls - before))
  return
end
if SCRIPT == "skybox" then
  cmd("nativeloader_sky", "0")
  report("skybox", "rtx.skyMode", "rtx.ignoreGameDirectionalLights")
  return
end
if SCRIPT == "horizon" then
  -- R26: No horizon ticked and unticked in the panel, the status line, the reset.
  local before = #calls
  cmd("nativeloader_sky_no_horizon", "1")
  report("horizon_on", "rtx.atmosphere.noHorizon")
  print("horizon_calls " .. (#calls - before) .. " " .. convars.nativeloader_sky_follow_map.value)
  tick(1)
  local lines, realPrint = {}, print
  print = function(text) lines[#lines + 1] = text end
  cmd("nativeloader_sky_status")
  print = realPrint
  for _, line in ipairs(lines) do
    if line:find("night sky", 1, true) then print("status_night " .. line) end
  end
  before = #calls
  cmd("nativeloader_sky_no_horizon", "0")
  print("horizon_off " .. (#calls - before) .. " " .. tostring(value("rtx.atmosphere.noHorizon")))
  cmd("nativeloader_sky_no_horizon", "1")
  cmd("nativeloader_sky_reset")
  -- Reset restores the physical horizon in Enhanced and a subsequent switch to Standard.
  report("horizon_reset_mode", "rtx.skyMode", "rtx.atmosphere.noHorizon")
  cmd("nativeloader_sky_enhanced", "0")
  report("horizon_reset", "rtx.atmosphere.noHorizon")
  return
end
if SCRIPT == "horizon_owned" then
  -- R26: on a map whose add-on owns the sky, the player's No horizon reaches that sky without taking
  -- it over (the companion sends that option alone).
  local options, seen = {}, {}
  for _, call in ipairs(calls) do
    if not seen[call[1]] then seen[call[1]] = true options[#options + 1] = call[1] end
  end
  print("owned_start_options " .. (#options > 0 and table.concat(options, ",") or "none"))
  local before = #calls
  cmd("nativeloader_sky_no_horizon", NEXT_HORIZON)
  print("owned_calls " .. (#calls - before) .. " " .. tostring(value("rtx.skyMode")) .. " "
    .. tostring(value("rtx.atmosphere.noHorizon")))
  tick(11)
  report("owned_after", "rtx.skyMode")
  return
end
if SCRIPT == "slider" then
  -- The panel's sliders write back what they show: the map's direction rounded to whole degrees,
  -- the time to two decimals. That is not the player moving them.
  local direction = convars.nativeloader_sky_direction.value
  cmd("nativeloader_sky_direction", tostring(math.floor(tonumber(direction) + 0.5)))
  cmd("nativeloader_sky_hour", convars.nativeloader_sky_hour.value)
  print("written_back " .. convars.nativeloader_sky_follow_map.value)
  cmd("nativeloader_sky_direction", tostring(tonumber(direction) + 30))
  print("moved " .. convars.nativeloader_sky_follow_map.value)
  return
end
if SCRIPT == "shelter" then
  cmd("nativeloader_weather_seconds", "0")
  cmd("nativeloader_weather", "rainstorm")
  tick(0.25)
  report("outside", "rtx.weather.precipitation.intensity", "rtx.weather.precipitation.occludeUnderCover")
  COVERED = true
  tick(0.25)
  report("fading", "rtx.weather.precipitation.intensity")
  tick(0.25)
  report("inside", "rtx.weather.precipitation.intensity", "rtx.atmosphere.cloudDensity")
  COVERED = false
  tick(0.25) tick(0.25)
  report("again", "rtx.weather.precipitation.intensity")
  return
end
if SCRIPT == "night" then
  report("moonlight_night", "rtx.atmosphere.surfaceMoonBrightness")
  cmd("nativeloader_sky_time", "dusk")
  report("moonlight_dusk", "rtx.atmosphere.surfaceMoonBrightness")
  cmd("nativeloader_sky_time", "night")
  local north = tonumber(convars.nativeloader_sky_direction.value)
  local sky = M.sky(23, M.SEASONS.summer, M.MOON_PHASES.full, north, nil, M.moonLatitude(nil, 1, 0.8))
  print(string.format("night %.2f %.2f %.2f", sky.moon.bearing, sky.moon.elevation, sky.sun.elevation))
  return
end
if SCRIPT == "eclipse" then
  local function dir(e, b) e, b = math.rad(e), math.rad(b) return { math.cos(e) * math.sin(b), math.sin(e), math.cos(e) * math.cos(b) } end
  local function angle(a, b) return math.deg(math.acos(math.max(-1, math.min(1, a[1] * b[1] + a[2] * b[2] + a[3] * b[3])))) end
  -- Where Remix was told the sun and the moon are: the moon's distance from the antisolar point and
  -- from the sun, the sun's height, the phase, and the time and follow settings.
  local function geometry(tag)
    local sun = dir(tonumber(value("rtx.atmosphere.sunElevation")), tonumber(value("rtx.atmosphere.sunRotation")))
    local moon = dir(tonumber(value("rtx.atmosphere.moon0.elevation")), tonumber(value("rtx.atmosphere.moon0.rotation")))
    print(string.format("%s %.3f %.3f %.3f %s %s %s", tag, angle(moon, { -sun[1], -sun[2], -sun[3] }), angle(moon, sun),
      tonumber(value("rtx.atmosphere.sunElevation")), value("rtx.atmosphere.moon0.phase"),
      convars.nativeloader_sky_hour.value, convars.nativeloader_sky_follow_map.value))
  end
  report("look", "rtx.atmosphere.eclipseEnable", "rtx.atmosphere.eclipseUmbraScale", "rtx.atmosphere.eclipsePenumbraScale",
    "rtx.atmosphere.eclipseSunScale", "rtx.atmosphere.moonTextureEnable", "rtx.atmosphere.starMapEnable",
    "rtx.atmosphere.nightSkyBrightness")
  geometry("plain")
  cmd("nativeloader_sky_eclipse", "lunar")
  geometry("lunar100")
  cmd("nativeloader_sky_eclipse_amount", "50")
  geometry("lunar50")
  cmd("nativeloader_sky_eclipse", "solar")
  geometry("solar50")
  cmd("nativeloader_sky_eclipse", "")
  geometry("none")
  cmd("nativeloader_sky_stars", "procedural")
  report("stars", "rtx.atmosphere.starMapEnable", "rtx.atmosphere.nightSkyBrightness")
  return
end
if SCRIPT == "moonday" then
  -- ADR 0207: the moon by day, its slider, the status line and the reset.
  cmd("nativeloader_sky_moon_day", "2.5")
  report("moonday_bright", "rtx.atmosphere.daytimeMoonBrightness")
  print("moonday_follow " .. convars.nativeloader_sky_follow_map.value)
  cmd("nativeloader_sky_moon_day", "9")
  report("moonday_high", "rtx.atmosphere.daytimeMoonBrightness")
  cmd("nativeloader_sky_moon_day", "0")
  report("moonday_off", "rtx.atmosphere.daytimeMoonBrightness")
  local lines, realPrint = {}, print
  print = function(text) lines[#lines + 1] = text end
  cmd("nativeloader_sky_status")
  print = realPrint
  for _, line in ipairs(lines) do
    if line:find("moon by day", 1, true) then print("moonday_status " .. line) end
  end
  cmd("nativeloader_sky_reset")
  -- The reset gives the defaults: the Enhanced sky (the user, 2026-11-26), which takes the moon by day itself, so the
  -- Standard sky's option is sent again when Standard is chosen.
  report("moonday_reset_mode", "rtx.skyMode")
  cmd("nativeloader_sky_enhanced", "0")
  report("moonday_reset", "rtx.atmosphere.daytimeMoonBrightness")
  return
end
if SCRIPT == "panel" or SCRIPT == "horizon_panel" then
  -- ADR 0227: both pages of the tab built against a panel that records each control (DForm's methods).
  local skyWidgets, byConvar = {}, {}
  local function recorder(tag)
    return setmetatable({}, { __index = function(_, kind)
      return function(_, ...)
        local parts = { tag, kind }
        for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
        print("panel " .. table.concat(parts, "|"))
        -- A combo box's choices (ADR 0249's This map and Other maps) are recorded too.
        local widget = setmetatable({ enabled = true }, { __index = function(_, method)
          if method == "AddChoice" then
            return function(_, label, data) print("panel " .. tag .. "|choice|" .. tostring(label) .. "|" .. tostring(data)) end
          elseif method == "SetEnabled" then
            return function(self, enabled) self.enabled = enabled end
          end
          return function() end
        end })
        if SCRIPT == "horizon_panel" and tag == "sky" then
          skyWidgets[#skyWidgets + 1] = widget
          if parts[4] and (kind == "CheckBox" or kind == "ComboBox") then byConvar[parts[4]] = widget end
        end
        return widget
      end
    end })
  end
  vgui = { Create = function() return setmetatable({ GetChildren = function() return {} end },
    { __index = function() return function() end end }) end }
  NATIVELOADER_SKY.buildPanel(recorder("sky"))
  if SCRIPT == "horizon_panel" then
    local function check(key, toggle)
      for i = 1, #skyWidgets do
        local widget = skyWidgets[i]
        if rawget(widget, "Think") then widget:Think() end
      end
      cmd("nativeloader_sky_no_horizon", toggle)
      print(key .. " " .. tostring(byConvar.nativeloader_sky_no_horizon.enabled)
        .. " " .. tostring(byConvar.nativeloader_sky_stars.enabled)
        .. " " .. tostring(value("rtx.skyMode")) .. " " .. tostring(value("rtx.atmosphere.noHorizon")))
    end
    check("enhanced_on", "1")
    cmd("nativeloader_sky_enhanced", "0") tick(1)
    check("standard_off", "0")
    cmd("nativeloader_sky_enhanced", "1") tick(1)
    check("enhanced_again", "1")
    return
  end
  NATIVELOADER_SKY.buildNightPanel(recorder("night"))
  return
end
if SCRIPT == "editor" or SCRIPT == "editor_owned" then
  -- ADR 0227: the night sky editor's options, as Remix was last given them.
  local EDITOR = { "rtx.atmosphere.starMapBrightness", "rtx.atmosphere.starMapStarBrightness",
    "rtx.atmosphere.starMapStarSaturation", "rtx.atmosphere.starMapConstellationBrightness",
    "rtx.atmosphere.starMapConstellationSaturation", "rtx.atmosphere.starMapGalaxyBrightness",
    "rtx.atmosphere.starMapGalaxySaturation", "rtx.atmosphere.starMapNebulaBrightness",
    "rtx.atmosphere.starMapNebulaSaturation", "rtx.atmosphere.starBrightness", "rtx.atmosphere.starDensity",
    "rtx.atmosphere.starTwinkleSpeed", "rtx.atmosphere.moon0.brightness", "rtx.atmosphere.moon0.angularRadius",
    "rtx.atmosphere.haloMoonBrightness", "rtx.atmosphere.moon0.darkSideBrightness",
    "rtx.atmosphere.shootingStarsPerMinute", "rtx.atmosphere.shootingStarBrightness" }
  if SCRIPT == "editor_owned" then
    -- A map whose add-on owns the sky: the start sends only what is off its default; a change sends its
    -- option alone, without taking that sky over (no skyMode, nothing more on the 10 s timer).
    local options, seen = {}, {}
    for _, call in ipairs(calls) do
      if not seen[call[1]] then seen[call[1]] = true options[#options + 1] = call[1] end
    end
    print("owned_start_options " .. (#options > 0 and table.concat(options, ",") or "none"))
    local before = #calls
    cmd("nativeloader_sky_constellations_brightness", "0")
    print("owned_calls " .. (#calls - before) .. " " .. tostring(value("rtx.skyMode")) .. " "
      .. tostring(value("rtx.atmosphere.starMapConstellationBrightness")))
    tick(11)
    report("owned_after", "rtx.skyMode")
    return
  end
  report("editor_start", unpack(EDITOR))
  local before = #calls
  cmd("nativeloader_sky_stars_brightness", "3")
  print("editor_calls " .. (#calls - before) .. " " .. convars.nativeloader_sky_follow_map.value)
  report("editor_stars", "rtx.atmosphere.starMapStarBrightness")
  cmd("nativeloader_sky_stars_brightness", "50")
  report("editor_high", "rtx.atmosphere.starMapStarBrightness")
  cmd("nativeloader_sky_stars_brightness", "x")
  report("editor_text", "rtx.atmosphere.starMapStarBrightness")
  cmd("nativeloader_sky_night_image", "2")
  cmd("nativeloader_sky_earthshine", "3")
  cmd("nativeloader_sky_moon_glow", "0.5")
  cmd("nativeloader_sky_shooting_stars", "6")
  cmd("nativeloader_sky_simulated_density", "0.75")
  report("editor_scaled", "rtx.atmosphere.starMapBrightness", "rtx.atmosphere.moon0.darkSideBrightness",
    "rtx.atmosphere.haloMoonBrightness", "rtx.atmosphere.shootingStarsPerMinute", "rtx.atmosphere.starDensity")
  -- The moon's size: the disc, the same moonlight on the ground, and the eclipse geometry by its radius.
  cmd("nativeloader_sky_time", "night")
  report("editor_moon16", "rtx.atmosphere.surfaceMoonBrightness")
  cmd("nativeloader_sky_moon_size", "3.2")
  report("editor_moon32", "rtx.atmosphere.moon0.angularRadius", "rtx.atmosphere.surfaceMoonBrightness")
  local function dir(e, b) e, b = math.rad(e), math.rad(b) return { math.cos(e) * math.sin(b), math.sin(e), math.cos(e) * math.cos(b) } end
  local function angle(a, b) return math.deg(math.acos(math.max(-1, math.min(1, a[1] * b[1] + a[2] * b[2] + a[3] * b[3])))) end
  local function antisolar()
    local sun = dir(tonumber(value("rtx.atmosphere.sunElevation")), tonumber(value("rtx.atmosphere.sunRotation")))
    local moon = dir(tonumber(value("rtx.atmosphere.moon0.elevation")), tonumber(value("rtx.atmosphere.moon0.rotation")))
    return angle(moon, { -sun[1], -sun[2], -sun[3] })
  end
  print(string.format("editor_clear %.3f", antisolar()))
  cmd("nativeloader_sky_eclipse_amount", "50")
  cmd("nativeloader_sky_eclipse", "lunar")
  print(string.format("editor_lunar50 %.3f %.3f", antisolar(), M.eclipseSeparation("lunar", 0.5, 1.6)))
  cmd("nativeloader_sky_eclipse", "")
  -- The night glow scales the weather's airglow (5 % of it under the night sky image).
  local airglow = tonumber(value("rtx.atmosphere.nightSkyBrightness"))
  cmd("nativeloader_sky_night_glow", "2")
  print(string.format("editor_glow %.6g %.6g", airglow, tonumber(value("rtx.atmosphere.nightSkyBrightness"))))
  local lines, realPrint = {}, print
  print = function(text) lines[#lines + 1] = text end
  cmd("nativeloader_sky_status")
  print = realPrint
  local status = {}
  for _, line in ipairs(lines) do if line:find("night sky editor", 1, true) then status[#status + 1] = line end end
  print("editor_status " .. table.concat(status, " | "))
  cmd("nativeloader_sky_night_reset")
  report("editor_reset", unpack(EDITOR))
  print(string.format("editor_reset_glow %.6g", tonumber(value("rtx.atmosphere.nightSkyBrightness"))))
  return
end
if SCRIPT == "fog" then
  -- (Colours hold spaces, so they are printed apart from report's option=value pairs.)
  cmd("nativeloader_remix_fog", "heavyFog")
  report("preset", "rtx.volumetrics.enable", "rtx.volumetrics.enableFogRemap",
    "rtx.volumetrics.transmittanceMeasurementDistanceMeters", "rtx.volumetrics.anisotropy")
  print("colours " .. value("rtx.volumetrics.transmittanceColor") .. "|" .. value("rtx.volumetrics.singleScatteringAlbedo"))
  cmd("nativeloader_weather", "foggy")
  tick(31)
  report("weather", "rtx.volumetrics.transmittanceMeasurementDistanceMeters", "rtx.atmosphere.cloudDensity")
  print("weather_colour " .. value("rtx.volumetrics.transmittanceColor"))
  cmd("nativeloader_remix_fog", "")
  tick(0.25)
  report("cleared", "rtx.volumetrics.transmittanceMeasurementDistanceMeters")
  return
end
cmd("nativeloader_weather", "rainstorm")
tick(15)
report("mid", "rtx.atmosphere.cloudDensity", "rtx.weather.precipitation.intensity")
tick(16)
report("end", "rtx.atmosphere.cloudDensity", "rtx.weather.precipitation.intensity", "rtx.atmosphere.lightningStrikesPerMinute")
local north = convars.nativeloader_sky_direction.value
cmd("nativeloader_sky_time", "18:00")
report("hour", "rtx.atmosphere.sunElevation", "rtx.atmosphere.sunRotation")
print("after " .. convars.nativeloader_sky_follow_map.value .. " " .. convars.nativeloader_sky_hour.value .. " "
  .. convars.nativeloader_sky_direction.value .. " " .. north)
local expect = M.sky(18, M.SEASONS.summer, M.MOON_PHASES.full, tonumber(north))
print(string.format("expect %.3f %.3f", expect.sun.elevation, expect.sun.bearing))
cmd("nativeloader_sky_day_minutes", "24")
cmd("nativeloader_sky_time_passes", "1")
for _ = 1, 240 do tick(0.25) end
cmd("nativeloader_sky_time_passes", "0")
print("clock " .. convars.nativeloader_sky_hour.value)
cmd("nativeloader_weather", "")
local before = #calls
tick(10)
print("left " .. (#calls - before))
cmd("nativeloader_sky_status")
'''


@unittest.skipUnless(LUAJIT, 'LuaJIT is not installed')
class SkyTests(unittest.TestCase):
    def run_lua(self, body: str, **globals_) -> dict:
        with tempfile.TemporaryDirectory(dir=REPO / 'out' / 'tmp') as scratch:
            script = Path(scratch) / 'harness.lua'
            prelude = f'LUA = {json.dumps(str(LUA))}\nCONSTRUCT = {json.dumps(CONSTRUCT)}\nCONF = {{}}\n'
            for name, value in globals_.items():
                prelude += f'{name} = {lua_string(value) if isinstance(value, bytes) else json.dumps(value)}\n'
            script.write_text(prelude + body, encoding='utf-8')
            done = subprocess.run([LUAJIT, str(script)], capture_output=True, text=True, timeout=60, cwd=scratch)
        self.assertEqual(done.returncode, 0, done.stderr + done.stdout)
        lines = {}
        for line in done.stdout.splitlines():
            key, _, rest = line.partition(' ')
            lines.setdefault(key, rest)
        return lines

    @staticmethod
    def numbers(text):
        return [float(v) for v in text.split()]

    def test_standard_remix_writes_match_the_pre_enhanced_companion(self):
        # Lua pairs() has no traversal order. Keep the sequence for EACH key in each action,
        # including repeated writes, and fingerprint the complete key/value strings.
        body = SESSION_SETUP + r'''
local last = 0
local function capture(stage)
  print("stage " .. stage)
  for i = last + 1, #calls do print(calls[i][1] .. "=" .. calls[i][2]) end
  last = #calls
end
hook.Run("InitPostEntity") capture("map_start")
for _, fn in ipairs(simple) do fn() end capture("late_refresh")
tick(0.02) capture("tick")
cmd("nativeloader_weather", "rainstorm") tick(15) capture("blend")
tick(16) capture("rain")
cmd("nativeloader_sky_time", "night") capture("night")
cmd("nativeloader_sky_moon", "lastQuarter") capture("moon")
cmd("nativeloader_weather", "") capture("leave_weather")
cmd("nativeloader_sky_here", "map") capture("map_sky")
hook.Run("ShutDown") capture("exit")
'''
        writes = {}
        for line in self.run_lines(body, MAP='gm_construct', BSP=self.sky_map(), LINE_DEFAULT=True):
            if line.startswith('stage '):
                stage = writes[line[6:]] = []
            elif line.startswith('rtx.'):
                stage.append(line)
        actual = {stage: (len(lines), hashlib.sha256('\n'.join(sorted(lines, key=lambda s: s.partition('=')[0]))
                                                    .encode()).hexdigest()[:24]) for stage, lines in writes.items()}
        # Captured from the sky at 98b5450c with the same LuaJIT harness.
        self.assertEqual(actual, {
            'map_start': (101, 'd59b1f11fcd2a6c0fd271bda'), 'late_refresh': (101, 'd59b1f11fcd2a6c0fd271bda'),
            'tick': (3, '5d807e8a42072cc16ca1b4e4'), 'blend': (42, '36c16111eadab3331e12d64c'),
            'rain': (37, '297a2f34353f0e80bc8582ea'), 'night': (7, '842b8cb7add522118964b181'),
            'moon': (3, '7ff92c3b53db3736e3dca1a6'), 'leave_weather': (48, '7c9f432192e046b41bc92dbe'),
            'map_sky': (3, '061edb7fa0b63b74831ef606'), 'exit': (0, 'e3b0c44298fc1c149afbf4c8'),
        })
        self.enhanced_session(r'''
local standard = {}
for _, pair in ipairs(calls) do standard[pair[1]] = pair[2] end
cmd("nativeloader_sky_enhanced", "1") cmd("nativeloader_sky_enhanced", "0")
for key, expected in pairs(standard) do assert(value(key) == expected, key) end
''', 'PRESET.nativeloader_sky_enhanced="0"')

    def settings(self, text):
        return dict(part.split('=', 1) for part in text.split()[1:])

    def enhanced_session(self, steps, setup='', **globals_):
        body = ('PRESET = {nativeloader_sky_enhanced="1"}\n' + setup + '\n' + SESSION_SETUP + r'''
local function numos(key) return value("rtx.atmosphere.numos." .. key) end
local volume = "rtx.volumetrics.enable"
local function volumeWrites()
  local n = 0
  for _, call in ipairs(calls) do if call[1] == volume then n = n + 1 end end
  return n
end
local looks = include("nativeloader/enhanced_weather.lua").presets
hook.Run("InitPostEntity")
for _, fn in ipairs(simple) do fn() end
''' + steps)
        return self.run_lua(body, MAP='gm_construct', BSP=self.sky_map(), LINE_DEFAULT=True, **globals_)

    def test_enhanced_weather_uses_each_look_and_keeps_the_host_precipitation(self):
        self.enhanced_session(r'''
assert(value("rtx.skyMode") == "2" and volumeWrites() == 0)
assert(numos("unitsPerMeter") == "52.4934" and numos("aerialPerspective") == "True")
assert(numos("weather.preset") == "None" and numos("weather.followGame") == "False")
cmd("nativeloader_weather_seconds", "0")
local presets = NATIVELOADER_SKY.presets
assert(#presets.order == 12)
for _, name in ipairs(presets.order) do
  cmd("nativeloader_weather", name)
  for key, setting in pairs(looks[name]) do
    if key ~= "cloudCoverageMean" and key ~= "cloudWindSpeed" and key ~= "cloudWindDirection" then
      assert(numos(key) == M.optionText(setting), name .. "." .. key)
    end
  end
  assert(tonumber(value("rtx.weather.precipitation.intensity")) == presets.presets[name].precipitationIntensity, name)
end
cmd("nativeloader_weather", "thunderstorm")
local windy = tonumber(numos("cloudWindSpeed"))
local bearing = numos("cloudWindDirection")
tick(9)
assert(tonumber(numos("cloudWindSpeed")) ~= windy and numos("cloudWindDirection") ~= bearing)
COVERED = true tick(1)
assert(value("rtx.weather.precipitation.intensity") == "0")
assert(value("rtx.atmosphere.cloudDensity") == nil and value("rtx.volumetrics.transmittanceColor") == nil)
''')

    def test_every_weather_and_built_in_look_passes_the_editors_own_check(self):
        self.run_lua(GMOD_MOCKS + r'''
local weather = include("nativeloader/enhanced_weather.lua")
local editor = include("nativeloader/enhanced_editor.lua")(weather)
local function check(name, look)
  local ok, why = editor.check(look)
  assert(ok, name .. ": " .. tostring(why))
end
for name, look in pairs(weather.presets) do check(name, look) end
for _, builtin in ipairs(editor.builtins) do check(builtin.name, editor.builtin(builtin)) end
''')

    def test_weather_blends_its_haze_absorption_and_returns_to_the_library_default(self):
        # Give one weather its own absorption in memory. The reviewer tunes the shipped weather rows.
        self.enhanced_session(r'''
local default = "0.0044, 0.0044, 0.0044"
cmd("nativeloader_weather_seconds", "0") cmd("nativeloader_weather", "clear")
assert(numos("mieAbsorption") == default)
cmd("nativeloader_weather_seconds", "2") cmd("nativeloader_weather", "hazy")
tick(1) assert(numos("mieAbsorption") == "0.00242, 0.00242, 0.00242")
tick(1) assert(numos("mieAbsorption") == "0.00044, 0.00044, 0.00044")
cmd("nativeloader_weather", "clear") tick(2) assert(numos("mieAbsorption") == default)
assert(not convars.nativeloader_sky_own_look:GetBool())
''', r'''
local readLua = dofile
function dofile(path)
  local data = readLua(path)
  if path:match("/enhanced_weather%.lua$") then data.presets.hazy.mieAbsorption = {0.00044, 0.00044, 0.00044} end
  return data
end
''')

    def test_enhanced_weather_blends_and_can_be_interrupted_or_left_to_remix(self):
        self.enhanced_session(r'''
-- The native SetConfigVariable accepts an empty string without applying it. Check the effective preset.
local function manualPreset()
  local key = "rtx.atmosphere.numos.weather.preset"
  local current = CONF[key]
  for _, pair in ipairs(calls) do if pair[1] == key and pair[2] ~= "" then current = pair[2] end end
  return current
end
assert(manualPreset() == "None" and numos("weather.transitionSeconds") == "0")
cmd("nativeloader_weather_seconds", "20")
cmd("nativeloader_weather", "foggy")
tick(10)
local halfway = 1 / (0.5 / looks.partlyCloudy.fogVisibilityMeters + 0.5 / looks.foggy.fogVisibilityMeters)
assert(math.abs(tonumber(numos("fogVisibilityMeters")) - halfway) < 0.01)
if not looks.partlyCloudy.cloudLayer2Enable and looks.foggy.cloudLayer2Enable then
  assert(tonumber(numos("cloudLayer2BaseHeightMeters")) == looks.foggy.cloudLayer2BaseHeightMeters)
end
for _, key in ipairs({"cloudLayer2Enable", "cloudCirrusEnable"}) do
  assert(numos(key) == M.optionText(looks.partlyCloudy[key] or looks.foggy[key]))
end
cmd("nativeloader_weather", "thunderstorm")
assert(math.abs(tonumber(numos("fogVisibilityMeters")) - halfway) < 0.01)
tick(20)
assert(tonumber(numos("fogVisibilityMeters")) == looks.thunderstorm.fogVisibilityMeters)
assert(tonumber(numos("cloudLayer2BaseHeightMeters")) == looks.thunderstorm.cloudLayer2BaseHeightMeters)
cmd("nativeloader_weather", "")
assert(numos("fogVisibilityMeters") == "1600" and numos("cloudDensity") == "20")
assert(manualPreset() == "Fair" and numos("weather.followGame") == "True" and numos("weather.transitionSeconds") == "10")
assert(volumeWrites() == 0)
''', 'CONF["rtx.atmosphere.numos.fogVisibilityMeters"]="1600"\nCONF["rtx.atmosphere.numos.weather.preset"]="Fair"')

    def test_enhanced_celestial_controls_use_one_clock_and_one_library_moon(self):
        self.enhanced_session(r'''
assert(numos("timeCycleEnable") == "False" and numos("nightSkyStars") == "True")
assert(numos("realMoonEnabled") == "False" and numos("moon0.enabled") == "True")
cmd("nativeloader_sky_time", "noon")
cmd("nativeloader_sky_season", "winter")
cmd("nativeloader_sky_direction", "115")
for name, phase in pairs(M.MOON_PHASES) do
  cmd("nativeloader_sky_moon", name)
  local sky = M.sky(12, M.SEASONS.winter, phase, 115, nil, M.moonLatitude(nil, 1, 0.8))
  assert(tonumber(numos("moon0.phase")) == phase)
  assert(math.abs(tonumber(numos("moon0.rotation")) - sky.moon.bearing) < 0.001)
  assert(math.abs(tonumber(numos("sunElevation")) - sky.sun.elevation) < 0.001)
end
assert(numos("dayOfYear") == tostring(M.SEASONS.winter) and numos("northOffsetDegrees") == "115")
cmd("nativeloader_sky_moon_day", "0")
assert(numos("moon0.enabled") == "False")
cmd("nativeloader_sky_moon_day", "2")
assert(numos("moon0.color") == "2, 2, 2")
cmd("nativeloader_sky_eclipse", "lunar")
assert(numos("moon0.phase") == "-1" and numos("moon0.color") == "1, 1, 1")
cmd("nativeloader_sky_eclipse_amount", "0")
local contact = numos("moon0.elevation")
cmd("nativeloader_sky_eclipse_amount", "100")
assert(numos("moon0.elevation") ~= contact)
cmd("nativeloader_sky_eclipse", "solar")
assert(numos("moon0.phase") == "0" and tonumber(numos("sunElevation")) > 15)
cmd("nativeloader_sky_time", "18:00")
tick(0.02) tick(60)
assert(numos("timeOfDayHours") == "18")
cmd("nativeloader_sky_day_minutes", "40") cmd("nativeloader_sky_time_passes", "1")
tick(60)
assert(numos("timeOfDayHours") == "18.6")
local writes = #calls
POSTER_STATE = "rendering" tick(36)
assert(#calls == writes)
POSTER_STATE = "done" tick(1)
assert(math.abs(tonumber(numos("timeOfDayHours")) - 18.61) < 0.001)
cmd("nativeloader_sky_no_horizon", "1") cmd("nativeloader_sky_stars", "procedural")
assert(value("rtx.atmosphere.noHorizon") == "True" and value("rtx.atmosphere.starMapEnable") == "False")
assert(numos("nightSkyImage") == "True")
''', POSTER_SIM=True)

    def test_enhanced_star_choice_is_saved_independently_and_only_sent_in_enhanced(self):
        self.enhanced_session(r'''
local choice = "nativeloader_sky_enhanced_stars"
local option = "rtx.atmosphere.numos.nightSkyImage"
assert(convars[choice].archived and convars[choice].default=="map" and value(option)=="True")
local count = #calls
cmd(choice,"real")
assert(#calls==count+1 and calls[#calls][1]==option and value(option)=="False")
assert(value("rtx.atmosphere.starMapEnable")=="True" and not NATIVELOADER_SKY.takenOver())
cmd("nativeloader_sky_stars","procedural")
assert(value("rtx.atmosphere.starMapEnable")=="False" and value(option)=="False")
cmd("nativeloader_sky_night_reset")
assert(convars[choice].value=="map" and value(option)=="True" and value("rtx.atmosphere.starMapEnable")=="False")
cmd("nativeloader_sky_enhanced","0")
count=#calls
cmd(choice,"real") tick(0)
for i=count+1,#calls do assert(calls[i][1]~=option) end
assert(value("rtx.skyMode")=="1" and value("rtx.atmosphere.starMapEnable")=="False")
cmd("nativeloader_sky_enhanced","1")
assert(value(option)=="False" and value("rtx.atmosphere.starMapEnable")=="False")
''')
        for setup in ('PRESET.nativeloader_sky_enhanced="0"', 'NativeLoaderVR={state="running"}',
                      'SAVED_CHOICES="gm_construct map"', 'FIXED_SKY_ADDON=true'):
            with self.subTest(setup=setup):
                self.enhanced_session(r'''
assert(numos("nightSkyImage")==nil)
local count=#calls
cmd("nativeloader_sky_enhanced_stars","real")
assert(#calls==count and numos("nightSkyImage")==nil)
''', setup)
        self.enhanced_session(r'''
assert(numos("nightSkyImage")=="False" and numos("nightSkyStars")=="True")
assert(value("rtx.atmosphere.starMapBrightness")=="0.24" and value("rtx.atmosphere.shootingStarsPerMinute")=="4")
assert(value("rtx.atmosphere.haloMoonBrightness")=="7.5" and not NATIVELOADER_SKY.takenOver())
''', r'''
PRESET.nativeloader_sky_enhanced_stars="real"
PRESET.nativeloader_weather=""
PRESET.nativeloader_sky_night_image="2"
PRESET.nativeloader_sky_shooting_stars="4"
PRESET.nativeloader_sky_moon_glow="0.5"
''')

    def test_enhanced_forwards_the_night_editor_values_at_start_on_edit_and_on_reset(self):
        keys = ', '.join(json.dumps(key) for key in self.EDITOR_DEFAULTS)
        out = self.enhanced_session(f'report("night_start", {keys})\n' + r'''
local function opt(key) return value("rtx.atmosphere."..key) end
cmd("nativeloader_sky_enhanced_stars","real")
cmd("nativeloader_sky_style_night_gain_stops","7")
cmd("nativeloader_sky_style_star_gain_stops","-2")
cmd("nativeloader_sky_style_star_scintillation","3")
for _,field in ipairs({
  {"night_image",2,"starMapBrightness",0.24}, {"stars_brightness",3,"starMapStarBrightness",3},
  {"stars_colour",0.5,"starMapStarSaturation",0.5}, {"constellations_brightness",4,"starMapConstellationBrightness",4},
  {"constellations_colour",0.6,"starMapConstellationSaturation",0.6}, {"milky_way_brightness",2.5,"starMapGalaxyBrightness",2.5},
  {"milky_way_colour",1.4,"starMapGalaxySaturation",1.4}, {"nebulae_brightness",0,"starMapNebulaBrightness",0},
  {"nebulae_colour",0.35,"starMapNebulaSaturation",0.35}, {"simulated_brightness",2.5,"starBrightness",1.25},
  {"simulated_density",0.8,"starDensity",0.8}, {"simulated_twinkle",0,"starTwinkleSpeed",0},
  {"moon_size",3,"moon0.angularRadius",3}, {"moon_brightness",0.5,"moon0.brightness",0.5},
  {"moon_glow",0.4,"haloMoonBrightness",6}, {"earthshine",2,"moon0.darkSideBrightness",0.01},
  {"shooting_stars",7.5,"shootingStarsPerMinute",7.5}, {"shooting_star_brightness",2.25,"shootingStarBrightness",2.25},
}) do
  cmd("nativeloader_sky_"..field[1],tostring(field[2]))
  assert(tonumber(opt(field[3]))==field[4],field[1])
end
assert(numos("moon0.angularDiameter")=="3" and numos("moonDiscGainStops")=="-1")
assert(numos("nightSkyImage")=="False" and numos("nightSkyStars")=="True")
local glow=tonumber(opt("nightSkyBrightness"))
local count=#calls
cmd("nativeloader_sky_night_glow","2")
assert(glow>0 and math.abs(tonumber(opt("nightSkyBrightness"))-2*glow)<1e-9)
assert(#calls==count+1 and calls[#calls][1]=="rtx.atmosphere.nightSkyBrightness")
assert(numos("nightGainStops")=="7" and numos("starGainStops")=="-2" and numos("starScintillation")=="3")
cmd("nativeloader_sky_enhanced_stars","map")
assert(numos("nightSkyImage")=="True" and opt("starMapConstellationBrightness")=="4" and opt("haloMoonBrightness")=="6")
assert(not NATIVELOADER_SKY.takenOver() and convars.nativeloader_sky_follow_map:GetBool())
cmd("nativeloader_sky_night_reset")
assert(tonumber(opt("nightSkyBrightness"))==glow)
''' + f'\nreport("night_reset", {keys})')
        self.assertEqual(self.settings(out['night_start']), self.EDITOR_DEFAULTS)
        self.assertEqual(self.settings(out['night_reset']), self.EDITOR_DEFAULTS)

    def test_enhanced_solar_eclipse_places_the_library_moon_at_the_discs_contacts(self):
        for configured in ('', '0.9'):
            with self.subTest(configured=configured):
                self.enhanced_session(r'''
local function separation()
  local s, m = math.rad(tonumber(numos("sunElevation"))), math.rad(tonumber(numos("moon0.elevation")))
  local delta=math.rad(tonumber(numos("sunRotation"))-tonumber(numos("moon0.rotation")))
  return math.deg(math.acos(math.Clamp(math.sin(s)*math.sin(m)+math.cos(s)*math.cos(m)*math.cos(delta),-1,1)))
end
cmd("nativeloader_sky_time","midnight")
cmd("nativeloader_sky_moon_day","0")
cmd("nativeloader_sky_eclipse","solar")
assert(convars.nativeloader_sky_hour.value=="12.00" and numos("moon0.phase")=="0" and numos("moon0.enabled")=="True")
local sunRadius=(tonumber(DIAMETER) or 0.545)/2
for _,size in ipairs({1.6,0.5}) do
  cmd("nativeloader_sky_moon_size",tostring(size))
  local first,inner=sunRadius+size/2,math.abs(sunRadius-size/2)
  for _,c in ipairs({{0,first},{45,(first+inner)/2},{90,inner},{100,0}}) do
    cmd("nativeloader_sky_eclipse_amount",tostring(c[1]))
    assert(math.abs(separation()-c[2])<0.001,tostring(c[1]))
  end
end
cmd("nativeloader_sky_eclipse","")
assert(numos("moon0.enabled")=="False" and numos("moon0.phase")=="0.5")
''', 'CONF["rtx.atmosphere.numos.sunSize"]=DIAMETER', DIAMETER=configured)

    def test_tuned_weather_bearings_cross_zero_and_unlimited_visibility_blends_as_clear_air(self):
        # Edit only the weather data in memory. Remove the independent slow wind drift to measure the blend.
        self.enhanced_session(r'''
cmd("nativeloader_weather_seconds", "20")
cmd("nativeloader_weather", "clear") tick(10)
assert(tonumber(numos("cloudWindDirection")) == 0 and tonumber(numos("fogVisibilityMeters")) == 2000)
tick(10)
assert(tonumber(numos("cloudWindDirection")) == 10 and tonumber(numos("fogVisibilityMeters")) == 1000)
''', r'''
local readLua = dofile
function dofile(path)
  local result = readLua(path)
  if path:match("/enhanced_weather%.lua$") then
    result.presets.partlyCloudy.cloudWindDirection, result.presets.clear.cloudWindDirection = 350, 10
    result.presets.partlyCloudy.fogVisibilityMeters, result.presets.clear.fogVisibilityMeters = 0, 1000
  elseif path:match("/sky_model%.lua$") then
    result.drift = function() return 0 end
  end
  return result
end
''')

    def test_enhanced_tier_and_explicit_detail(self):
        for tier, level in [('high', 0), ('medium', 1), ('low', 2), ('unknown', 1)]:
            with self.subTest(tier=tier):
                self.enhanced_session(r'''
assert(numos("qualityLevel") == EXPECT)
for name, level in pairs({high="0", medium="1", low="2", auto=EXPECT}) do
  cmd("nativeloader_sky_enhanced_quality", name)
  assert(numos("qualityLevel") == level)
end
cmd("nativeloader_sky_enhanced_quality", "invalid") assert(numos("qualityLevel") == EXPECT)
''', 'JSON={status={schema=1,activation={performance_tier={tier=TIER}}}}', LOADER_STATUS='status',
                                      TIER=tier, EXPECT=str(level))

    def test_enhanced_never_writes_the_players_volumetrics_switch_across_vr_map_and_shutdown(self):
        for initial in ('True', 'False'):
            with self.subTest(initial=initial):
                self.enhanced_session(r'''
assert(convars.nativeloader_sky_volumetrics_saved.value == "" and volumeWrites() == 0)
cmd("nativeloader_sky_enhanced_quality", "low")
NativeLoaderVR = {state="running"} tick(0.02)
assert(value("rtx.skyMode") == "1" and volumeWrites() == 0 and numos("qualityLevel") == "2")
assert(convars.nativeloader_sky_enhanced.value == "1" and convars.nativeloader_sky_volumetrics_saved.value == "")
cmd("nativeloader_sky_enhanced_quality", "high")
NativeLoaderVR.state = "off" tick(0.02)
assert(value("rtx.skyMode") == "2" and volumeWrites() == 0 and numos("qualityLevel") == "0")
cmd("nativeloader_sky_here", "map")
assert(value("rtx.skyMode") == "0" and volumeWrites() == 0)
local n = #calls
cmd("nativeloader_sky_enhanced", "0") cmd("nativeloader_sky_enhanced", "1") tick(1)
assert(n == #calls and NATIVELOADER_SKY.mapSky().shown == "own")
cmd("nativeloader_sky_here", "rtx")
assert(value("rtx.skyMode") == "2" and volumeWrites() == 0)
cmd("nativeloader_sky_enhanced", "0") assert(volumeWrites() == 0 and value("rtx.skyMode") == "1")
cmd("nativeloader_sky_enhanced", "1") hook.Run("ShutDown")
assert(volumeWrites() == 0 and convars.nativeloader_sky_volumetrics_saved.value == "")
''', 'CONF["rtx.volumetrics.enable"]=INITIAL', INITIAL=initial)

    def test_enhanced_preference_under_fixed_sky_and_when_a_sky_owner_arrives_late(self):
        self.enhanced_session(r'''
assert(#calls == 0)
cmd("nativeloader_sky_enhanced", "0") cmd("nativeloader_sky_enhanced_quality", "low")
cmd("nativeloader_sky_enhanced", "1") tick(1)
assert(#calls == 0 and not NATIVELOADER_SKY.takenOver())
''', FIXED_SKY_ADDON=True)
        self.enhanced_session(r'''
assert(NATIVELOADER_SKY.mapSky().shown == "own" and value("rtx.skyMode") == "0")
local before = #calls
cmd("nativeloader_sky_enhanced", "0") cmd("nativeloader_sky_enhanced", "1") tick(1)
assert(#calls == before and value(volume) == nil and numos("qualityLevel") == nil)
''', r'''
SKY_FILES={["data_static/nativeloader/sky/gm_construct/fixed.json"]="decl"}
JSON={decl={version=1,sky="map",title="Construct HD"}}
''')
        self.enhanced_session(r'''
hook.Add("NativeLoaderSkyOwner", "late", function() return "Station" end)
hook.Add("NativeLoaderSkyFixed", "late", function() return true end)
RemixConfig.SetConfigVariable("rtx.skyMode", "0")
hook.Run("NativeLoaderSkySet") tick(0.02)
assert(not NATIVELOADER_SKY.enhanced() and volumeWrites() == 0 and value("rtx.skyMode") == "0")
''')

    def test_enhanced_fog_menu_uses_visibility_and_returns_to_the_weather(self):
        self.enhanced_session(r'''
assert(tonumber(numos("fogVisibilityMeters")) == looks.partlyCloudy.fogVisibilityMeters)
cmd("nativeloader_remix_fog", "heavyFog")
local linear = ((0.85 + 0.055) / 1.055) ^ 2.4
local visibility = math.log(0.02) * 5 * 1.905 / math.log(linear)
assert(math.abs(tonumber(numos("fogVisibilityMeters")) - visibility) < 0.001)
assert(numos("fogAlbedo") == "0.9" and numos("fogAnisotropy") == "-0.2" and volumeWrites() == 0)
cmd("nativeloader_weather", "clear") tick(31)
assert(math.abs(tonumber(numos("fogVisibilityMeters")) - visibility) < 0.001)
cmd("nativeloader_remix_fog", "")
assert(tonumber(numos("fogVisibilityMeters")) == looks.clear.fogVisibilityMeters)
cmd("nativeloader_weather", "") cmd("nativeloader_remix_fog", "mist")
assert(tonumber(numos("fogVisibilityMeters")) > visibility)
cmd("nativeloader_remix_fog", "") assert(numos("fogVisibilityMeters") == "0")
''', MENU=True)

    def test_enhanced_leaves_an_applied_fog_preset_enable_value_alone(self):
        self.enhanced_session(r'''
cmd("nativeloader_remix_fog", "heavyFog")
assert(value(volume) == "True" and volumeWrites() == 1)
cmd("nativeloader_sky_enhanced", "1") cmd("nativeloader_sky_enhanced_quality", "low")
assert(convars.nativeloader_sky_volumetrics_saved.value == "" and volumeWrites() == 1)
cmd("nativeloader_sky_enhanced", "0")
tick(1)
assert(volumeWrites() == 1 and convars.nativeloader_sky_volumetrics_saved.value == "")
''', 'PRESET.nativeloader_sky_enhanced="0"\nCONF["rtx.volumetrics.enable"]="False"', MENU=True)

    def test_enhanced_signals_one_new_world_per_map_and_recovers_an_unfinished_restore(self):
        self.enhanced_session(r'''
assert(numos("worldChangeCount") == "8" and convars.nativeloader_sky_volumetrics_saved.value == "")
cmd("nativeloader_sky_enhanced", "0") assert(volumeWrites() == 0)
cmd("nativeloader_sky_enhanced", "1") assert(numos("worldChangeCount") == "8")
hook.Run("ShutDown") tick(1)
assert(volumeWrites() == 0 and not NATIVELOADER_SKY.enhanced())
hook.Run("InitPostEntity")
assert(numos("worldChangeCount") == "9" and NATIVELOADER_SKY.enhanced())
''', 'PRESET.nativeloader_sky_numos_world="7"\nCONF["rtx.volumetrics.enable"]="False"')
        self.enhanced_session(r'''
assert(not NATIVELOADER_SKY.enhanced() and value(volume) == "False")
assert(convars.nativeloader_sky_volumetrics_saved.value == "" and numos("worldChangeCount") == nil)
cmd("nativeloader_sky_enhanced","1") cmd("nativeloader_sky_enhanced","0") hook.Run("ShutDown")
assert(volumeWrites() == 1)
''', 'PRESET.nativeloader_sky_enhanced="0"\nPRESET.nativeloader_sky_volumetrics_saved="False"')
        self.enhanced_session(r'''
local writer = RemixConfig.SetConfigVariable
convars.nativeloader_sky_volumetrics_saved:SetString("True")
RemixConfig.SetConfigVariable = function(k,v) if k == volume then return false end return writer(k,v) end
tick(1)
assert(convars.nativeloader_sky_volumetrics_saved.value == "True" and volumeWrites() == 0)
RemixConfig.SetConfigVariable = writer
tick(1) tick(1)
assert(convars.nativeloader_sky_volumetrics_saved.value == "" and volumeWrites() == 1 and value(volume) == "True")
''')

    def test_no_horizon_checkbox_works_in_enhanced_and_standard(self):
        out = self.run_lua(SESSION, MAP='gm_construct', BSP=self.sky_map(), SKY_DEFAULT=True, SCRIPT='horizon_panel')
        self.assertEqual(self.settings(out['start'])['rtx.atmosphere.noHorizon'], 'False')
        self.assertEqual(out['enhanced_on'], 'true false 2 True')
        self.assertEqual(out['standard_off'], 'true true 1 False')
        self.assertEqual(out['enhanced_again'], 'true false 2 True')

    def test_enhanced_panel_offers_saved_choices_and_explains_vr(self):
        lines = self.run_lines('NativeLoaderVR={state="running"}\nPRESET={nativeloader_sky_enhanced="1"}\n' + SESSION,
                               MAP='gm_construct', BSP=self.sky_map(), SCRIPT='panel')
        for row in ['ComboBox|Sky quality|nativeloader_sky_enhanced', 'choice|Standard|0', 'choice|Enhanced|1',
                    'ComboBox|Enhanced detail|nativeloader_sky_enhanced_quality', 'choice|Automatic|auto',
                    'choice|High|high', 'choice|Medium|medium', 'choice|Low|low']:
            self.assertIn('panel sky|' + row, lines)
        self.assertTrue(any('Enhanced, the default' in line for line in lines))
        self.assertTrue(any('Enhanced sky is unavailable in VR' in line for line in lines))
        self.assertIn('rtx.skyMode=1', next(line for line in lines if line.startswith('start ')))

    def test_a_new_players_game_starts_in_enhanced_and_vr_in_standard(self):
        # The user, 2026-11-26: the Enhanced sky is the default; Standard stays a choice, and VR shows Standard.
        for vr, mode in (('', '2'), ('NativeLoaderVR={state="running"}\n', '1')):
            with self.subTest(vr=bool(vr)):
                lines = self.run_lines(vr + SESSION, MAP='gm_construct', BSP=self.sky_map(), SKY_DEFAULT=True)
                self.assertIn(f'rtx.skyMode={mode}', next(line for line in lines if line.startswith('start ')))

    def test_editor_settings_blend_from_the_current_sky_and_leave_the_weather_particles_alone(self):
        self.enhanced_session(r'''
cmd("nativeloader_weather_seconds","0") cmd("nativeloader_weather","thunderstorm")
local rain = value("rtx.weather.precipitation.intensity")
local top = tonumber(numos("cloudDepthMeters"))
local light = numos("sunElevation")
cmd("nativeloader_sky_look_cloud_density","12")
assert(convars.nativeloader_sky_own_look:GetBool() and numos("cloudDensity") == "12")
assert(tonumber(numos("cloudDepthMeters")) == top)
tick(1)
assert(tonumber(numos("cloudDepthMeters")) == (top + looks.partlyCloudy.cloudDepthMeters)/2)
cmd("nativeloader_sky_look_cloud_color","0.2,0.4,0.6")
assert(numos("cloudColor") == "0.2, 0.4, 0.6")
tick(1)
assert(tonumber(numos("cloudDepthMeters")) == looks.partlyCloudy.cloudDepthMeters)
assert(value("rtx.weather.precipitation.intensity") == rain and numos("sunElevation") == light)
cmd("nativeloader_weather","snow")
assert(numos("cloudDensity") == "12" and tonumber(value("rtx.weather.precipitation.intensity")) == 0.45)
cmd("nativeloader_sky_own_look","0") tick(1)
assert(tonumber(numos("cloudDensity")) == (12 + looks.snow.cloudDensity)/2)
tick(1) assert(tonumber(numos("cloudDensity")) == looks.snow.cloudDensity)
cmd("nativeloader_weather","") cmd("nativeloader_sky_own_look","1") tick(2)
local wind = numos("cloudWindDirection") tick(5)
assert(numos("cloudDensity") == "12" and wind ~= numos("cloudWindDirection"))
cmd("nativeloader_sky_own_look","0") tick(1) assert(numos("cloudDensity") == "16")
tick(1) assert(numos("cloudDensity") == "20" and numos("weather.followGame") == "True")
''')

    def test_mode_each_tier_and_styles_including_when_weather_is_left_to_remix(self):
        self.enhanced_session(r'''
local data = include("nativeloader/enhanced_weather.lua")
cmd("nativeloader_weather","")
for _, tier in ipairs({"high","medium","low"}) do
  cmd("nativeloader_sky_enhanced_quality",tier)
  for key, setting in pairs(data.mode[tier]) do
    if key ~= "aerialPerspectiveLocalLights" then assert(numos(key)==M.optionText(setting), key) end
  end
  assert(numos("nightGainStops")=="10" and numos("aerialPerspectiveLocalLights")=="False")
end
cmd("nativeloader_sky_style_night_gain_stops","13") cmd("nativeloader_sky_style_rays_strength","0")
assert(numos("nightGainStops")=="13" and numos("rays.enable")=="False" and numos("rays.strength")=="0")
cmd("nativeloader_sky_style_rays_strength","1.5")
assert(numos("rays.enable")=="True" and numos("rays.strength")=="1.5")
for _, spec in ipairs({{"moonlight_gain_stops","moonlightGainStops",-3},{"star_gain_stops","starGainStops",4},
    {"star_scintillation","starScintillation",0},{"cloud_shadow_strength","cloudShadowStrength",0.25}}) do
  cmd("nativeloader_sky_style_"..spec[1],tostring(spec[3])) assert(tonumber(numos(spec[2]))==spec[3])
end
assert(not convars.nativeloader_sky_own_look:GetBool())
cmd("nativeloader_sky_moon_size","3") cmd("nativeloader_sky_moon_brightness","0.5")
assert(numos("moon0.angularDiameter")=="3" and numos("moonDiscGainStops")=="-1")
cmd("nativeloader_sky_moon_brightness","0") assert(numos("moonDiscGainStops")=="-16")
cmd("nativeloader_weather","clear") tick(31) assert(numos("nightGainStops")=="13")
cmd("nativeloader_sky_enhanced","0")
local writes = #calls
cmd("nativeloader_sky_style_star_gain_stops","2") cmd("nativeloader_sky_look_cloud_density","5")
assert(#calls==writes and volumeWrites()==0)
''')

    def test_lamp_glow_is_a_saved_style_that_overrides_every_tier_and_preserves_its_limits(self):
        # Exercise both directions of the override, even if every shipped tier starts with lamps off.
        self.enhanced_session(r'''
local data = include("nativeloader/enhanced_weather.lua")
local lamp = "nativeloader_sky_style_aerial_perspective_local_lights"
assert(convars[lamp].archived and convars[lamp].default=="0")
cmd("nativeloader_weather","")
for _, enabled in ipairs({"0","1","0"}) do
  cmd(lamp,enabled)
  for _, tier in ipairs({"low","medium","high"}) do
    cmd("nativeloader_sky_enhanced_quality",tier)
    assert(numos("aerialPerspectiveLocalLights") == (enabled=="1" and "True" or "False"))
    for key,v in pairs(data.mode[tier]) do
      if key~="aerialPerspectiveLocalLights" then assert(numos(key)==M.optionText(v),key) end
    end
  end
end
assert(not convars.nativeloader_sky_own_look:GetBool() and volumeWrites()==0)
cmd("nativeloader_sky_enhanced","0")
local writes = #calls
cmd(lamp,"1") assert(#calls==writes)
cmd("nativeloader_sky_enhanced","1") assert(numos("aerialPerspectiveLocalLights")=="True")
''', r'''
local readLua = dofile
function dofile(path)
  local data = readLua(path)
  if path:match("/enhanced_weather%.lua$") then data.mode.high.aerialPerspectiveLocalLights = true end
  return data
end
''')

    def test_near_mist_matches_numos_contrast_and_honours_an_explicit_remix_fog(self):
        self.enhanced_session(r'''
local p="rtx.volumetrics."
cmd("nativeloader_sky_style_volumetrics","1")
cmd("nativeloader_sky_look_fog_visibility_meters","850") tick(2)
cmd("nativeloader_sky_look_fog_albedo","0.67") cmd("nativeloader_sky_look_fog_anisotropy","-0.25")
assert(numos("volumetrics")=="1" and value(p.."singleScatteringAlbedo")=="0.67, 0.67, 0.67")
assert(value(p.."anisotropy")=="-0.25" and value(p.."enableFogRemap")=="False")
local srgb=tonumber(value(p.."transmittanceColor"):match("^[^,]+"))
local linear=((srgb+0.055)/1.055)^2.4
local distance=tonumber(value(p.."transmittanceMeasurementDistanceMeters"))
assert(math.abs(math.log(0.02)*distance*1.905*2/math.log(linear)-850)<0.01)
cmd("nativeloader_sky_look_fog_visibility_meters","0")
assert(value(p.."transmittanceColor")=="1, 1, 1")
cmd("nativeloader_remix_fog","heavyFog")
assert(value(p.."transmittanceMeasurementDistanceMeters")=="5")
cmd("nativeloader_sky_look_fog_visibility_meters","1200") tick(2)
assert(value(p.."transmittanceMeasurementDistanceMeters")=="5" and numos("fogVisibilityMeters")~="1200")
cmd("nativeloader_remix_fog","") assert(numos("fogVisibilityMeters")=="1200")
assert(math.abs(tonumber(value(p.."transmittanceMeasurementDistanceMeters"))-1200/(1.905*2))<0.001)
cmd("nativeloader_sky_style_volumetrics","0")
assert(value(p.."transmittanceMeasurementDistanceMeters")=="777" and volumeWrites()==0)
''', 'CONF["rtx.sceneScale"]="2"\nCONF["rtx.volumetrics.transmittanceMeasurementDistanceMeters"]="777"', MENU=True)

    def test_mist_scales_the_weather_and_personal_look_without_changing_their_values(self):
        self.enhanced_session(r'''
local strength = "nativeloader_sky_style_mist_strength"
assert(convars[strength].archived and convars[strength].default=="1")
assert(numos("aerosolDensity")=="2" and numos("mieAbsorption")=="0.0044, 0.0044, 0.0044")
assert(numos("fogVisibilityMeters")=="20000")
for _, case in ipairs({{"0","1.1","0"},{"1","2","20000"},{"2","2.9","10000"}}) do
  cmd(strength,case[1]) tick(1) tick(1)
  assert(numos("aerosolDensity")==case[2] and numos("fogVisibilityMeters")==case[3])
  assert(numos("aerialPerspective")==(case[1]=="0" and "False" or "True"))
end
assert(not convars.nativeloader_sky_own_look:GetBool())
cmd("nativeloader_sky_look_aerosol_density","7.1")
cmd("nativeloader_sky_look_fog_visibility_meters","6400") tick(2)
for _, case in ipairs({{"2","13.1","3200"},{"0","1.1","0"},{"1","7.1","6400"}}) do
  cmd(strength,case[1]) tick(1)
  assert(numos("aerosolDensity")==case[2] and numos("fogVisibilityMeters")==case[3])
  assert(convars.nativeloader_sky_look_aerosol_density.value=="7.1")
  assert(convars.nativeloader_sky_look_fog_visibility_meters.value=="6400")
end
cmd("nativeloader_sky_look_aerosol_density","0.5") cmd("nativeloader_sky_look_fog_visibility_meters","0")
for _, s in ipairs({"0","1","2"}) do
  cmd(strength,s)
  assert(numos("aerosolDensity")=="0.5" and numos("fogVisibilityMeters")=="0")
end
assert(numos("mistStrength")==nil and volumeWrites()==0)
''')

    def test_mist_scales_each_step_after_blending_across_the_clean_air_density(self):
        self.enhanced_session(r'''
local strength = "nativeloader_sky_style_mist_strength"
cmd("nativeloader_weather_seconds","0") cmd("nativeloader_weather","clear")
cmd("nativeloader_weather_seconds","20") cmd("nativeloader_weather","hazy") tick(10)
local a, b = looks.clear, looks.hazy
local density = (a.aerosolDensity+b.aerosolDensity)/2
local visibility = 1/(0.5/a.fogVisibilityMeters+0.5/b.fogVisibilityMeters)
for _, s in ipairs({0,1,2,0.5}) do
  cmd(strength,tostring(s))
  assert(math.abs(tonumber(numos("aerosolDensity"))-(1.1+(density-1.1)*s))<0.0001)
  local expected = s>0 and visibility/s or 0
  assert(math.abs(tonumber(numos("fogVisibilityMeters"))-expected)<0.1)
end
cmd(strength,"1") tick(10)
assert(tonumber(numos("aerosolDensity"))==b.aerosolDensity and tonumber(numos("fogVisibilityMeters"))==b.fogVisibilityMeters)
''')

    def test_map_mist_saved_choices_off_and_zero_select_the_right_runtime_policy(self):
        for choice in ('0', '1', '2'):
            with self.subTest(saved_choice=choice):
                self.enhanced_session(r'''
local strength, mode = "nativeloader_sky_style_mist_strength", "nativeloader_sky_style_volumetrics"
local distance = "rtx.volumetrics.transmittanceMeasurementDistanceMeters"
assert(convars[mode].value==CHOICE)
assert(numos("volumetrics")==(CHOICE=="1" and "1" or "0"))
assert(numos("aerialPerspective")==(CHOICE=="2" and "False" or "True"))
cmd(mode,"1") cmd(strength,"2")
local expected = (looks.partlyCloudy.fogVisibilityMeters/2)/1.905
assert(math.abs(tonumber(value(distance))-expected)<0.01)
local skyHaze, skyVisibility = numos("aerosolDensity"), numos("fogVisibilityMeters")
cmd(mode,"2")
assert(numos("volumetrics")=="0" and numos("aerialPerspective")=="False" and value(distance)=="777")
assert(numos("aerosolDensity")==skyHaze and numos("fogVisibilityMeters")==skyVisibility)
local before = #calls
cmd("nativeloader_sky_style_rays_strength","1.5")
for i=before+1,#calls do assert(calls[i][1]~="rtx.atmosphere.numos.aerialPerspective") end
cmd(mode,"1") cmd(strength,"0")
assert(numos("volumetrics")=="0" and numos("aerialPerspective")=="False" and value(distance)=="777")
assert(convars[mode].value=="1")
cmd(strength,"2")
assert(numos("volumetrics")=="1" and numos("aerialPerspective")=="True")
assert(math.abs(tonumber(value(distance))-expected)<0.01)
cmd(mode,"0") assert(numos("volumetrics")=="0" and numos("aerialPerspective")=="True")
cmd("nativeloader_weather","") cmd(strength,"0")
assert(numos("aerialPerspective")=="False" and numos("volumetrics")=="0")
for _, c in ipairs(calls) do assert(c[1]~="rtx.atmosphere.numos.volumetrics" or c[2]~="2") end
assert(volumeWrites()==0)
''', 'PRESET.nativeloader_sky_style_volumetrics=CHOICE\nCONF["rtx.volumetrics.transmittanceMeasurementDistanceMeters"]="777"',
                                      CHOICE=choice)

    def test_explicit_fog_preset_preserves_its_strength_until_cleared(self):
        self.enhanced_session(r'''
local strength, mode = "nativeloader_sky_style_mist_strength", "nativeloader_sky_style_volumetrics"
cmd(mode,"1") cmd("nativeloader_remix_fog","heavyFog")
local distance = numos("fogVisibilityMeters")
for _, s in ipairs({"0","1","2"}) do
  cmd(strength,s) tick(1)
  assert(numos("fogVisibilityMeters")==distance and numos("fogAlbedo")=="0.9" and numos("fogAnisotropy")=="-0.2")
  assert(value("rtx.volumetrics.transmittanceMeasurementDistanceMeters")=="5")
  assert(value("rtx.volumetrics.transmittanceColor")=="0.85, 0.85, 0.85")
end
cmd(mode,"2") assert(numos("aerialPerspective")=="False" and numos("fogVisibilityMeters")==distance)
cmd(mode,"1") cmd("nativeloader_remix_fog","")
assert(tonumber(numos("fogVisibilityMeters"))==looks.partlyCloudy.fogVisibilityMeters/2)
assert(volumeWrites()==0)
''', MENU=True)

    def test_sky_page_and_editor_share_one_mist_setting(self):
        self.enhanced_session(Path(__file__).with_name('enhanced_editor_harness.lua').read_text(encoding='utf-8'),
                              MIST_PAGES=True)

    def test_rainbow_tracks_only_rain_and_drains_for_five_minutes_in_any_look(self):
        self.enhanced_session(r'''
cmd("nativeloader_weather_seconds","0")
local levels=NATIVELOADER_SKY.presets.presets
for _, name in ipairs({"drizzle","rainstorm","thunderstorm"}) do
  cmd("nativeloader_weather",name)
  assert(tonumber(numos("rainbow.strength"))==levels[name].precipitationIntensity)
end
cmd("nativeloader_sky_style_rainbow_strength","1.6")
cmd("nativeloader_sky_own_look","1") cmd("nativeloader_weather","snow")
tick(150) assert(math.abs(tonumber(numos("rainbow.strength"))-0.8)<0.0001)
cmd("nativeloader_weather","sandstorm") tick(150) assert(numos("rainbow.strength")=="0")
cmd("nativeloader_weather","rainstorm") cmd("nativeloader_weather","") tick(300)
assert(numos("rainbow.strength")=="0")
''')

    def test_editor_page_loads_saves_shares_and_refuses_a_whole_invalid_look(self):
        self.enhanced_session(Path(__file__).with_name('enhanced_editor_harness.lua').read_text(encoding='utf-8'), MENU=True)

    def test_editor_page_offers_the_switch_in_standard_and_tracks_vr(self):
        self.enhanced_session(Path(__file__).with_name('enhanced_editor_harness.lua').read_text(encoding='utf-8'),
                              'PRESET.nativeloader_sky_enhanced="0"', PAGE_STANDARD=True)

    def test_new_and_migrated_defaults_move_the_clock_without_taking_over_a_maps_sky(self):
        for preset, marker in [('', 'kept player settings'),
                               ('PRESET = {nativeloader_sky_time_passes="0", nativeloader_sky_day_minutes="30"}\n',
                                'migrated 0/30 to 1/20')]:
            for map_name in ('gm_construct', 'modern_house'):
                with self.subTest(migrated=bool(preset), map=map_name):
                    owner = 'MHRTX_Config = {}\n' if map_name == 'modern_house' else ''
                    out = self.run_lua(owner + preset + SESSION, MAP=map_name, BSP=bsp(CONSTRUCT),
                                       SCRIPT='defaults', RUNNING_DEFAULTS=True)
                    self.assertEqual(out['defaults'], '1 20')
                    self.assertEqual(out['marker'], marker)
                    if map_name == 'modern_house':
                        self.assertEqual(out['start'].split()[0], '0')
                        self.assertEqual(out['afterminute'].split()[0], '0')
                        self.assertEqual(float(out['elapsed']), 0)
                    else:
                        self.assertAlmostEqual(float(out['elapsed']), 1.2, delta=0.001)

    def test_the_sun_moon_and_stars(self):
        out = self.run_lua(MODEL)
        # Latitude 40: the equinox's noon sun 50 degrees high in the south, summer's 73.4, winter's 26.6;
        # summer days run 04:30-19:30, winter ones 07:20-16:40 (sunrise and sunset at -0.83 degrees).
        for season, (elevation, rise, sets) in {'spring': (50.0, 5.93, 18.07), 'summer': (73.44, 4.50, 19.50),
                                                'winter': (26.58, 7.33, 16.67)}.items():
            noon = self.numbers(out['noon_' + season])
            self.assertAlmostEqual(noon[0], elevation, delta=0.2)
            self.assertAlmostEqual(noon[1], 180.0, delta=0.01)
            self.assertAlmostEqual(noon[2], rise, delta=0.05)
            self.assertAlmostEqual(noon[3], sets, delta=0.05)
        # gm_construct's light_environment (pitch -56, yaw 306): the sun 56 degrees high at bearing 324.
        self.assertEqual(self.numbers(out['mapsun']), [56.0, 324.0])
        self.assertEqual(out['mapsun_up'], 'nil nil')
        # Following the map puts the sun exactly where the map's is, in the afternoon; a sun higher
        # than summer's noon sun (85) gives noon, in the map sun's direction.
        for i, (elevation, bearing) in enumerate([(56, 324), (20, 10), (73, 200), (85, 90), (5, 270)], 1):
            hours, at_elevation, at_bearing = self.numbers(out[f'follow{i}'])
            self.assertGreaterEqual(hours, 12.0)
            self.assertAlmostEqual(at_bearing, bearing, delta=0.01)
            self.assertAlmostEqual(at_elevation, min(elevation, 73.44), delta=0.05)
        # At 20:00 in spring the sun has set; the full moon has risen opposite it, the new moon set with it.
        new, quarter, full = (self.numbers(out[f'moon{p}']) for p in ('0', '0.25', '0.5'))
        self.assertLess(full[2], 0)
        self.assertGreater(full[0], 0)
        self.assertAlmostEqual((full[1] - full[3]) % 360, 180, delta=15)
        self.assertLess(new[0], 0)
        self.assertGreater(quarter[0], new[0])
        # The stars turn 15 degrees an hour, the field the other way round; the pole stands at the
        # latitude in the north.
        a, b, pole, pole_bearing = self.numbers(out['stars'])
        self.assertAlmostEqual((a - b) % 360, 15.0, delta=0.01)
        self.assertEqual((pole, pole_bearing), (40.0, 30.0))
        self.assertEqual(self.numbers(out['entities']), [2.0, 56.0, 324.0])
        self.assertEqual(self.numbers(out['env_sun']), [40.0, 180.0])
        self.assertEqual(out['none'], 'nil')
        self.assertEqual(out['names'], 'night nil dusk')
        angle, extinction, scalar, colour = self.numbers(out['blend'])
        self.assertAlmostEqual(angle, 0.0, delta=1e-6)
        self.assertAlmostEqual(extinction, 1 / (0.5 * (1 / 100 + 1 / 1000)), delta=1e-3)
        self.assertEqual((scalar, colour), (1.5, 1.0))
        self.assertEqual(out['step'], 'false true')
        self.assertEqual(out['text'], 'True|0.5, 1, 0.25|2|0.00330001')
        self.assertEqual(out['clock'], '00:00 14:00 23:00 7.0833333333333 nil nil')
        d0, d150, d6 = self.numbers(out['drift'])
        self.assertTrue(-1 <= d0 <= 1 and -1 <= d150 <= 1 and d0 != d150 and d0 != d6)
        # Eclipse stages for a moon 0.8 degrees across its radius: lunar, the penumbra touched at 0, the
        # umbra at 0.3, the moon wholly inside it at 0.7, centred at 1; solar, the sun touched at 0 and
        # covered from 0.9. Without an eclipse the moon passes clear of the penumbra.
        self.assertEqual(self.numbers(out['lunar']), [4.64, 2.92, 2.12, 1.32, 0.0])
        s0, s45, s90, s100, clear = self.numbers(out['solar'])
        self.assertEqual((s0, s90, s100, clear), (1.576, 0.024, 0.0, 5.64))
        self.assertAlmostEqual(s45, (1.576 + 0.024) / 2, delta=1e-4)
        self.assertEqual(out['phases'], '0.5 0 nil 0.15 0.85')
        # The moon's ecliptic latitude is its distance from the shadow's centre (or the sun's).
        for i, expected in enumerate([2.12, 5.64, 0.71], 1):
            self.assertAlmostEqual(self.numbers(out[f'offset{i}'])[0], expected, delta=0.01)

    def test_a_poster_holds_the_clock_and_the_weather(self):
        # GitHub issue 3 (ADR 0226): while the runtime renders a poster, the sky sends nothing and its clock waits;
        # afterwards it goes on from where it stood, without the poster's minute.
        out = self.run_lua('POSTER_SIM = true\n' + SESSION, MAP='gm_construct', BSP=bsp(CONSTRUCT), SCRIPT='poster')
        held, sent = out['held'].split()
        self.assertEqual(float(held), 0.0)
        self.assertEqual(sent, '0')
        ran, resumed = self.numbers(out['ran'])
        self.assertGreater(ran, 0.019)  # the clock ran before the poster
        self.assertAlmostEqual(resumed, 24 / (20 * 60), places=6)  # a second of a 20-minute day, not the minute

    def test_a_map_start_turns_on_the_physical_sky_at_the_maps_sun(self):
        out = self.run_lua(SESSION, MAP='gm_construct', BSP=bsp(CONSTRUCT), SCRIPT='weather')
        start = self.settings(out['start'])
        self.assertEqual((start['rtx.skyMode'], start['rtx.ignoreGameDirectionalLights']), ('1', 'True'))
        self.assertEqual((start['rtx.atmosphere.timeCycleEnable'], start['rtx.atmosphere.moon0.enabled']), ('False', 'True'))
        self.assertAlmostEqual(float(start['rtx.atmosphere.sunElevation']), 56.0, delta=0.01)
        self.assertAlmostEqual(float(start['rtx.atmosphere.sunRotation']), 324.0, delta=0.01)
        self.assertEqual(start['rtx.atmosphere.starAxisElevation'], '40.000')
        # The default weather, partly cloudy, at once: its cloud density, its fog, no rain.
        self.assertEqual(start['rtx.atmosphere.cloudDensity'], '6')
        # Its fog from a visibility of 8.8 km at GMod's scale (a Remix metre is 1.905 real ones): the
        # distance over which the preset's transmittance colour (0.998, sRGB, which the runtime
        # uses linear) is measured.
        linear = ((0.998 + 0.055) / 1.055) ** 2.4
        self.assertAlmostEqual(float(start['rtx.volumetrics.transmittanceMeasurementDistanceMeters']),
                               -math.log(linear) * (8800 / 1.905) / 3, delta=1e-3)
        self.assertEqual(start['rtx.weather.precipitation.intensity'], '0')
        self.assertEqual(start['rtx.atmosphere.surfaceMoonBrightness'], '0.0')  # no moonlight by day
        hour, direction, follow = out['convars'].split()
        self.assertAlmostEqual(float(hour), 14.35, delta=0.01)  # 14:21, the panel shows the map's time
        self.assertEqual(follow, '1')
        # A change of weather blends over nativeloader_weather_seconds (30): halfway there at 15 s.
        mid, end = self.settings(out['mid']), self.settings(out['end'])
        self.assertTrue(6 < float(mid['rtx.atmosphere.cloudDensity']) < 7)
        self.assertTrue(0 < float(mid['rtx.weather.precipitation.intensity']) < 0.8)
        self.assertEqual((end['rtx.atmosphere.cloudDensity'], end['rtx.weather.precipitation.intensity'],
                          end['rtx.atmosphere.lightningStrikesPerMinute']), ('7', '0.8', '4'))
        # Choosing a time takes the sun off the map's: the direction stays the map's.
        hour = self.settings(out['hour'])
        follow, hours, direction_after, direction_before = out['after'].split()
        self.assertEqual((follow, hours, direction_after), ('0', '18.00', direction_before))
        elevation, bearing = self.numbers(out['expect'])
        self.assertAlmostEqual(float(hour['rtx.atmosphere.sunElevation']), elevation, delta=0.002)
        self.assertAlmostEqual(float(hour['rtx.atmosphere.sunRotation']), bearing, delta=0.002)
        # 60 s of a 24-minute day: an hour; stopping the clock keeps the time it got to.
        self.assertAlmostEqual(float(out['clock']), 19.0, delta=0.02)
        # Weather left to Remix: nothing more is sent for it (what it set went back at once, below).
        self.assertEqual(out['left'], '0')
        self.assertTrue(out['[nativeloader]'].startswith('sky: physical; Remix API ready'), out['[nativeloader]'])

    def test_weather_left_to_remix_puts_back_remixs_own_values(self):
        # R3-009: clearing the weather after Rain gave the options back their rtx.conf value, or what
        # Remix has without one (the package's layer, else the runtime's default); not the rain's.
        out = self.run_lua('CONF = { ["rtx.atmosphere.cloudDensity"] = "1.7" }\n' + SESSION, MAP='gm_construct',
                           BSP=bsp(CONSTRUCT), SCRIPT='release')
        rain, released = self.settings(out['rain']), self.settings(out['released'])
        self.assertEqual((rain['rtx.atmosphere.cloudDensity'], rain['rtx.weather.precipitation.intensity'],
                          rain['rtx.weather.precipitation.spawnRadiusMeters']), ('7', '0.8', '8'))
        radius, lightning, intensity = out['defaults'].split()
        self.assertEqual(released['rtx.atmosphere.cloudDensity'], '1.7')  # rtx.conf's
        self.assertEqual((released['rtx.weather.precipitation.intensity'], released['rtx.weather.precipitation.spawnRadiusMeters'],
                          released['rtx.atmosphere.lightningStrikesPerMinute']), (intensity, radius, lightning))
        self.assertEqual((intensity, lightning), ('0', '0'))
        self.assertEqual(out['quiet'], '0')

    def test_a_maps_own_sky_add_on_keeps_its_sky_until_the_player_changes_it(self):
        out = self.run_lua('MHRTX_Config = {}\n' + SESSION, MAP='modern_house', BSP=bsp(CONSTRUCT), SCRIPT='ownership')
        self.assertEqual(out['start'].split()[0], '0')
        self.assertEqual(out['owned'].split()[0], '0')
        # R3-015: 50 updates a second by default; changing how often does not take the map's sky over.
        self.assertEqual(out['interval'], '0.02')
        self.assertEqual((out['adjusted'].split()[0], out['interval_now']), ('0', '0.1'))
        taken = self.settings(out['taken'])
        self.assertEqual((taken['rtx.skyMode'], taken['rtx.atmosphere.cloudDensity']), ('1', '7'))  # overcast's (R18)

    def test_a_sky_taken_over_comes_back_at_once_when_the_maps_add_on_sets_its_own_again(self):
        # R5: Modern House RTX puts its afternoon sun back three times in the first minute; the
        # player's night used to wait up to 10 s for the companion's timer.
        add_on = ('MHRTX_Config = {}\nMHRTX = { ApplySettings = function()\n'
                  '  RemixConfig.SetConfigVariable("rtx.atmosphere.sunElevation", "35")\n'
                  '  RemixConfig.SetConfigVariable("rtx.atmosphere.cloudDensity", "4")\nend }\n')
        out = self.run_lua(add_on + SESSION, MAP='modern_house', BSP=bsp(CONSTRUCT), SCRIPT='follow')
        self.assertEqual(out['followed'], 'true')
        self.assertEqual(self.settings(out['theirs'])['rtx.atmosphere.sunElevation'], '35')
        mine = float(self.settings(out['mine'])['rtx.atmosphere.sunElevation'])
        self.assertLess(mine, -10)
        again = self.settings(out['again'])
        self.assertEqual(float(again['rtx.atmosphere.sunElevation']), mine)
        self.assertNotEqual(again['rtx.atmosphere.cloudDensity'], '4')
        self.assertEqual(float(self.settings(out['reloaded'])['rtx.atmosphere.sunElevation']), mine)

    def test_the_players_own_time_and_weather_apply_from_the_start_on_a_map_whose_add_on_sets_the_sky(self):
        # R16 (the user's item 44): with Follow the map's sun unticked, the player's sky is in charge from
        # the map's start; Modern House RTX, which loads later and sets its afternoon from its own timer,
        # is followed from its first sky on, and the player's sky comes back in the same call.
        preset = ('PRESET = { nativeloader_sky_follow_map = "0", nativeloader_sky_hour = "9.80", '
                  'nativeloader_weather = "clear" }\n')
        out = self.run_lua(preset + SESSION, MAP='modern_house', BSP=bsp(CONSTRUCT), SCRIPT='entry')
        entered = self.settings(out['entered'])
        self.assertEqual(entered['rtx.skyMode'], '1')
        mine = float(entered['rtx.atmosphere.sunElevation'])
        self.assertGreater(mine, 50)
        self.assertEqual(out['followed'], 'true')
        after = self.settings(out['after'])
        self.assertAlmostEqual(float(after['rtx.atmosphere.sunElevation']), mine, delta=0.5)
        self.assertEqual(after['rtx.atmosphere.cloudDensity'], entered['rtx.atmosphere.cloudDensity'])
        self.assertAlmostEqual(float(self.settings(out['later'])['rtx.atmosphere.sunElevation']), mine, delta=0.5)

    def test_following_the_map_keeps_a_map_add_ons_sky_from_the_start(self):
        # The same map with Follow the map's sun ticked (the default): the add-on keeps its sky.
        preset = 'PRESET = { nativeloader_sky_follow_map = "1" }\nMHRTX_Config = {}\n'
        out = self.run_lua(preset + SESSION, MAP='modern_house', BSP=bsp(CONSTRUCT), SCRIPT='ownership')
        self.assertEqual(out['start'].split()[0], '0')
        self.assertEqual(out['owned'].split()[0], '0')

    def test_a_fixed_sky_stays_under_the_players_own_sky_until_a_setting_changes(self):
        # ADR 0248 (the user's answer of 2026-11-20, "Yes, keep orbit sky"): an add-on whose sky belongs to the
        # place (gm_stelliferous's orbit skybox) keeps it also with Follow the map's sun unticked; a sky or
        # weather setting changed in the session still takes it over, and the add-on can tell.
        for follow in ('0', '1'):
            preset = (f'PRESET = {{ nativeloader_sky_follow_map = "{follow}", nativeloader_sky_hour = "9.80", '
                      'nativeloader_weather = "clear" }\nFIXED_SKY_ADDON = true\n')
            out = self.run_lua(preset + SESSION, MAP='gm_stelliferous', BSP=bsp(CONSTRUCT), SCRIPT='fixed')
            self.assertEqual(out['start'].split()[0], '0', follow)
            self.assertEqual(out['taken_start'], 'false', follow)
            self.assertEqual(out['owned'].split()[0], '0', follow)
            self.assertIn('set by Station RTX, fixed;', out['[nativeloader]'] + ';', follow)
            self.assertIn('Station RTX keeps a sky of its own', out['panel'], follow)
            taken = self.settings(out['taken'])
            self.assertEqual((taken['rtx.skyMode'], taken['rtx.atmosphere.cloudDensity']), ('1', '7'), follow)
            self.assertEqual(out['taken_after'], 'true', follow)

    # ---------------------------------------------------------------- ADR 0249: which sky a map shows

    @staticmethod
    def sky_map(skyname='painted', camera=None, faces=True):
        """A map's BSP: its sky name, a sky_camera at `camera`'s scale (None: no 3D skybox), sky faces or none."""
        entities = (f'{{\n"skyname" "{skyname}"\n"classname" "worldspawn"\n}}\n'
                    '{\n"pitch" "-56"\n"angles" "0 306 0"\n"classname" "light_environment"\n}\n')
        if camera is not None:
            entities += f'{{\n"origin" "0 0 10000"\n"scale" "{camera}"\n"classname" "sky_camera"\n}}\n'
        return bsp(entities, [0, 0x4, 0x200] if faces else [0, 0x200])

    def map_sky(self, steps='', camera=16, faces=True, preset='', map_name='gm_construct', skyname='painted', **globals_):
        code = preset + (f'STEPS = {{ {steps} }}\n' if steps else '')
        return self.run_lua(code + SESSION, MAP=map_name, BSP=self.sky_map(skyname, camera, faces), SCRIPT='mapsky', **globals_)

    @staticmethod
    def engine(line):
        return dict(part.split('=', 1) for part in line.split()[0:] if '=' in part)

    def test_every_map_shows_the_rtx_sky_by_default_and_the_chat_line_says_how_to_switch(self):
        # The user's request of 2026-11-20: the RTX sky replaces a map's own by default; one chat line at the map's
        # start says which sky shows and how to switch, and says when the map has no sky of its own.
        cases = [
            (dict(camera=16), 'It also has a sky of its own, with a 3D skybox: type nativeloader_sky_here map'),
            (dict(camera=None), 'It also has a sky of its own: type nativeloader_sky_here map'),
            (dict(camera=16, preset='FACES = false\n'), 'It has no sky of its own to switch to.'),
        ]
        for kwargs, advice in cases:
            with self.subTest(**{k: str(v) for k, v in kwargs.items()}):
                out = self.map_sky(**kwargs)
                self.assertEqual(self.settings(out['sky0'])['rtx.skyMode'], '1')
                engine = self.engine(out['engine0'])
                self.assertEqual((engine['r_3dsky'], engine['r_novis'], engine['saved'], engine['here']),
                                 ('0', '1', '', 'auto'))
                self.assertEqual(out['enginelog'], '')
                self.assertTrue(out['chat'].startswith('[RTX] This map shows the RTX sky. '), out['chat'])
                self.assertIn(advice, out['chat'])
                self.assertEqual(out['api0'].split()[:3], ['rtx', 'rtx', 'default'])
        # A map without sky faces (indoors) says so and nothing else.
        out = self.map_sky(faces=False)
        self.assertEqual(out['chat'], '[RTX] This map has no open sky.')
        # The line can be turned off; the console still has it.
        out = self.map_sky(preset='PRESET = { nativeloader_sky_message = "0" }\n')
        self.assertNotIn('chat', out)
        self.assertIn('This map shows the RTX sky.', out['status_message'])

    def test_the_chat_line_is_off_by_default_and_a_saved_old_default_goes_off_once(self):
        # ADR 0253, the user's request of 2026-11-21 ("Make this notice hidden by default"): a new player's game says
        # nothing in chat; the console and the panel still say which sky shows.
        out = self.map_sky(LINE_DEFAULT=True)
        self.assertNotIn('chat', out)
        self.assertIn('This map shows the RTX sky.', out['status_message'])
        self.assertEqual(out['message'], '0 the chat line was off')
        # A game that saved the earlier default (on) in client.vdf: off once, the marker written ...
        out = self.map_sky(preset='PRESET = { nativeloader_sky_message = "1" }\n', LINE_MIGRATION=True)
        self.assertNotIn('chat', out)
        self.assertEqual(out['message'], '0 turned the chat line off')
        # ... and once the marker is there, a player who ticks "Say which sky shows" again keeps the line.
        out = self.map_sky(preset='PRESET = { nativeloader_sky_message = "1" }\n')
        self.assertEqual(out['message'], '1 done')
        self.assertTrue(out['chat'].startswith('[RTX] This map shows the RTX sky. '), out['chat'])

    def test_this_maps_own_sky_shows_its_3d_skybox_through_the_pas_and_is_remembered(self):
        out = self.map_sky('{ "nativeloader_sky_here", "map" }, { "nativeloader_sky_here", "rtx" }, '
                           '{ "nativeloader_sky_here", "auto" }',
                           preset='CONF = { ["rtx.ignoreGameDirectionalLights"] = "False" }\n')
        own = self.settings(out['sky1'])
        self.assertEqual((own['rtx.skyMode'], own['rtx.ignoreGameDirectionalLights']), ('0', 'False'))
        engine = self.engine(out['engine1'])
        self.assertEqual((engine['r_3dsky'], engine['r_novis'], engine['forcenovis'], engine['vis_pas'], engine['warn']),
                         ('1', '0', '0', '1', '1'))
        self.assertEqual(engine['saved'], 'r_3dsky=0;r_novis=1;rtx_patch_forcenovis=1;rtx_patch_vis_pas=0')
        # The RTX fixes' question before r_3dsky 1 is held back for this change only.
        log = out['enginelog'].split(',')
        self.assertIn('r_3dsky=1(warn 0)', log)
        self.assertEqual(log[log.index('r_3dsky=1(warn 0)') - 1], 'rtx_show_3dsky_warning=0')
        self.assertEqual(log[log.index('r_3dsky=1(warn 0)') + 1], 'rtx_show_3dsky_warning=1')
        self.assertEqual(out['api1'].split()[:4], ['own', 'map', 'choice', 'true'])
        # Back to the RTX sky: the engine's settings as they were, the choice saved; auto forgets it.
        self.assertEqual(self.settings(out['sky2'])['rtx.skyMode'], '1')
        engine = self.engine(out['engine2'])
        self.assertEqual((engine['r_3dsky'], engine['r_novis'], engine['forcenovis'], engine['vis_pas'], engine['saved']),
                         ('0', '1', '1', '0', ''))
        self.assertEqual(out['choices'], '')
        # The choice is there at the next start, from the map's first frame (R16).
        out = self.map_sky(preset='SAVED_CHOICES = "gm_flatgrass rtx\\ngm_construct map\\n"\n')
        self.assertEqual(self.settings(out['start'])['rtx.skyMode'], '0')
        engine = self.engine(out['engine0'])
        self.assertEqual((engine['r_3dsky'], engine['r_novis'], engine['here']), ('1', '0', 'map'))
        self.assertEqual(out['chat'], '[RTX] This map shows its own sky and its 3D skybox, as you chose for it. For the RTX sky: '
                                      'type nativeloader_sky_here rtx in the console, or use RTX Remix > Sky and weather in the '
                                      'spawn menu.')
        # Another map's choice stays in the file when this one changes.
        out = self.map_sky('{ "nativeloader_sky_here", "rtx" }', preset='SAVED_CHOICES = "gm_flatgrass rtx\\ngm_construct map\\n"\n')
        self.assertEqual(out['choices'], 'gm_construct rtx;gm_flatgrass rtx;')

    def test_a_map_with_a_2d_sky_only_or_a_skybox_at_another_scale_shows_its_own_sky_without_the_3d_pass(self):
        for camera, limit in ((None, None), (64, 'Its 3D skybox (scale 64) cannot be shown under RTX yet.')):
            with self.subTest(camera=camera):
                out = self.map_sky('{ "nativeloader_sky_here", "map" }', camera=camera)
                self.assertEqual(self.settings(out['sky1'])['rtx.skyMode'], '0')
                engine = self.engine(out['engine1'])
                self.assertEqual((engine['r_3dsky'], engine['r_novis'], engine['saved']), ('0', '1', ''))
                self.assertEqual(out['enginelog'], '')
                self.assertEqual(out['api1'].split()[:4], ['own', 'map', 'choice', 'false'])
                if limit:
                    self.assertIn(limit, out['status_message'])
                else:
                    self.assertNotIn('3D skybox', out['status_message'])

    def test_choosing_the_maps_own_sky_on_a_map_without_one_keeps_the_rtx_sky_and_says_so(self):
        out = self.map_sky('{ "nativeloader_sky_here", "map" }', preset='FACES = false\n')
        self.assertEqual(self.settings(out['sky1'])['rtx.skyMode'], '1')
        self.assertEqual(out['api1'].split()[:3], ['rtx', 'rtx', 'missing'])
        self.assertIn('It has no sky of its own to switch to.', out['status_message'])
        # An unknown choice is refused and nothing is saved.
        out = self.map_sky('{ "nativeloader_sky_here", "../x" }')
        self.assertEqual(self.engine(out['engine1'])['here'], 'auto')
        self.assertEqual(out['choices'], '')

    def test_a_sky_or_weather_change_shows_the_rtx_sky_until_the_next_map(self):
        # The user's answer of 2026-11-20 ("Yes, keep ADR 0248") for every sky that is not the RTX sky.
        out = self.map_sky('{ "nativeloader_weather", "overcast" }, { "tick", 31 }',
                           preset='SAVED_CHOICES = "gm_construct map\\n"\n')
        self.assertEqual(self.settings(out['sky0'])['rtx.skyMode'], '0')
        taken = self.settings(out['sky2'])
        self.assertEqual((taken['rtx.skyMode'], taken['rtx.atmosphere.cloudDensity']), ('1', '7'))
        engine = self.engine(out['engine1'])
        self.assertEqual((engine['r_3dsky'], engine['r_novis'], engine['saved'], engine['here']), ('0', '1', '', 'map'))
        self.assertEqual(out['api1'].split()[0], 'taken')
        self.assertEqual(out['choices'], '')  # unchanged: nothing was written in this session
        # Choosing the map's sky again shows it again.
        out = self.map_sky('{ "nativeloader_weather", "overcast" }, { "nativeloader_sky_here", "rtx" }, '
                           '{ "nativeloader_sky_here", "map" }', preset='SAVED_CHOICES = "gm_construct map\\n"\n')
        self.assertEqual(self.settings(out['sky3'])['rtx.skyMode'], '0')
        self.assertEqual(self.engine(out['engine3'])['r_3dsky'], '1')

    def test_a_maps_rtx_version_brings_a_sky_file_that_comes_above_the_rtx_sky(self):
        # The user's choice of 2026-11-20: a map's RTX version's own sky by default. Sky files are content: JSON in
        # data_static/nativeloader/sky/<map>/<id>.json, checked, the higher priority first.
        folder = 'data_static/nativeloader/sky/gm_construct/'
        files = {
            'hd.json': ('{"hd"}', '{ version = 1, sky = "skybox", skyname = "sky_day01_01", title = "Construct HD", priority = 5 }'),
            'own.json': ('{"own"}', '{ version = 1, sky = "map", title = "Construct RTX", skybox3d = false }'),
            'offered.json': ('{"offered"}', '{ version = 1, sky = "map", title = "Offered", default = false, priority = 9 }'),
            'v2.json': ('{"v2"}', '{ version = 2, sky = "map" }'),
            'climb.json': ('{"climb"}', '{ version = 1, sky = "skybox", skyname = "../../x" }'),
            'rtx.json': ('{"rtx"}', '{ version = 1, sky = "map" }'),
            'broken.json': ('not json', None),
        }
        sky_files = 'SKY_FILES = { ' + ', '.join(f'["{folder}{name}"] = {json.dumps(text)}' for name, (text, _) in files.items()) + ' }\n'
        json_map = 'JSON = { ' + ', '.join(f'[{json.dumps(text)}] = {table}' for text, table in files.values() if table) + ' }\n'
        out = self.map_sky('{ "nativeloader_sky_here", "rtx" }, { "nativeloader_sky_here", "own" }, '
                           '{ "nativeloader_sky_here", "offered" }', preset=sky_files + json_map, SKYNAME='painted')
        # Single-player: the highest priority file that is not only offered, its sky by name.
        self.assertEqual(self.settings(out['sky0'])['rtx.skyMode'], '0')
        self.assertEqual(self.engine(out['engine0'])['skyname'], 'sky_day01_01')
        self.assertEqual(out['api0'].split()[:4], ['own', 'file', 'package', 'true'])
        self.assertEqual(out['chat'], '[RTX] This map shows the sky of Construct HD. For the RTX sky: type nativeloader_sky_here '
                                      'rtx in the console, or use RTX Remix > Sky and weather in the spawn menu.')
        # The player's RTX sky; the map's own sky name back.
        self.assertEqual(self.settings(out['sky1'])['rtx.skyMode'], '1')
        self.assertEqual(self.engine(out['engine1'])['skyname'], 'painted')
        self.assertIn('Its RTX version has a sky of its own, from Construct HD: type nativeloader_sky_here auto',
                      out['line1'])
        # Another file by its id: the map's own sky without the 3D pass; an offered file.
        engine = self.engine(out['engine2'])
        self.assertEqual((engine['skyname'], engine['r_3dsky']), ('painted', '0'))
        self.assertEqual(out['api2'].split()[:4], ['own', 'file', 'choice', 'false'])
        self.assertEqual(out['api3'].split()[:3], ['own', 'file', 'choice'])
        # In priority order; the version 2 file, the climbing sky name, the reserved id and the broken JSON left out.
        self.assertIn('sky files offered(map) hd(skybox sky_day01_01) own(map);', out['status_map'])
        # In a game with more players a sky by name is left out (sv_skyname is every player's): the next file.
        out = self.map_sky(preset=sky_files + json_map, SKYNAME='painted', SINGLE=False)
        self.assertEqual(self.engine(out['engine0'])['skyname'], 'painted')
        self.assertTrue(out['chat'].startswith('[RTX] This map shows the sky of Construct RTX.'), out['chat'])

    def test_a_fixed_addon_sky_stays_and_the_players_choice_for_the_map_replaces_it(self):
        # ADR 0248 kept (the user's answer): the add-on's fixed sky at the start, also under the player's own time;
        # the chat line names it. Choosing the RTX sky for the map takes it over (takenOver true); going back to it
        # in the session keeps the RTX sky until the next map's start, when the add-on sets its own again.
        out = self.map_sky('{ "nativeloader_sky_here", "rtx" }, { "nativeloader_sky_here", "auto" }',
                           preset='PRESET = { nativeloader_sky_follow_map = "0" }\nFIXED_SKY_ADDON = true\n',
                           map_name='gm_stelliferous', skyname='sky_orbit_01_hdr', camera=64)
        self.assertEqual(out['start'].split()[0], '0')
        self.assertEqual(out['api0'].split()[0], 'addon')
        self.assertEqual(out['api0'].split()[-1], 'false')
        self.assertEqual(out['chat'], '[RTX] This map shows the sky of Station RTX. For the RTX sky: type nativeloader_sky_here '
                                      'rtx in the console, or use RTX Remix > Sky and weather in the spawn menu.')
        self.assertEqual(self.settings(out['sky1'])['rtx.skyMode'], '1')
        self.assertEqual(out['api1'].split()[-1], 'true')
        # The add-on names itself no more once its sky is replaced; the companion still knows it for this map.
        self.assertEqual(out['line1'], 'This map shows the RTX sky, as you chose for it. Its RTX version has a sky of its own, '
                                       'from Station RTX: type nativeloader_sky_here auto in the console, or use RTX Remix > '
                                       'Sky and weather in the spawn menu.')
        self.assertEqual(out['api2'].split()[0], 'taken')
        self.assertEqual(out['api2'].split()[-1], 'true')
        self.assertEqual(out['line2'], 'This map shows the RTX sky until the next map starts, when the sky of Station RTX returns.')
        # At the next start the add-on's sky is back (auto was saved as no choice at all).
        self.assertEqual(out['choices'], '')
        # A start with the RTX sky chosen for the map: the add-on never names itself, its fixed sky is still offered.
        out = self.map_sky(preset='FIXED_SKY_ADDON = true\nSAVED_CHOICES = "gm_stelliferous rtx\\n"\n',
                           map_name='gm_stelliferous', skyname='sky_orbit_01_hdr', camera=64)
        self.assertEqual(self.settings(out['start'])['rtx.skyMode'], '1')
        self.assertEqual(out['chat'], '[RTX] This map shows the RTX sky, as you chose for it. Its RTX version has a sky of its '
                                      'own: type nativeloader_sky_here auto in the console, or use RTX Remix > Sky and weather '
                                      'in the spawn menu.')

    def test_the_sky_and_weather_page_has_this_maps_choice_and_the_one_for_other_maps(self):
        # ADR 0249: what this map shows, This map (automatic, the RTX sky, the map's own sky, each sky file), Other
        # maps (nativeloader_sky), the chat line's checkbox; a map without a sky of its own says so and offers none.
        folder = 'data_static/nativeloader/sky/gm_construct/'
        preset = (f'SKY_FILES = {{ ["{folder}hd.json"] = "hd" }}\n'
                  'JSON = { hd = { version = 1, sky = "map", title = "Construct HD" } }\n')
        for faces in (True, False):
            with self.subTest(faces=faces):
                lines = [line.split(' ', 1)[1].split('|') for line in self.run_lines(
                    preset + ('' if faces else 'FACES = false\n') + SESSION, MAP='gm_construct',
                    BSP=self.sky_map('painted', 16), SCRIPT='panel') if line.startswith('panel ')]
                sky = [parts[1:] for parts in lines if parts[0] == 'sky']
                self.assertIn(['Help', 'This map shows the sky of Construct HD.'], sky)
                here = sky.index(['ComboBox', 'This map', 'nativeloader_sky_here'])
                choices = [parts[1:] for parts in sky[here + 1:] if parts[0] == 'choice']
                expected = [['Automatic', 'auto'], ['RTX sky', 'rtx']] + ([["The map's own sky", 'map']] if faces else []) \
                    + [['Sky of Construct HD', 'hd'], ['RTX sky', '1'], ['Their own sky', '0']]
                self.assertEqual(choices[:len(expected)], expected)  # the two combo boxes; Season and the others follow
                self.assertIn(['ComboBox', 'Other maps', 'nativeloader_sky'], sky)
                self.assertIn(['CheckBox', 'Say which sky shows', 'nativeloader_sky_message'], sky)
                self.assertEqual(['ControlHelp', 'This map has no sky of its own to switch to.'] in sky, not faces)

    def test_the_map_sky_module_reads_maps_and_checks_sky_files(self):
        # nativeloader/map_sky.lua under plain LuaJIT: names, titles, texinfo flags, an LZMA lump's stream, the files'
        # checks, the order, and which sky the map shows for each choice.
        script = r'''
local M = dofile(LUA .. "/nativeloader/map_sky.lua")
local function with(t) return function() return t end end
print("ids " .. tostring(M.validId("hd_sky-2")) .. " " .. tostring(M.validId("auto")) .. " " .. tostring(M.validId("Hd"))
  .. " " .. tostring(M.validId("../x")) .. " " .. tostring(M.validId(string.rep("a", 49))))
print("skynames " .. tostring(M.validSkyname("zaton/c_expos_zaton_evening_")) .. " " .. tostring(M.validSkyname("../x"))
  .. " " .. tostring(M.validSkyname("a//b")) .. " " .. tostring(M.validSkyname("/a")) .. " " .. tostring(M.validSkyname("a.b")))
print("maps " .. tostring(M.validMap("gm_construct")) .. " " .. tostring(M.validMap("a..b")) .. " " .. tostring(M.validMap("a/b")))
print("title [" .. M.title("  Station\tRTX \n") .. "] " .. #M.title(string.rep("\195\169", 40)) .. " " .. tostring(M.title("\1\2")))
local function rec(flags) return string.rep("\0", 64) .. string.char(flags % 256, math.floor(flags / 256) % 256, 0, 0) .. "\0\0\0\0" end
print("texinfos " .. M.skyTexinfos(rec(0) .. rec(4) .. rec(0x200) .. rec(2), bit.band) .. " " .. M.skyTexinfos("", bit.band))
print("camera " .. M.skyCamera({ { classname = "sky_camera", scale = "32" } }).scale .. " "
  .. M.skyCamera({ { classname = "sky_camera", scale = "x" } }).scale .. " " .. tostring(M.skyCamera({ { classname = "worldspawn" } })))
local stream = M.lzmaStream("LZMA\16\0\0\0\4\0\0\0PROPSdata")
print("lzma " .. #stream .. " " .. stream:sub(1, 5) .. " " .. stream:byte(6) .. " " .. stream:sub(14) .. " " .. tostring(M.lzmaStream("xx")))
local bad = {
  { "x", { version = 2, sky = "map" } }, { "x", { version = 1, sky = "space" } },
  { "x", { version = 1, sky = "skybox" } }, { "x", { version = 1, sky = "map", default = "yes" } },
  { "x", { version = 1, sky = "map", priority = 101 } }, { "x", { version = 1, sky = "map", priority = 1.5 } },
  { "map", { version = 1, sky = "map" } },
}
for i, case in ipairs(bad) do print("bad" .. i .. " " .. tostring(select(2, M.declaration(case[1], "{}", with(case[2]))))) end
print("bad8 " .. tostring(select(2, M.declaration("x", string.rep(" ", 16385), with({ version = 1, sky = "map" })))))
print("bad9 " .. tostring(select(2, M.declaration("x", "{", function() error("no") end))))
local a = M.declaration("a", "{}", with({ version = 1, sky = "map" }))
local b = M.declaration("b", "{}", with({ version = 1, sky = "skybox", skyname = "sky_day01_01", priority = 3, skybox3d = false }))
local c = M.declaration("c", "{}", with({ version = 1, sky = "map", default = false, priority = 9 }))
local files = M.sorted({ a, b, c })
print("order " .. files[1].id .. files[2].id .. files[3].id .. " " .. a.title .. " " .. tostring(b.skybox3d))
local f = M.facts({ texinfos = 2, faces = true, camera = { scale = 16 } })
local function r(s) s.facts = s.facts or f s.files = s.files or files local x = M.resolve(s)
  return x.sky .. "/" .. x.reason .. "/" .. tostring(x.threeD) .. "/" .. tostring(x.skyname) .. "/" .. tostring(x.file and x.file.id) end
print("resolve " .. r({ choice = "auto", single = true }) .. " " .. r({ choice = "auto", single = false }) .. " "
  .. r({ choice = "c", single = true }) .. " " .. r({ choice = "zzz", single = true }) .. " "
  .. r({ choice = "auto", files = {}, global = "0" }) .. " " .. r({ choice = "auto", files = {}, global = "1" }))
'''
        out = self.run_lua(script)
        self.assertEqual(out['ids'], 'true false false false false')
        self.assertEqual(out['skynames'], 'true false false false false')
        self.assertEqual(out['maps'], 'true false false')
        self.assertEqual(out['title'], '[Station RTX] 64 nil')
        self.assertEqual(out['texinfos'], '2 0')
        self.assertEqual(out['camera'], '32 16 nil')
        self.assertEqual(out['lzma'], '17 PROPS 16 data nil')
        for i in range(1, 10):
            self.assertNotEqual(out[f'bad{i}'], 'nil', i)
        self.assertEqual(out['order'], 'cba a false')
        self.assertEqual(out['resolve'], 'file/package/false/sky_day01_01/b file/package/true/nil/a file/choice/true/nil/c '
                                         'file/package/false/sky_day01_01/b map/global/true/nil/nil rtx/default/nil/nil/nil')

    def test_engine_settings_an_earlier_map_changed_go_back_at_the_next_maps_start(self):
        # A level change keeps convars and starts the client's Lua afresh: the record in nativeloader_sky_engine_saved
        # puts back what the map's own 3D skybox changed, on a map that shows the RTX sky.
        preset = ('ENGINE_START = { r_3dsky = "1", r_novis = "0", rtx_patch_forcenovis = "0", rtx_patch_vis_pas = "1" }\n'
                  'PRESET = { nativeloader_sky_engine_saved = "r_3dsky=0;r_novis=1;rtx_patch_forcenovis=1;rtx_patch_vis_pas=0" }\n')
        out = self.map_sky(preset=preset, camera=None)
        engine = self.engine(out['engine0'])
        self.assertEqual((engine['r_3dsky'], engine['r_novis'], engine['forcenovis'], engine['vis_pas'], engine['saved']),
                         ('0', '1', '1', '0', ''))
        # Leaving a map with its 3D skybox shown puts them back and keeps the record for the next start to check.
        out = self.map_sky('{ "nativeloader_sky_here", "map" }, { "shutdown" }')
        engine = self.engine(out['engine2'])
        self.assertEqual((engine['forcenovis'], engine['vis_pas']), ('1', '0'))
        self.assertEqual((engine['r_3dsky'], engine['r_novis']), ('0', '1'))
        self.assertNotEqual(engine['saved'], '')

    def test_a_slider_writing_back_its_rounded_value_keeps_the_maps_sun(self):
        out = self.run_lua(SESSION, MAP='gm_construct', BSP=bsp(CONSTRUCT), SCRIPT='slider')
        self.assertEqual(out['written_back'], '1')
        self.assertEqual(out['moved'], '0')

    def test_rain_fades_out_under_cover_and_back_outside(self):
        # The runtime's own cover test is off (it finds the 3D skybox room above every drop); the
        # game's trace up decides, and the rain fades over half a second.
        out = self.run_lua(SESSION, MAP='gm_construct', BSP=bsp(CONSTRUCT), SCRIPT='shelter')
        outside = self.settings(out['outside'])
        self.assertEqual((outside['rtx.weather.precipitation.intensity'],
                          outside['rtx.weather.precipitation.occludeUnderCover']), ('0.8', 'False'))
        self.assertEqual(self.settings(out['fading'])['rtx.weather.precipitation.intensity'], '0.4')
        inside = self.settings(out['inside'])
        self.assertEqual((inside['rtx.weather.precipitation.intensity'], inside['rtx.atmosphere.cloudDensity']), ('0', '7'))
        self.assertEqual(self.settings(out['again'])['rtx.weather.precipitation.intensity'], '0.8')

    def test_the_maps_skybox_gives_back_the_maps_sun(self):
        out = self.run_lua('CONF = { ["rtx.ignoreGameDirectionalLights"] = "False" }\n' + SESSION, MAP='gm_construct',
                           BSP=bsp(CONSTRUCT), SCRIPT='skybox')
        skybox = self.settings(out['skybox'])
        self.assertEqual((skybox['rtx.skyMode'], skybox['rtx.ignoreGameDirectionalLights']), ('0', 'False'))

    def test_a_night_map_starts_at_night_with_the_moon_where_its_light_is(self):
        night = CONSTRUCT.replace('"painted"', '"sky_borealis01"')
        out = self.run_lua(SESSION, MAP='gm_nightcity', BSP=bsp(night), SCRIPT='night')
        hour, _, follow = out['convars'].split()
        self.assertEqual((hour, follow), ('23.00', '1'))
        # The moon's ground light fades in with the twilight: all of it at night (the sun 20 degrees
        # down), a trace at dusk (about 5 degrees down: smoothstep of 1/8 of 240, some 10; the time
        # is kept to two decimals, which moves the sun a little).
        self.assertEqual(self.settings(out['moonlight_night'])['rtx.atmosphere.surfaceMoonBrightness'], '240.0')
        dusk = float(self.settings(out['moonlight_dusk'])['rtx.atmosphere.surfaceMoonBrightness'])
        self.assertTrue(5 < dusk < 20, dusk)
        moon_bearing, moon_elevation, sun_elevation = self.numbers(out['night'])
        self.assertAlmostEqual(moon_bearing, 324.0, delta=0.05)
        self.assertGreater(moon_elevation, 0)
        self.assertLess(sun_elevation, -15)

    def test_an_eclipse_puts_the_moon_in_earths_shadow_or_before_the_sun(self):
        out = self.run_lua(SESSION, MAP='gm_construct', BSP=bsp(CONSTRUCT), SCRIPT='eclipse')
        self.assertEqual(self.settings(out['look']), {
            'rtx.atmosphere.eclipseEnable': 'True', 'rtx.atmosphere.eclipseUmbraScale': '2.65',
            'rtx.atmosphere.eclipsePenumbraScale': '4.8', 'rtx.atmosphere.eclipseSunScale': '0.97',
            'rtx.atmosphere.moonTextureEnable': 'True', 'rtx.atmosphere.starMapEnable': 'True',
            # Under the night sky image the weather's airglow (partly cloudy: 0.008) is turned down.
            'rtx.atmosphere.nightSkyBrightness': '0.0004'})

        def geometry(tag):
            anti, sun, elevation, phase, hour, follow = out[tag].split()
            return float(anti), float(sun), float(elevation), phase, hour, follow

        # The full moon of the map's afternoon passes clear of Earth's shadow.
        anti, _, _, phase, _, follow = geometry('plain')
        self.assertAlmostEqual(anti, 5.64, delta=0.01)
        self.assertEqual((phase, follow), ('0.500', '1'))
        # A lunar eclipse needs the night: the clock goes to midnight, off the map's sun; at 100 the
        # moon is in the middle of the shadow, at 50 2.12 degrees out (sky_model.eclipseSeparation).
        anti, _, elevation, phase, hour, follow = geometry('lunar100')
        self.assertAlmostEqual(anti, 0.0, delta=0.01)
        self.assertLess(elevation, -8)
        self.assertEqual((phase, hour, follow), ('0.500', '0.00', '0'))
        self.assertAlmostEqual(geometry('lunar50')[0], 2.12, delta=0.01)
        # A solar eclipse needs the day: noon, a new moon 0.71 degrees from the sun at 50.
        _, sun, elevation, phase, hour, _ = geometry('solar50')
        self.assertAlmostEqual(sun, 1.576 + (0.024 - 1.576) * 0.5 / 0.9, delta=0.01)
        self.assertGreater(elevation, 15)
        self.assertEqual((phase, hour), ('0.000', '12.00'))
        # No eclipse: the chosen phase again, the moon clear of the shadow, the time kept.
        anti, _, _, phase, hour, _ = geometry('none')
        self.assertAlmostEqual(anti, 5.64, delta=0.01)
        self.assertEqual((phase, hour), ('0.500', '12.00'))
        self.assertEqual(self.settings(out['stars']), {
            'rtx.atmosphere.starMapEnable': 'False', 'rtx.atmosphere.nightSkyBrightness': '0.008'})

    def test_the_moon_by_day_goes_to_remix(self):
        # ADR 0207: by default the moon by day is as bright as the real Moon at its phase (1, the runtime's own
        # default); the slider scales it from 0 (no moon while the sun is up) to 4, and is not a change of time.
        out = self.run_lua(SESSION, MAP='gm_construct', BSP=bsp(CONSTRUCT), SCRIPT='moonday')
        self.assertEqual(self.settings(out['start'])['rtx.atmosphere.daytimeMoonBrightness'], '1')
        self.assertEqual(self.settings(out['moonday_bright'])['rtx.atmosphere.daytimeMoonBrightness'], '2.5')
        self.assertEqual(out['moonday_follow'], '1')
        self.assertEqual(self.settings(out['moonday_high'])['rtx.atmosphere.daytimeMoonBrightness'], '4')
        self.assertEqual(self.settings(out['moonday_off'])['rtx.atmosphere.daytimeMoonBrightness'], '0')
        self.assertIn('moon by day 0.00', out['moonday_status'])
        # The reset lands on the default sky, Enhanced; Standard, chosen again, has the moon by day back at 1.
        self.assertEqual(self.settings(out['moonday_reset_mode'])['rtx.skyMode'], '2')
        self.assertEqual(self.settings(out['moonday_reset'])['rtx.atmosphere.daytimeMoonBrightness'], '1')

    # The night sky editor's options at their defaults: Remix's own values (the image's 0.12, the runtime's star,
    # halo and earthshine defaults) and the moon's 1.6 degrees.
    EDITOR_DEFAULTS = {
        'rtx.atmosphere.starMapBrightness': '0.12', 'rtx.atmosphere.starMapStarBrightness': '1',
        'rtx.atmosphere.starMapStarSaturation': '1', 'rtx.atmosphere.starMapConstellationBrightness': '1',
        'rtx.atmosphere.starMapConstellationSaturation': '1', 'rtx.atmosphere.starMapGalaxyBrightness': '1',
        'rtx.atmosphere.starMapGalaxySaturation': '1', 'rtx.atmosphere.starMapNebulaBrightness': '1',
        'rtx.atmosphere.starMapNebulaSaturation': '1', 'rtx.atmosphere.starBrightness': '0.5',
        'rtx.atmosphere.starDensity': '0.5', 'rtx.atmosphere.starTwinkleSpeed': '1', 'rtx.atmosphere.moon0.brightness': '1',
        'rtx.atmosphere.moon0.angularRadius': '1.6', 'rtx.atmosphere.haloMoonBrightness': '15',
        'rtx.atmosphere.moon0.darkSideBrightness': '0.005', 'rtx.atmosphere.shootingStarsPerMinute': '1.2',
        'rtx.atmosphere.shootingStarBrightness': '1'}

    def test_the_night_sky_editor_sets_each_element(self):
        # ADR 0227: every element of the night sky with the companion's sky from the map's start; a slider sends
        # its option at once and leaves the map's sun followed; values are held to their ranges.
        out = self.run_lua(SESSION, MAP='gm_construct', BSP=bsp(CONSTRUCT), SCRIPT='editor')
        self.assertEqual(self.settings(out['editor_start']), self.EDITOR_DEFAULTS)
        self.assertEqual(out['editor_calls'].split(), ['1', '1'])
        self.assertEqual(self.settings(out['editor_stars'])['rtx.atmosphere.starMapStarBrightness'], '3')
        self.assertEqual(self.settings(out['editor_high'])['rtx.atmosphere.starMapStarBrightness'], '8')
        self.assertEqual(self.settings(out['editor_text'])['rtx.atmosphere.starMapStarBrightness'], '1')
        self.assertEqual(self.settings(out['editor_scaled']), {
            'rtx.atmosphere.starMapBrightness': '0.24', 'rtx.atmosphere.moon0.darkSideBrightness': '0.015',
            'rtx.atmosphere.haloMoonBrightness': '7.5', 'rtx.atmosphere.shootingStarsPerMinute': '6',
            'rtx.atmosphere.starDensity': '0.75'})
        # Twice as wide: the disc's option, and a quarter of the ground light per area, so the night is as light.
        moon16 = float(self.settings(out['editor_moon16'])['rtx.atmosphere.surfaceMoonBrightness'])
        moon32 = self.settings(out['editor_moon32'])
        self.assertGreater(moon16, 100)
        self.assertEqual(moon32['rtx.atmosphere.moon0.angularRadius'], '3.2')
        self.assertAlmostEqual(float(moon32['rtx.atmosphere.surfaceMoonBrightness']), moon16 / 4, delta=0.1)
        # The eclipse geometry by the bigger moon's radius: clear of its larger shadow without an eclipse
        # ((4.8 + 1) x 1.6 + 1 degrees), and half way through a lunar eclipse where the model puts it.
        self.assertAlmostEqual(float(out['editor_clear']), (4.8 + 1) * 1.6 + 1, delta=0.01)
        lunar, expected = self.numbers(out['editor_lunar50'])
        self.assertAlmostEqual(lunar, expected, delta=0.01)
        # The night glow doubles the weather's airglow.
        glow, doubled = self.numbers(out['editor_glow'])
        self.assertGreater(glow, 0)
        self.assertAlmostEqual(doubled, 2 * glow, delta=1e-9)
        self.assertIn('night sky editor: image 2.00; stars 1.00 (colour 1.00)', out['editor_status'])
        self.assertIn('moon 1.00, 3.20 deg, glow 0.50, earthshine 3.00; shooting stars 6.0 a minute', out['editor_status'])
        # The editor's reset puts every element back, the night glow too.
        self.assertEqual(self.settings(out['editor_reset']), self.EDITOR_DEFAULTS)
        self.assertAlmostEqual(float(out['editor_reset_glow']), glow, delta=1e-9)

    def run_lines(self, body: str, **globals_) -> list:
        """The harness's whole output, line by line (run_lua keeps only the first line of each key)."""
        with tempfile.TemporaryDirectory(dir=REPO / 'out' / 'tmp') as scratch:
            script = Path(scratch) / 'harness.lua'
            prelude = f'LUA = {json.dumps(str(LUA))}\nCONSTRUCT = {json.dumps(CONSTRUCT)}\nCONF = {{}}\n'
            for name, value in globals_.items():
                prelude += f'{name} = {lua_string(value) if isinstance(value, bytes) else json.dumps(value)}\n'
            script.write_text(prelude + body, encoding='utf-8')
            done = subprocess.run([LUAJIT, str(script)], capture_output=True, text=True, timeout=60, cwd=scratch)
        self.assertEqual(done.returncode, 0, done.stderr + done.stdout)
        return done.stdout.splitlines()

    def test_the_night_sky_editor_page_has_a_control_for_each_element(self):
        # ADR 0227: the Night sky editor page builds, every editor setting has its slider over its own range (the
        # moon's size from 0.5, the shooting stars to 15 with one decimal), the page has Go to night, Time passes, the
        # Night sky choice and its reset; the Sky and weather page still builds and points to it.
        lines = [line.split(' ', 1)[1].split('|') for line in self.run_lines(SESSION, MAP='gm_construct', BSP=bsp(CONSTRUCT),
                                                                                SCRIPT='panel') if line.startswith('panel ')]
        night = [parts[1:] for parts in lines if parts[0] == 'night']
        sky = [parts[1:] for parts in lines if parts[0] == 'sky']
        sliders = {parts[2]: (parts[1], float(parts[3]), float(parts[4]), int(parts[5])) for parts in night
                   if parts[0] == 'NumSlider'}
        ranges = {'night_image': (0, 4), 'stars_brightness': (0, 8), 'stars_colour': (0, 2),
                  'constellations_brightness': (0, 8), 'constellations_colour': (0, 2), 'milky_way_brightness': (0, 8),
                  'milky_way_colour': (0, 2), 'nebulae_brightness': (0, 8), 'nebulae_colour': (0, 2),
                  'simulated_brightness': (0, 4), 'simulated_density': (0, 1), 'simulated_twinkle': (0, 4),
                  'moon_brightness': (0, 4), 'moon_size': (0.5, 5), 'moon_glow': (0, 4), 'earthshine': (0, 8),
                  'shooting_stars': (0, 15), 'shooting_star_brightness': (0, 8), 'night_glow': (0, 4)}
        self.assertEqual(set(sliders), {'nativeloader_sky_' + name for name in ranges})
        for name, (low, high) in ranges.items():
            label, got_low, got_high, decimals = sliders['nativeloader_sky_' + name]
            self.assertEqual((got_low, got_high), (low, high), name)
            self.assertEqual(decimals, 1 if name == 'shooting_stars' else 2, name)
            self.assertTrue(label, name)
        self.assertEqual(sliders['nativeloader_sky_constellations_brightness'][0], 'Constellations')
        self.assertIn(['Button', 'Go to night', 'nativeloader_sky_time', 'night'], night)
        self.assertIn(['CheckBox', 'Time passes', 'nativeloader_sky_time_passes'], night)
        self.assertIn(['ComboBox', 'Night sky', 'nativeloader_sky_stars'], night)
        self.assertIn(['Button', 'Reset the night sky', 'nativeloader_sky_night_reset'], night)
        for heading in ('Night sky image', 'Simulated stars', 'Moon', 'Shooting stars', 'Night glow'):
            self.assertIn(['Help', heading], night)
        self.assertIn(['ControlHelp', 'The Night sky editor, next to this page, sets how each part of the night sky looks.'],
                      sky)
        self.assertIn(['Button', 'Reset the sky and weather', 'nativeloader_sky_reset'], sky)

    def test_night_page_shows_both_star_sources_and_labels_standard_only_controls(self):
        for quality, vr in [('0', False), ('1', False), ('1', True)]:
            with self.subTest(quality=quality, vr=vr):
                setup = f'PRESET={{nativeloader_sky_enhanced="{quality}"}}\n'
                if vr:
                    setup += 'NativeLoaderVR={state="running"}\n'
                lines = self.run_lines(setup + SESSION, MAP='gm_construct', BSP=self.sky_map(), SCRIPT='panel')
                night = [line.removeprefix('panel night|').split('|') for line in lines if line.startswith('panel night|')]
                at = night.index(['ComboBox', 'Stars', 'nativeloader_sky_enhanced_stars'])
                self.assertEqual(night[at + 1:at + 3], [['choice', 'Night sky image', 'map'], ['choice', 'Real stars', 'real']])
                self.assertIn('For Enhanced', night[at + 3][1])
                self.assertIn(['ComboBox', 'Night sky', 'nativeloader_sky_stars'], night)
                sliders = {row[2] for row in night if row[0] == 'NumSlider'}
                for name in ('simulated_density', 'simulated_twinkle', 'earthshine', 'night_glow', 'moon_glow', 'shooting_stars'):
                    self.assertIn('nativeloader_sky_' + name, sliders)
                help_text = ' '.join(row[1] for row in night if row[0] == 'ControlHelp')
                for fragment in ("Standard's simulated stars", 'dark side in Standard', "Standard's airglow"):
                    self.assertIn(fragment, help_text)

    def test_the_night_sky_editor_reaches_a_maps_own_sky_without_taking_it_over(self):
        # On a map whose add-on owns the sky: nothing at the start while every element is at its default; a
        # change goes out alone; a saved change goes out at the start; the sky stays the add-on's.
        out = self.run_lua('MHRTX_Config = {}\n' + SESSION, MAP='modern_house', BSP=bsp(CONSTRUCT), SCRIPT='editor_owned')
        self.assertEqual(out['owned_start_options'], 'none')
        self.assertEqual(out['owned_calls'].split(), ['1', 'nil', '0'])
        self.assertEqual(out['owned_after'].split(), ['1', 'rtx.skyMode=nil'])
        out = self.run_lua('MHRTX_Config = {}\nPRESET = { nativeloader_sky_nebulae_colour = "0.25" }\n' + SESSION,
                           MAP='modern_house', BSP=bsp(CONSTRUCT), SCRIPT='editor_owned')
        self.assertEqual(out['owned_start_options'], 'rtx.atmosphere.starMapNebulaSaturation')
        self.assertEqual(self.settings(out['start']).get('rtx.skyMode'), 'nil')

    def test_a_fog_preset_sets_remix_fog_and_the_weather_leaves_it_alone(self):
        out = self.run_lua(SESSION, MAP='gm_construct', BSP=bsp(CONSTRUCT), SCRIPT='fog', MENU=True)
        # Remix's Heavy Fog preset, as its menu's Apply button sets it.
        self.assertEqual(self.settings(out['preset']), {
            'rtx.volumetrics.enable': 'True', 'rtx.volumetrics.enableFogRemap': 'False',
            'rtx.volumetrics.transmittanceMeasurementDistanceMeters': '5', 'rtx.volumetrics.anisotropy': '-0.2'})
        self.assertEqual(out['colours'], '0.85, 0.85, 0.85|0.9, 0.9, 0.9')
        # A change of weather blends its clouds in but leaves the preset's fog.
        weather = self.settings(out['weather'])
        self.assertEqual(weather['rtx.volumetrics.transmittanceMeasurementDistanceMeters'], '5')
        self.assertNotEqual(weather['rtx.atmosphere.cloudDensity'], '0.9')
        self.assertEqual(out['weather_colour'], '0.85, 0.85, 0.85')
        # Cleared, the weather's fog comes back at the next tick.
        cleared = self.settings(out['cleared'])['rtx.volumetrics.transmittanceMeasurementDistanceMeters']
        self.assertNotEqual(cleared, '5')
        self.assertGreater(float(cleared), 0)

    def test_without_the_remix_api_nothing_is_sent(self):
        out = self.run_lua(SESSION, MAP='gm_construct', BSP=bsp(CONSTRUCT), SCRIPT='skybox', NOAPI=True)
        self.assertEqual(out['start'].split()[0], '0')
        out = self.run_lua('PRESET = { nativeloader_sky_no_horizon = "1" }\n' + SESSION, MAP='gm_construct',
                           BSP=bsp(CONSTRUCT), SCRIPT='horizon', NOAPI=True)
        self.assertEqual(out['start'].split()[0], '0')
        self.assertEqual(out['horizon_on'].split()[0], '0')

    def test_no_horizon_goes_with_the_sky_and_leaves_the_maps_sun_followed(self):
        # R26 (ADR 0139): off by default, sent with the companion's sky at a map's start; ticking it
        # sends the runtime's option alone (the map's sun is still followed), the status names it, and
        # the reset unticks it.
        out = self.run_lua(SESSION, MAP='gm_construct', BSP=bsp(CONSTRUCT), SCRIPT='horizon')
        self.assertEqual(self.settings(out['start'])['rtx.atmosphere.noHorizon'], 'False')
        self.assertEqual(self.settings(out['horizon_on'])['rtx.atmosphere.noHorizon'], 'True')
        self.assertEqual(out['horizon_calls'].split(), ['1', '1'])
        self.assertIn('no horizon (the sky in every direction)', out['status_night'])
        self.assertEqual(out['horizon_off'].split(), ['1', 'False'])
        # The reset lands on the default sky, Enhanced; Standard, chosen again, has the horizon back.
        self.assertEqual(self.settings(out['horizon_reset_mode'])['rtx.skyMode'], '2')
        self.assertEqual(self.settings(out['horizon_reset_mode'])['rtx.atmosphere.noHorizon'], 'False')
        self.assertEqual(self.settings(out['horizon_reset'])['rtx.atmosphere.noHorizon'], 'False')
        # A saved check takes effect at map start with either physical sky.
        for enhanced, mode in (('0', '1'), ('1', '2')):
            with self.subTest(mode=mode):
                preset = f'PRESET = {{ nativeloader_sky_enhanced = "{enhanced}", nativeloader_sky_no_horizon = "1" }}\n'
                out = self.run_lua(preset + SESSION, MAP='gm_construct', BSP=bsp(CONSTRUCT), SCRIPT='skybox')
                start = self.settings(out['start'])
                self.assertEqual((start['rtx.skyMode'], start['rtx.atmosphere.noHorizon']), (mode, 'True'))

    def test_no_horizon_reaches_a_maps_own_sky_without_taking_it_over(self):
        # The horizon is how the player sees whichever physical sky is shown: on a map whose add-on
        # owns the sky it is sent alone, when ticked or changed, and that sky stays the add-on's (no
        # skyMode, nothing on the 10 s timer). Unticked at the start, the companion sends that map nothing.
        out = self.run_lua('MHRTX_Config = {}\n' + SESSION, MAP='modern_house', BSP=bsp(CONSTRUCT),
                           SCRIPT='horizon_owned', NEXT_HORIZON='1')
        self.assertEqual(out['start'].split()[0], '0')
        self.assertEqual(out['owned_start_options'], 'none')
        self.assertEqual(out['owned_calls'].split(), ['1', 'nil', 'True'])
        self.assertEqual(out['owned_after'].split(), ['1', 'rtx.skyMode=nil'])
        # Saved ticked: the map's start sends that option and nothing else (once at InitPostEntity and
        # once with everything 5 s later, as the companion does on every map).
        out = self.run_lua('MHRTX_Config = {}\nPRESET = { nativeloader_sky_no_horizon = "1" }\n' + SESSION,
                           MAP='modern_house', BSP=bsp(CONSTRUCT), SCRIPT='horizon_owned', NEXT_HORIZON='0')
        self.assertEqual(out['owned_start_options'], 'rtx.atmosphere.noHorizon')
        start = self.settings(out['start'])
        self.assertEqual((start['rtx.atmosphere.noHorizon'], start['rtx.skyMode']), ('True', 'nil'))
        self.assertEqual(out['owned_calls'].split(), ['1', 'nil', 'False'])
        self.assertEqual(out['owned_after'].split()[1], 'rtx.skyMode=nil')


if __name__ == '__main__':
    unittest.main()
