-- Runs the companion's real nativeloader/menu/pbr_note.lua (ADR 0217, ADR 0219) in a mocked menu realm: the main
-- menu's state (IsInGame, IsInLoading), the clock, the screen, cookies, the companion's catalog, Steam's overlay,
-- the pointer and Derma.
-- Usage: luajit <this> <repo> <scenario>. See the adjacent .md.
local root, scenario = ...
local SCRIPT = root .. "/companion/nativeloader/lua/nativeloader/menu/pbr_note.lua"
local COLLECTION = "3834474695"

local cookies, convars, logs, panels, hooks, commands = {}, { gmod_language = "en" }, {}, {}, {}, {}
local inGame, loading, now, width, height = false, false, 100, 1920, 1080
local reads, viewed, opened = 0, {}, {}
local hovered -- the panel under the pointer
local failBuild, noViewFile = false, false

local function eq(a, b, what) if a ~= b then error((what or "value") .. ": expected " .. tostring(b) .. ", got " .. tostring(a), 2) end end

MENU_DLL = true
-- GMod's extensions that LuaJIT lacks.
function istable(v) return type(v) == "table" end
function isstring(v) return type(v) == "string" end
function isfunction(v) return type(v) == "function" end
function string.TrimRight(s) return (s:gsub("%s+$", "")) end
function string.TrimLeft(s) return (s:gsub("^%s+", "")) end
utf8 = {}
function utf8.char(code)
    if code < 0x80 then return string.char(code) end
    if code < 0x800 then return string.char(0xC0 + math.floor(code / 0x40), 0x80 + code % 0x40) end
    return string.char(0xE0 + math.floor(code / 0x1000), 0x80 + math.floor(code / 0x40) % 0x40, 0x80 + code % 0x40)
end
function utf8.codes(s)
    local i = 1
    return function()
        if i > #s then return nil end
        local b, code, n = s:byte(i), 0, 1
        if b < 0x80 then code = b
        elseif b < 0xE0 then code, n = (b - 0xC0) * 0x40 + (s:byte(i + 1) - 0x80), 2
        else code, n = (b - 0xE0) * 0x1000 + (s:byte(i + 1) - 0x80) * 0x40 + (s:byte(i + 2) - 0x80), 3 end
        local at = i
        i = i + n
        return at, code
    end
