-- Runs the companion's real nativeloader/menu/unsubscribed_notice.lua (ADR 0188) in a mocked menu realm: the loader's
-- status report, the account's subscriptions (engine.GetAddons), hooks, timers, cookies, Derma. Usage:
-- luajit <this> <repo> <scenario>. See the adjacent .md.
local root, scenario = ...
local SCRIPT = root .. "/companion/nativeloader/lua/nativeloader/menu/unsubscribed_notice.lua"

local cookies, convars, logs, panels, timers, hooks, commands = {}, { gmod_language = "en" }, {}, {}, {}, {}, {}
local status = { packages = { { id = "gmod-rtx-remix", source = "workshop", label = "3829070317" } } }
local addons = {}
local failBuild = false
-- The RTX client module's add-on list and Steam switch functions (ADR 0189): their calls, and what they answer.
local listCalls, listAnswer, noListApi = {}, nil, false
local steamAnswer, noSteamApi = nil, false

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
-- The status report is read whole and decoded by util.JSONToTable: the mock hands over the table.
file = { Read = function(name, path)
    if name == "native-loader/status.json" and path == "DATA" then return status and "{status}" or nil end
    return nil
end }
util = { JSONToTable = function(text) return text == "{status}" and status or nil end }
engine = { GetAddons = function() return addons end }
steamworks = {}
hook = { Add = function(event, name, fn) hooks[event .. "/" .. name] = fn end }
local later = {}
timer = {
    Create = function(name, delay, reps, fn) timers[name] = { delay = delay, reps = reps, fn = fn } end,
    Simple = function(delay, fn) later[#later + 1] = fn end,
}
concommand = { Add = function(name, fn) commands[name] = fn end }
surface = {
    CreateFont = function() end, SetFont = function() end,
    GetTextSize = function(text) return #text * 9, 20 end,
    SetDrawColor = function() end, DrawRect = function() end,
}
draw = { RoundedBox = function() end, SimpleText = function() end }
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
-- The text a card draws: labels keep their wrapped lines in Paint, so the test reads them from the closures' source
-- text instead: every label is built from L(...) calls, which the script exposes through its card only. Here the
-- drawn strings are captured by a draw.SimpleText that records them.
local drawn = {}
draw.SimpleText = function(text) drawn[#drawn + 1] = text end
local function paintAll()
    drawn = {}
    for _, p in ipairs(panels) do if p.Paint and not p.removed then p.Paint(p, 100, 100) end end
    return table.concat(drawn, " ")
end
local function alive(p)
    while p do
        if p.removed then return false end
        p = p.parent
    end
    return true
end
local function card() for _, p in ipairs(panels) do if p.popup and alive(p) then return p end end end
local function button(text)
    for _, p in ipairs(panels) do if p.class == "DButton" and p.text == text and alive(p) then return p end end
    error("no button " .. text)
end
local function run(menu)
    MENU_DLL = menu ~= false
    __NATIVELOADER_MENU_API = { read = function(name)
        if name == "nativeloader/nativeloader/i18n_data.lua" then
            return 'return { ja = { ["RTX Remix is not subscribed on this Steam account"] = "JA-TITLE", ' ..
                '["This Steam account does not subscribe to RTX Remix (Workshop item %s), but RTX Remix is still installed in this game."] = "JA-ITEM %s", ' ..
                '["OK"] = "JA-OK" } }'
        end
    end }
    if not noSteamApi then
        __NATIVELOADER_MENU_API.rtx_steam_state = function()
            if type(steamAnswer) == "function" then return steamAnswer() end
            if steamAnswer == nil then return nil, "Steam's list of the signed-in account cannot be read" end
            return steamAnswer
        end
    end
    if not noListApi then
        __NATIVELOADER_MENU_API.rtx_addon_list = function(off)
            listCalls[#listCalls + 1] = off
            if listAnswer then return listAnswer(off) end
            return off and "added" or "removed"
        end
    end
    dofile(SCRIPT)
    __NATIVELOADER_MENU_API = nil
end
local function tick(n)
    for _ = 1, n or 1 do
        local t = timers.NativeLoaderUnsubscribedNotice
        if t then t.fn() end
        local pending = later
        later = {}
        for _, fn in ipairs(pending) do fn() end
    end
end
local function list(...)
    local out = {}
    for _, id in ipairs({ ... }) do out[#out + 1] = { wsid = id, title = "addon " .. id, mounted = id ~= "3829070317" } end
    return out
end

if scenario == "subscribed" then
    addons = list("111", "3829070317", "222")
    run()
    assert(timers.NativeLoaderUnsubscribedNotice, "checks are scheduled")
    eq(timers.NativeLoaderUnsubscribedNotice.reps, 0, "while the menu runs")
    tick()
    eq(NativeLoaderUnsubscribedNotice.Verdict(), "subscribed")
    assert(not card(), "no card for a subscribed account")
elseif scenario == "not-subscribed" then
    addons = list("111", "222")
    run()
    tick()
    eq(NativeLoaderUnsubscribedNotice.Verdict(), nil, "a list seen once is not trusted yet")
    tick()
    eq(NativeLoaderUnsubscribedNotice.Verdict(), "not subscribed")
    local shown = card()
    assert(shown, "the card is shown")
    local text = paintAll()
    assert(text:find("RTX Remix is not subscribed on this Steam account", 1, true), text)
    assert(text:find("(Workshop item 3829070317)", 1, true), "the item is named: " .. text)
    assert(button("Don't show this again"), "a way to keep it off")
    button("OK").DoClick()
    assert(not card(), "OK closes it")
    tick(3)
    assert(not card(), "shown once per start")
    assert(logs[1]:find("3829070317: not subscribed", 1, true), logs[1])
elseif scenario == "waits-for-the-list" then
    addons = {}
    run()
    tick(5)
    eq(NativeLoaderUnsubscribedNotice.Verdict(), nil, "an empty list is not known yet")
    assert(not card())
    addons = list("3829070317")
    hooks["WorkshopSubscriptionsChanged/NativeLoaderUnsubscribedNotice"]()
    tick()
    eq(NativeLoaderUnsubscribedNotice.Verdict(), "subscribed")
elseif scenario == "growing-list" then
    addons = list("111")
    run()
    tick()
    addons = list("111", "222")
    tick()
    eq(NativeLoaderUnsubscribedNotice.Verdict(), nil, "a list still growing is not trusted")
    addons = list("111", "222", "3829070317")
    tick()
    eq(NativeLoaderUnsubscribedNotice.Verdict(), "subscribed", "the item was in the full list")
    assert(not card())
elseif scenario == "steam-says-subscribed" then
    addons = list("111")
    steamworks.IsSubscribed = function(id) return id == "3829070317" end
    run()
    tick(3)
    eq(NativeLoaderUnsubscribedNotice.Verdict(), "subscribed", "steamworks.IsSubscribed is a second opinion")
elseif scenario == "dismissed" then
    cookies["nativeloader.unsubscribed-notice"] = "dismissed"
    addons = list("111")
    run()
    tick(3)
    eq(NativeLoaderUnsubscribedNotice.Verdict(), "not subscribed")
    assert(not card(), "Don't show this again holds")
    commands.nativeloader_unsubscribed_notice()
    assert(card(), "the console command shows it anyway")
    button("OK").DoClick()
    commands.nativeloader_unsubscribed_notice_reset()
    eq(cookies["nativeloader.unsubscribed-notice"], "watching")
elseif scenario == "dismiss-button" then
    addons = list("111")
    run()
    tick(2)
    button("Don't show this again").DoClick()
    eq(cookies["nativeloader.unsubscribed-notice"], "dismissed")
    assert(not card())
elseif scenario == "resubscribed" then
    addons = list("111")
    run()
    tick(2)
    eq(NativeLoaderUnsubscribedNotice.Verdict(), "not subscribed")
    button("OK").DoClick()
    addons = list("111", "3829070317")
    hooks["WorkshopSubscriptionsChanged/NativeLoaderUnsubscribedNotice"]()
    tick()
    eq(NativeLoaderUnsubscribedNotice.Verdict(), "subscribed")
    assert(not card())
elseif scenario == "local-source" then
    status.packages[1].source = "local"
    status.packages[1].label = "garrysmod/addons/rtx.gma"
    addons = list("111")
    run()
    eq(NativeLoaderUnsubscribedNotice.Item(), nil)
    assert(not timers.NativeLoaderUnsubscribedNotice, "nothing to watch for a local source")
    assert(not hooks["WorkshopSubscriptionsChanged/NativeLoaderUnsubscribedNotice"])
elseif scenario == "no-status" then
    status = nil
    addons = list("111")
    run()
    eq(NativeLoaderUnsubscribedNotice.Item(), nil)
    assert(not timers.NativeLoaderUnsubscribedNotice)
elseif scenario == "translation" then
    convars.gmod_language = "ja"
    addons = list("111")
    run()
    tick(2)
    local text = paintAll()
    assert(text:find("JA-TITLE", 1, true), text)
    assert(text:find("JA-ITEM 3829070317", 1, true), "the item in the translated text: " .. text)
    assert(button("JA-OK"))
elseif scenario == "failure" then
    failBuild = true
    addons = list("111")
    run()
    tick(2)
    eq(NativeLoaderUnsubscribedNotice.Verdict(), "not subscribed")
    assert(logs[#logs]:find("unsubscribed notice failed", 1, true), logs[#logs])
elseif scenario == "switched-off" then
    -- ADR 0189: switched off in Steam for this account. GMod hides the item (not in its list), which is no unsubscribe:
    -- written into GMod's list the loader reads, said on a card.
    addons = list("111", "222")
    steamAnswer = "disabled"
    run()
    tick(3)
    eq(NativeLoaderUnsubscribedNotice.Switch(), "disabled")
    eq(NativeLoaderUnsubscribedNotice.Verdict(), nil, "not judged as unsubscribed")
    eq(#listCalls, 1, "written once")
    eq(listCalls[1], true)
    eq(NativeLoaderUnsubscribedNotice.TurnedOff(), true)
    local text = paintAll()
    assert(text:find("RTX Remix is turned off", 1, true), text)
    assert(text:find("(Workshop item 3829070317) is switched off in Steam for this Steam account", 1, true), text)
    assert(text:find("switch it on again in Steam, enable it in GMod's Addons list", 1, true), text)
    assert(not text:find("not subscribed", 1, true), "never the unsubscribed card: " .. text)
    assert(not pcall(button, "Don't show this again"), "no dismissal: it happens once")
    button("OK").DoClick()
    tick(2)
    assert(not card(), "shown once")
    local said = table.concat(logs, " | ")
    assert(said:find("3829070317: disabled in Steam for this account", 1, true), said)
    assert(said:find("turned off: added in garrysmod/cfg/addonnomount.txt", 1, true), said)
elseif scenario == "switched-on-again" then
    addons = list("111")
    steamAnswer = "disabled"
    run()
    tick()
    eq(NativeLoaderUnsubscribedNotice.TurnedOff(), true)
    assert(card())
    steamAnswer = "enabled"  -- switched on again in Steam before the restart
    addons = list("111", "3829070317")
    tick()
    eq(#listCalls, 2)
    eq(listCalls[2], false, "its own entry taken out again")
    eq(NativeLoaderUnsubscribedNotice.TurnedOff(), false)
    assert(not card(), "the card goes")
    tick(2)
    eq(#listCalls, 2, "nothing more while it stays on")
    eq(NativeLoaderUnsubscribedNotice.Verdict(), "subscribed")
elseif scenario == "gmod-list-disable" then
    -- Disabled in GMod's own Addons list: GMod writes cfg/addonnomount.txt itself (measured), nothing to do.
    addons = list("3829070317")
    steamAnswer = "enabled"
    steamworks.ShouldMountAddon = function() return false end
    run()
    tick(3)
    eq(#listCalls, 0)
    assert(not card())
    eq(NativeLoaderUnsubscribedNotice.Verdict(), "subscribed")
elseif scenario == "turn-off-failed" then
    addons = list("111")
    steamAnswer = "disabled"
    listAnswer = function() return nil, "garrysmod/cfg/addonnomount.txt is not GMod's list of disabled add-ons" end
    run()
    tick()
    eq(NativeLoaderUnsubscribedNotice.TurnedOff(), false)
    local text = paintAll()
    assert(text:find("RTX Remix is switched off in Steam", 1, true), text)
    assert(text:find("could not be turned off (garrysmod/cfg/addonnomount.txt is not GMod", 1, true), text)
    button("OK").DoClick()
    tick(2)
    assert(not card(), "said once, not at every check")
elseif scenario == "no-list-api" then
    noListApi = true
    addons = list("111")
    steamAnswer = "disabled"
    run()
    tick()
    local text = paintAll()
    assert(text:find("cannot change GMod's add-on list", 1, true), text)
elseif scenario == "no-steam-state" then
    -- A module that cannot read Steam's list (or none): the unsubscribed notice as before.
    noSteamApi = true
    addons = list("111")
    run()
    tick(2)
    eq(NativeLoaderUnsubscribedNotice.Switch(), nil)
    eq(NativeLoaderUnsubscribedNotice.Verdict(), "not subscribed")
    assert(card(), "the unsubscribed card")
    eq(#listCalls, 0)
elseif scenario == "addon-state" then
    addons = list("111", "3829070317")
    -- Takes the id only as a number, as GMod's menu passes it.
    steamworks.ShouldMountAddon = function(id)
        if type(id) ~= "number" then error("bad argument #1 (number expected)") end
        return tostring(id) == "111"
    end
    run()
    commands.nativeloader_addon_state(nil, nil, { "111" })
    assert(logs[#logs]:find("addon state 111: listed true; mounted true; ShouldMountAddon true", 1, true), logs[#logs])
    commands.nativeloader_addon_state(nil, nil, {})
    assert(logs[#logs]:find("addon state 3829070317: listed true; mounted false; ShouldMountAddon false", 1, true), logs[#logs])
elseif scenario == "not-menu" then
    run(false)
    eq(NativeLoaderUnsubscribedNotice, nil)
else
    error("unknown scenario " .. tostring(scenario))
end
print("PASS " .. scenario)
