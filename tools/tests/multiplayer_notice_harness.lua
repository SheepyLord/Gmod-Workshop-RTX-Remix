-- Runs the companion's real nativeloader/menu/multiplayer_notice.lua (R24, ADR 0133) in a mocked menu realm:
-- cookies, convars, the module's read API, Derma, the menu page's Call. Usage: luajit <this> <repo> <scenario>.
-- See the adjacent .md.
local root, scenario = ...
local SCRIPT = root .. "/companion/nativeloader/lua/nativeloader/menu/multiplayer_notice.lua"

local cookies, convars, calls, logs, panels, timers = {}, { gmod_language = "en" }, {}, {}, {}, {}
local reads, failBuild = {}, false

local function eq(a, b, what) if a ~= b then error((what or "value") .. ": expected " .. tostring(b) .. ", got " .. tostring(a), 2) end end

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
function ScrW() return 1920 end
function ScrH() return 1080 end
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
util = { TableToJSON = function(t)
    local v = t[1]
    return '["' .. v:gsub('\\', '\\\\'):gsub('"', '\\"') .. '"]'
end }
timer = { Create = function(name, delay, reps, fn) timers[name] = fn end }
local commands = {}
concommand = { Add = function(name, fn) commands[name] = fn end }
local fonts = {}
surface = {
    font = nil,
    CreateFont = function(name, data) fonts[name] = data end,
    SetFont = function(font) surface.font = font end,
    GetTextSize = function(text) return #text * 9, 20 end,
    SetDrawColor = function() end,
    DrawRect = function() end,
}
draw = { RoundedBox = function() end, SimpleText = function() end }
function IsValid(v) return v ~= nil and v.removed ~= true and (type(v) ~= "table" or v.IsValid == nil or v:IsValid()) end
local Panel = {}
Panel.__index = Panel
function Panel:SetSize(w, h) self.w, self.h = w, h end
function Panel:SetPos(x, y) self.x, self.y = x, y end
function Panel:SetWide(w) self.w = w end
function Panel:SetTall(h) self.h = h end
function Panel:GetTall() return self.h or 0 end
function Panel:MakePopup() self.popup = true end
function Panel:SetKeyboardInputEnabled() end
function Panel:SetFont(f) self.font = f end
function Panel:SetText(t) self.text = t end
function Panel:SetTextColor() end
function Panel:IsHovered() return false end
function Panel:RequestFocus() self.focused = true end
function Panel:Remove() self.removed = true end
vgui = { Create = function(class, parent)
    if failBuild then error("no Derma in this realm") end
    local panel = setmetatable({ class = class, parent = parent }, Panel)
    panels[#panels + 1] = panel
    return panel
end }
pnlMainMenu = { Call = function(_, js) calls[#calls + 1] = js end }

-- Removing a panel removes its children, as in Derma.
local function alive(p)
    while p do
        if p.removed then return false end
        p = p.parent
    end
    return true
end
local function texts()
    local found = {}
    for _, p in ipairs(panels) do if p.text and alive(p) then found[#found + 1] = p.text end end
    return table.concat(found, "\n")
end
local function button(text)
    for _, p in ipairs(panels) do if p.class == "DButton" and p.text == text and alive(p) then return p end end
    error("no button " .. text)
end
local function overlay() for _, p in ipairs(panels) do if p.popup then return p end end end
local function run()
    MENU_DLL = true
    __NATIVELOADER_MENU_API = { read = function(name)
        reads[#reads + 1] = name
        if name == "nativeloader/nativeloader/i18n_data.lua" then
            return 'return { ja = { ["Before you join a server"] = "JA-TITLE", ["Don\'t show this again"] = "JA-NEVER" } }'
        end
    end }
    dofile(SCRIPT)
    __NATIVELOADER_MENU_API = nil
end
local function lastCall() return calls[#calls] end

if scenario == "first-start" then
    run()
    eq(cookies["nativeloader.multiplayer-notice"], "active")
    eq(cookies["nativeloader.multiplayer-warning-dismissed"], "1", "the loader's own notice is turned off")
    eq(NativeLoaderMultiplayerNotice.State(), "active")
    assert(calls[1]:find("NativeLoaderReceiveMenuState", 1, true), "the page's half retires the loader's notice")
    assert(calls[1]:find('%(false, "", ""%)$'), calls[1]:sub(-80))
    assert(timers.NativeLoaderMultiplayerNotice, "installed again after a page reload")
    -- A second run in the same realm changes nothing.
    local before = #calls
    run()
    eq(#calls, before)
elseif scenario == "carry-over" then
    cookies["nativeloader.multiplayer-warning-dismissed"] = "1"
    _G.NativeLoaderUpdateSession = "tok-1"
    cookies["nativeloader.loader-update-ignored"] = "0.17.0"
    run()
    eq(NativeLoaderMultiplayerNotice.State(), "dismissed", "an earlier choice in the loader's notice carries over")
    assert(calls[1]:find('%(true, "tok%-1", "0%.17%.0"%)$'), calls[1]:sub(-80))
    NativeLoaderMultiplayerNotice.Open("/servers/internet")
    eq(#panels, 0, "no notice once dismissed")
    assert(lastCall():find('go%("/servers/internet"%)'), lastCall())
elseif scenario == "open" then
    run()
    NativeLoaderMultiplayerNotice.Open("/servers/internet?x=1")
    local all = texts()
    assert(all:find("Don't show this again", 1, true) and all:find("I understand, continue", 1, true) and all:find("Back", 1, true), all)
    assert(overlay(), "a popup")
    -- Fonts that draw every language of the catalog (GMod's fonts without `extended` draw Latin-1 only).
    for _, name in ipairs({ "NativeLoaderMPTitle", "NativeLoaderMPText", "NativeLoaderMPButton" }) do
        assert(fonts[name] and fonts[name].extended == true, name .. " is not extended")
    end
    -- One notice at a time.
    local count = #panels
    NativeLoaderMultiplayerNotice.Open("/servers/internet")
    eq(#panels, count)
    -- Back closes without going on.
    local calls0 = #calls
    button("Back").DoClick()
    assert(overlay().removed, "closed")
    eq(#calls, calls0, "Back does not open the browser")
    -- Continue goes on once and keeps the notice for the next time.
    NativeLoaderMultiplayerNotice.Open("/servers/internet")
    button("I understand, continue").DoClick()
    assert(lastCall():find('go%("/servers/internet"%)'), lastCall())
    eq(NativeLoaderMultiplayerNotice.State(), "active")
    -- Don't show this again: remembered, the page stops asking, the browser opens.
    NativeLoaderMultiplayerNotice.Open("/servers/favorites")
    button("Don't show this again").DoClick()
    eq(cookies["nativeloader.multiplayer-notice"], "dismissed")
    assert(calls[#calls - 1]:find("off = true", 1, true), calls[#calls - 1])
    assert(lastCall():find('go%("/servers/favorites"%)'), lastCall())
elseif scenario == "commands" then
    cookies["nativeloader.multiplayer-warning-dismissed"] = "1"
    run()
    eq(NativeLoaderMultiplayerNotice.State(), "dismissed")
    commands.nativeloader_multiplayer_notice()
    assert(texts():find("Don't show this again", 1, true), "shown on request even after the choice")
    button("Back").DoClick()
    commands.nativeloader_multiplayer_notice_reset()
    eq(cookies["nativeloader.multiplayer-notice"], "active")
    assert(lastCall():find("off = false", 1, true), lastCall())
    NativeLoaderMultiplayerNotice.Open("/servers/internet")
    assert(texts():find("I understand, continue", 1, true), "the browser asks again")
    button("Back").DoClick()
    -- The command's card goes on to the menu's server browser route (menuApp.js has only "/servers/").
    commands.nativeloader_multiplayer_notice()
    button("I understand, continue").DoClick()
    assert(lastCall():find('go%("/servers/"%)'), lastCall())
    -- The status line names the state, the language and its source.
    commands.nativeloader_multiplayer_notice_status()
    local line = logs[#logs]
    assert(line:find("multiplayer notice: active; language en (from gmod_language)", 1, true), line)
    assert(line:find("title: Before you join a server", 1, true), line)
elseif scenario == "targets" then
    run()
    local count = #calls
    NativeLoaderMultiplayerNotice.Open(42)
    eq(#calls, count, "not a target: nothing")
    -- The page held the navigation: whatever is not the server browser's, or is too long, goes on at once.
    NativeLoaderMultiplayerNotice.Open("/servers/" .. string.rep("a", 600))
    assert(lastCall():find('go%("/servers/aaa', 1), lastCall():sub(1, 90))
    NativeLoaderMultiplayerNotice.Open("/addons/")
    assert(lastCall():find('go%("/addons/"%)'), lastCall())
    eq(#panels, 0, "only the server browser's routes get the card")
    -- The page matches the route in any case; so does the script.
    NativeLoaderMultiplayerNotice.Open("/SERVERS/")
    assert(texts():find("I understand, continue", 1, true), "the card for /SERVERS/")
elseif scenario == "loading-page" then
    -- JavaScript queued while the menu page loads piles up in the panel: the page's half waits for the page.
    local loading = true
    pnlMainMenu.HTML = { IsLoading = function() return loading end }
    run()
    eq(#calls, 0, "nothing queued while the page loads")
    timers.NativeLoaderMultiplayerNotice()
    eq(#calls, 0, "nor on the timer")
    loading = false
    timers.NativeLoaderMultiplayerNotice()
    assert(calls[1] and calls[1]:find("NativeLoaderReceiveMenuState", 1, true), "installed once the page has loaded")
elseif scenario == "translation" then
    convars.gmod_language = "ja"
    run()
    NativeLoaderMultiplayerNotice.Open("/servers/internet")
    local all = texts()
    assert(all:find("JA-NEVER", 1, true), all)
    assert(all:find("I understand, continue", 1, true), "an untranslated text stays English")
    eq(reads[1], "nativeloader/nativeloader/i18n_data.lua")
    -- nativeloader_language wins over the game's language; English reads no catalog.
    reads, panels = {}, {}
    NativeLoaderMultiplayerNotice = nil
    convars.nativeloader_language = "en"
    run()
    NativeLoaderMultiplayerNotice.Open("/servers/internet")
    eq(#reads, 0)
elseif scenario == "menu-compile" then
    -- GMod's menu realm has no CompileString, only RunString (PoC, R24): the catalog still loads, through a global
    -- that is cleared at once.
    CompileString = nil
    RunString = function(code, identifier, handleError)
        eq(identifier, "nativeloader/i18n_data.lua")
        eq(handleError, false)
        assert(loadstring(code, identifier))()
    end
    convars.gmod_language = "ja"
    run()
    NativeLoaderMultiplayerNotice.Open("/servers/")
    assert(texts():find("JA-NEVER", 1, true), texts())
    eq(rawget(_G, "__NATIVELOADER_I18N_DATA"), nil, "the global is cleared")
    -- Without either, English and no error.
    button("Back").DoClick()
    NativeLoaderMultiplayerNotice = nil
    RunString, panels = nil, {}
    run()
    NativeLoaderMultiplayerNotice.Open("/servers/")
    assert(texts():find("Don't show this again", 1, true), texts())
elseif scenario == "saved-language" then
    -- The menu realm cannot see the companion's client convar: the copy the companion keeps for the menu counts,
    -- before the game's language.
    convars.gmod_language = "fr"
    local asked
    file = { Read = function(path, where)
        asked = path .. "@" .. where
        return "ja"
    end }
    run()
    NativeLoaderMultiplayerNotice.Open("/servers/")
    assert(texts():find("JA-NEVER", 1, true), texts())
    eq(asked, "nativeloader_companion/language.txt@DATA")
    button("Back").DoClick()
    commands.nativeloader_multiplayer_notice_status()
    assert(logs[#logs]:find("language ja (from nativeloader_language (saved))", 1, true), logs[#logs])
    assert(logs[#logs]:find("title: JA-TITLE", 1, true), logs[#logs])
elseif scenario == "failure" then
    run()
    failBuild = true
    NativeLoaderMultiplayerNotice.Open("/servers/internet")
    assert(logs[1]:find("multiplayer notice failed", 1, true), tostring(logs[1]))
    assert(lastCall():find('go%("/servers/internet"%)'), "a notice that cannot be shown never keeps the browser closed")
elseif scenario == "not-menu" then
    MENU_DLL = nil
    dofile(SCRIPT)
    eq(NativeLoaderMultiplayerNotice, nil)
    eq(#calls, 0)
else
    error("unknown scenario " .. tostring(scenario))
end
print("PASS " .. scenario)