end
function MsgN(text) logs[#logs + 1] = text end
function Color(r, g, b, a) return { r = r, g = g, b = b, a = a or 255 } end
function ScrW() return width end
function ScrH() return height end
function SysTime() return now end
function IsInGame() return inGame end
function IsInLoading() return loading end
KEY_ESCAPE, KEY_ENTER, KEY_PAD_ENTER = 70, 64, 51
function CompileString(source, name) return loadstring(source, name) end
function GetConVar(name)
    if convars[name] == nil then return nil end
    return { GetString = function() return convars[name] end }
end
cookie = {
    GetString = function(key, default) local v = cookies[key] if v == nil then return default end return v end,
    Set = function(key, value) cookies[key] = tostring(value) end,
}
-- The companion keeps the player's language here when its own convar is not visible to the menu realm.
local savedLanguage
file = { Read = function(name, path)
    if name == "nativeloader_companion/language.txt" and path == "DATA" then
        reads = reads + 1
        return savedLanguage
    end
    return nil
end }
steamworks = { ViewFile = function(id) viewed[#viewed + 1] = id end }
gui = { OpenURL = function(url) opened[#opened + 1] = url end }
hook = { Add = function(event, name, fn) hooks[event .. "/" .. name] = fn end }
concommand = { Add = function(name, fn) commands[name] = fn end }
surface = {
    CreateFont = function() end, SetFont = function() end,
    GetTextSize = function(text) return #text * 9, 20 end,
    SetDrawColor = function() end, DrawRect = function() end,
}
local drawn = {}
draw = { RoundedBox = function() end, SimpleText = function(text) drawn[#drawn + 1] = text end }
function IsValid(v) return v ~= nil and v.removed ~= true end
local Panel = {}
Panel.__index = Panel
function Panel:SetSize(w, h) self.w, self.h = w, h end
function Panel:SetPos(x, y) self.x, self.y = x, y end
function Panel:SetWide(w) self.w = w end
function Panel:GetWide() return self.w or 0 end
function Panel:SetTall(h) self.h = h end
function Panel:GetTall() return self.h or 0 end
function Panel:MakePopup() self.popup = true end
function Panel:SetKeyboardInputEnabled(on) self.keyboard = on end
function Panel:SetFont(f) self.font = f end
function Panel:SetText(t) self.text = t end
function Panel:SetTextColor() end
function Panel:IsHovered() return false end
function Panel:RequestFocus() self.focused = true end
function Panel:Remove() self.removed = true end
function Panel:GetParent() return self.parent end
vgui = { Create = function(class, parent)
    if failBuild then error("no Derma in this realm") end
    local panel = setmetatable({ class = class, parent = parent }, Panel)
    panels[#panels + 1] = panel
    return panel
end, GetHoveredPanel = function() return hovered end }

-- The companion's catalog as the RTX client module reads it (a Lua chunk returning { language = { english = text } }).
local CATALOG = [[return { fr = {
    ["Obtaining more PBR resources"] = "Obtenir plus de ressources PBR",
    ["Open the collection"] = "Ouvrir la collection",
} }]]
rawset(_G, "__NATIVELOADER_MENU_API", { read = function(name)
    if name == "nativeloader/nativeloader/i18n_data.lua" then return CATALOG end
    return nil
end })

local function alive(p)
    while p do
        if p.removed then return false end
        p = p.parent
    end
    return true
end
-- The note is the popup without the keyboard.
local function note() for _, p in ipairs(panels) do if p.popup and p.keyboard == false and alive(p) then return p end end end
local function inside(p, top)
    while p do
        if p == top then return true end
        p = p.parent
    end
    return false
end
local function button(text, top)
    for _, p in ipairs(panels) do
        if p.class == "DButton" and p.text == text and alive(p) and inside(p, top) then return p end
    end
    error("no button " .. text)
end
local function hasButton(text, top)
    return pcall(button, text, top)
end
local function paint(top)
    drawn = {}
    for _, p in ipairs(panels) do if p.Paint and alive(p) and inside(p, top) then p.Paint(p, 100, 100) end end
    return table.concat(drawn, " ")
end
local function frame() hooks["Think/NativeLoaderPbrNote"]() end
local function later(seconds) now = now + seconds end
-- Frames 0.25 s apart for `seconds`.
local function run(seconds)
    for _ = 1, math.floor(seconds / 0.25 + 0.5) do
        later(0.25)
        frame()
    end
end

local chunk = assert(loadfile(SCRIPT))
local function start() chunk() end

if scenario == "shows" then
    start()
    frame()
    local n = note()
    assert(n, "the note on the main menu")
    eq(n.keyboard, false, "the note never takes the keyboard")
    eq(n.x + n.w, width - 16, "the note's right edge")
    eq(n.y, 16, "the note's top")
    local text = paint(n)
    assert(text:find("Obtaining more PBR resources", 1, true), text)
    assert(text:find("SheepyLord's RTX Remix collection", 1, true), text)
    -- One line of text under the title: the summary's label is one line tall (20 in this mock).
    local lines = 0
    for _, p in ipairs(panels) do
        if p.class == "DPanel" and p.parent == n and p.h == 20 then lines = lines + 1 end
    end
    eq(lines, 2, "the title and the summary each on one line")
    button("Open the collection", n)
    button("Hide", n)
    button("Don't show again", n)
    eq(hasButton("Maps without PBR", n), false, "the old card's button")
    -- Kept, not rebuilt, frame after frame.
    local count = #panels
    for _ = 1, 50 do frame() end
    eq(#panels, count, "panels made while nothing changed")
elseif scenario == "game-and-loading" then
    inGame = true
    start()
    frame()
    eq(note(), nil, "a note over a running game")
    inGame = false
    frame()
    assert(note(), "the note back on the main menu")
    loading = true
    frame()
    eq(note(), nil, "a note while a map loads")
elseif scenario == "hide" then
    start()
    frame()
    button("Hide", note()).DoClick()
    eq(note(), nil, "the note after Hide")
    run(10)
    eq(note(), nil, "the note again before the next start")
    eq(cookies["nativeloader.pbr-note"], nil, "Hide is not remembered past this start")
elseif scenario == "auto-hide" then
    start()
    frame()
    assert(note(), "the note")
    run(9.5)
    assert(note(), "the note before 10 seconds")
    run(1)
    eq(note(), nil, "the note after 10 seconds")
    run(10)
    eq(note(), nil, "the note again before the next start")
    eq(cookies["nativeloader.pbr-note"], nil, "the 10 seconds are not remembered past this start")
    commands.nativeloader_pbr_note()
    run(0.25)
    assert(note(), "the console command shows the note again")
    run(9.5)
    assert(note(), "for another 10 seconds")
elseif scenario == "pointer" then
    start()
    frame()
    local n = note()
    hovered = button("Hide", n) -- the pointer over one of its buttons
    run(30)
    assert(note(), "the note while the pointer is over it")
    hovered = nil
    run(9.5)
    assert(note(), "the time it had left")
    run(1)
    eq(note(), nil, "the note after its 10 seconds")
elseif scenario == "never" then
    start()
    frame()
    button("Don't show again", note()).DoClick()
    eq(note(), nil, "the note after Don't show again")
    eq(cookies["nativeloader.pbr-note"], "dismissed", "the choice is remembered")
    run(3)
    eq(note(), nil, "the note later")
elseif scenario == "dismissed" then
    cookies["nativeloader.pbr-note"] = "dismissed"
    start()
    frame()
    eq(note(), nil, "a dismissed note")
    commands.nativeloader_pbr_note()
    run(3)
    eq(note(), nil, "the console command keeps Don't show again")
    commands.nativeloader_pbr_note_reset()
    eq(cookies["nativeloader.pbr-note"], "shown", "reset")
    run(0.25)
    assert(note(), "the note after the reset")
elseif scenario == "open" then
    start()
    frame()
    button("Open the collection", note()).DoClick()
    eq(#opened, 1, "the address opened")
    eq(opened[1], "https://steamcommunity.com/sharedfiles/filedetails/?id=" .. COLLECTION, "the collection's address")
    eq(#viewed, 0, "steamworks.ViewFile, which shows nothing without the overlay")
    assert(logs[#logs]:find("opening https://steamcommunity.com", 1, true), logs[#logs])
    gui.OpenURL = nil
    button("Open the collection", note()).DoClick()
    eq(#viewed, 1, "Steam's file view without gui.OpenURL")
    eq(viewed[1], COLLECTION, "the collection")
elseif scenario == "french" then
    convars.gmod_language = "fr"
    start()
    frame()
    local text = paint(note())
    assert(text:find("Obtenir plus de ressources PBR", 1, true), text)
    button("Ouvrir la collection", note())
    button("Hide", note()) -- untranslated text falls back to English
elseif scenario == "throttle" then
    convars.gmod_language = nil -- the language then comes from the companion's saved copy
    savedLanguage = "en"
    start()
    for _ = 1, 200 do frame() end
    assert(reads <= 1, "language reads in one second of frames: " .. reads)
    local first = note()
    assert(first, "the note")
    width, height = 2560, 1440
    frame()
    eq(note(), first, "rebuilt before the two-second look")
    later(2.5)
    frame()
    assert(note() ~= first, "rebuilt for the new screen")
    eq(note().x + note().w, 2560 - math.floor(16 * 1440 / 1080 + 0.5), "the new note's right edge, scaled")
elseif scenario == "tiny-screen" then
    width, height = 0, 0
    start()
    frame()
    eq(note(), nil, "a note on a screen of no size")
    eq(#logs, 0, "console lines")
    width, height = 1920, 1080
    later(3)
    frame()
    assert(note(), "the note once the screen has a size")
elseif scenario == "build-fails" then
    failBuild = true
    start()
    frame()
    eq(#logs, 1, "one console line")
    assert(logs[1]:find("PBR note failed", 1, true), logs[1])
    run(10)
    eq(#logs, 1, "no retry every frame")
elseif scenario == "once" then
    start()
    local first = NativeLoaderPbrNote
    chunk()
    eq(NativeLoaderPbrNote, first, "a second run replaces nothing")
else
    error("unknown scenario " .. tostring(scenario))
end
print("PASS " .. scenario)
