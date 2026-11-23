-- Runs the companion's real nativeloader/menu/disk_space.lua (ADR 0260) in a mocked menu realm: the loader's start-up
-- report, the RTX client module's disk_space, timers, cookies, console commands, Derma. Usage:
-- luajit <this> <repo> <scenario>. See the adjacent .md.
local root, scenario = ...
local SCRIPT = root .. "/companion/nativeloader/lua/nativeloader/menu/disk_space.lua"
local MIB = 1048576

local cookies, convars, logs, panels, timers, commands = {}, { gmod_language = "en" }, {}, {}, {}, {}
local status, space, noSpaceApi, spaceCalls = nil, nil, false, 0

local function eq(a, b, what) if a ~= b then error((what or "value") .. ": expected " .. tostring(b) .. ", got " .. tostring(a), 2) end end
local function has(text, part, what)
    if not tostring(text):find(part, 1, true) then error((what or "text") .. ": no '" .. part .. "' in: " .. tostring(text), 2) end
end
local function hasnt(text, part, what)
    if tostring(text):find(part, 1, true) then error((what or "text") .. ": unexpected '" .. part .. "' in: " .. tostring(text), 2) end
end

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
local screenW, screenH = 1920, 1080
function ScrW() return screenW end
function ScrH() return screenH end
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
timer = {
    Create = function(name, delay, reps, fn) timers[name] = { delay = delay, reps = reps, fn = fn } end,
    Remove = function(name) timers[name] = nil end,
}
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
function Panel:SetKeyboardInputEnabled() end
function Panel:SetFont(f) self.font = f end
function Panel:SetText(t) self.text = t end
function Panel:SetTextColor() end
function Panel:IsHovered() return false end
function Panel:RequestFocus() self.focused = true end
function Panel:Remove() self.removed = true end
vgui = { Create = function(class, parent)
    local panel = setmetatable({ class = class, parent = parent }, Panel)
    panels[#panels + 1] = panel
    return panel
end }
local function alive(p)
    while p do
        if p.removed then return false end
        p = p.parent
    end
    return true
end
local function card() for _, p in ipairs(panels) do if p.popup and alive(p) then return p end end end
-- Everything the open card draws, in order; its wrapped lines joined by a space again. raw keeps the no-break spaces
-- the sizes carry; otherwise they read as spaces.
local function text(raw)
    drawn = {}
    for _, p in ipairs(panels) do if p.Paint and alive(p) then p.Paint(p, 100, 100) end end
    local joined = table.concat(drawn, " ")
    return raw and joined or (string.gsub(joined, "\194\160", " "))
end
local function buttons()
    local out = {}
    for _, p in ipairs(panels) do if p.class == "DButton" and alive(p) then out[#out + 1] = p.text end end
    return table.concat(out, ",")
end
local function button(label)
    for _, p in ipairs(panels) do if p.class == "DButton" and p.text == label and alive(p) then return p end end
    error("no button " .. label)
end

local catalogSource
local function run(menu)
    MENU_DLL = menu ~= false
    NativeLoaderDiskSpace = nil
    panels, timers, commands, logs = {}, {}, {}, {}
    __NATIVELOADER_MENU_API = { read = function(name)
        if name == "nativeloader/nativeloader/i18n_data.lua" then return catalogSource end
    end }
    if not noSpaceApi then
        __NATIVELOADER_MENU_API.disk_space = function()
            spaceCalls = spaceCalls + 1
            if space == nil then return nil, "Windows cannot tell the free space (error 3)" end
            return space
        end
    end
    dofile(SCRIPT)
    __NATIVELOADER_MENU_API = nil
end
-- The menu's first ticks: the card waits for a usable screen.
local function tick(times)
    for _ = 1, times or 1 do
        local t = timers.NativeLoaderDiskSpace
        if t then t.fn() end
    end
end

-- The loader's own words (loader/core/src/deploy.cpp ensure_space; fs.cpp fail()).
local NEED = "not enough free disk space: the new files need 2300 MiB and 64 MiB should stay free, but only 1500 MiB are free"
local FULL = "cannot write C:\\Games\\GarrysMod\\native-loader\\staging\\81\\0\\payload\\runtime\\d3d9.dll (Windows error 112)"
local function report(outcome, reason, folder)
    return { schema = 1, deployment = { outcome = outcome, reason = reason or "" },
             activation = { outcome = "active", runtime = { folder = folder or "D:\\Steam\\steamapps\\common\\GarrysMod\\native-loader\\packages\\gmod-rtx-remix\\1_2" } } }
end
local function drive(available, packages)
    return { available = available, total = 1000000 * MIB, drive = "h:", packages = packages }
end
local PACKAGES = { { id = "gmod-rtx-remix", payload = 1393 * MIB, files = 820 * MIB }, { id = "map-pack", payload = 0, files = 3700 * MIB } }

if scenario == "failed_need" then
    -- The loader's check refused the start's updates: what it needed, what was free, how much to free.
    status, space = report("failed", NEED), drive(1600 * MIB, PACKAGES)
    run()
    eq(card(), nil, "a card before the menu is up")
    has(logs[1], "last deployment failed (disk space: need)", "console line")
    screenW, screenH = 320, 200
    tick()
    eq(card(), nil, "a card on a screen too small for it")
    screenW, screenH = 1920, 1080
    tick()
    local shown = text()
    has(shown, "Not enough disk space to install updates", "title")
    -- 2300 MiB needed (2.3 GB, up), 64 MB kept, 1500 MiB free (1.5 GB), on drive H: (the module's, upper case).
    has(shown, "needed 2.3 GB free on drive H:", "need")
    has(shown, "keeps another 64 MB free, but only 1.5 GB were free", "spare and free")
    has(shown, "Nothing was changed", "kept")
    -- 2300 + 64 - 1500 + 512 (the game's room) = 1376 MiB: 1.4 GB, rounded up.
    has(shown, "Free at least 1.4 GB on drive H:, then restart the game", "how much")
    -- A size's number and unit are held together by a no-break space, never broken across lines.
    has(text(true), "needed 2.3\194\160GB free", "a size's no-break space")
    hasnt(text(true), "2.3 GB", "a size with a breaking space")
    eq(buttons(), "OK", "a failure card has no way to stop it")
    eq(timers.NativeLoaderDiskSpace, nil, "the timer outlived the card")
    button("OK").DoClick()
    eq(card(), nil, "OK did not close the card")
elseif scenario == "failed_full" then
    -- The drive filled while the loader unpacked: the card says so; how much to free comes from the module.
    status, space = report("failed", FULL), drive(500 * MIB, PACKAGES)
    run()
    tick()
    local shown = text()
    has(shown, "drive H: ran out of space while the RTX Remix loader unpacked", "full")
    has(shown, "Nothing was changed", "kept")
    -- The largest package, 3700 MiB, + 64 + 512 - 500 free = 3776 MiB: 3.7 GB, rounded up.
    has(shown, "Free at least 3.7 GB on drive H:", "how much")
    hasnt(shown, "C:\\Games", "the loader's path")
    -- Error 39 (a handle's disk full) is the same.
    status = report("failed", "cannot write X (Windows error 39); the change was undone")
    run()
    tick()
    has(text(), "ran out of space", "error 39")
    -- Another wording of the check: the generic card.
    status = report("failed", "not enough free disk space for this")
    run()
    tick()
    local generic = text()
    has(generic, "Free some space on drive H:", "generic")
    hasnt(generic, "ran out of space", "generic")
elseif scenario == "low" then
    -- Before it happens: less free than the largest package would need to unpack again.
    status, space = report("deployed"), drive(2000 * MIB, PACKAGES)
    run()
    has(logs[1], "largest package map-pack: 3700 MiB; wanted free 4276 MiB", "console line")
    tick()
    local shown = text()
    has(shown, "Little free disk space for updates", "title")
    has(shown, "Drive H: has 2.0 GB free", "free")
    has(shown, "the largest of them needs up to 3.7 GB at once", "largest, rounded up")
    -- 3700 + 64 + 512 - 2000 = 2276 MiB: 2.3 GB.
    has(shown, "Free at least 2.3 GB on drive H: so that updates can be installed", "how much")
    eq(buttons(), "OK,Don't show this again", "buttons")
    button("Don't show this again").DoClick()
    eq(card(), nil, "the card stayed")
    eq(cookies["nativeloader.disk-space-notice"], "dismissed", "the choice was not kept")
    -- The next start: nothing, though the space is as low; the command still shows it.
    run()
    tick()
    eq(card(), nil, "a dismissed warning came back")
    commands.nativeloader_disk_space()
    has(text(), "Little free disk space", "the command")
    has(logs[#logs], "card: low", "the command's line")
    -- A failure is never dismissed.
    status = report("failed", NEED)
    run()
    tick()
    has(text(), "Not enough disk space to install updates", "a failure after dismissing the warning")
    commands.nativeloader_disk_space_reset()
    eq(cookies["nativeloader.disk-space-notice"], "watching", "reset")
elseif scenario == "enough" then
    -- Room for the largest package: no card, no timer kept; the status command prints the numbers.
    status, space = report("deployed"), drive(50 * 1024 * MIB, PACKAGES)
    run()
    tick(3)
    eq(card(), nil, "a card with enough space")
    commands.nativeloader_disk_space_status()
    has(logs[#logs], "drive H: has 51200 MiB free of 1000000 MiB", "status")
    has(logs[#logs], "last deployment deployed", "status")
    commands.nativeloader_disk_space()
    eq(card(), nil, "the command made a card with enough space")
    has(logs[#logs], "no card: there is space for updates", "the command's line")
    -- Exactly what is wanted is enough; one MiB less is not.
    space = drive((3700 + 64 + 512) * MIB, PACKAGES)
    run()
    tick()
    eq(card(), nil, "a card at exactly the space wanted")
    space = drive((3700 + 64 + 512 - 1) * MIB, PACKAGES)
    run()
    tick()
    has(text(), "Little free disk space", "one MiB short")
    -- No packages listed (a fresh generation without sizes): nothing to warn about.
    space = drive(10 * MIB, {})
    run()
    tick()
    eq(card(), nil, "a card without package sizes")
elseif scenario == "old_module" then
    -- An RTX client module without disk_space: no warning, but a failure still shows, its drive from the report.
    noSpaceApi = true
    status = report("deployed")
    run()
    eq(timers.NativeLoaderDiskSpace, nil, "a timer with nothing to show")
    eq(#logs, 0, "a line with nothing to say")
    status = report("failed", NEED, "E:\\SteamLibrary\\steamapps\\common\\GarrysMod\\native-loader\\packages\\gmod-rtx-remix\\9_9")
    run()
    tick()
    local shown = text()
    has(shown, "needed 2.3 GB free on drive E:", "the report's drive")
    commands.nativeloader_disk_space_status()
    has(logs[#logs], "free space unknown (this RTX client module does not measure disk space)", "status")
    -- A module whose measurement fails: the same, and why.
    noSpaceApi = false
    space = nil
    status = report("failed", FULL)
    run()
    tick()
    has(text(), "Free some space on drive D:", "no measurement")
    eq(spaceCalls > 0, true, "disk_space was not asked")
elseif scenario == "unrelated" then
    -- A deployment that failed for another reason, or no report at all: no card.
    space = drive(50 * 1024 * MIB, PACKAGES)
    for _, reason in ipairs({ "another deployment is running in this folder", "Garry's Mod is running from this folder; close it first",
                              "cannot open X (Windows error 5)" }) do
        status = report("failed", reason)
        run()
        tick()
        eq(card(), nil, "a card for: " .. reason)
    end
    status = nil
    run()
    tick()
    eq(card(), nil, "a card without a report")
    -- Outside the menu realm nothing runs.
    status = report("failed", NEED)
    run(false)
    eq(NativeLoaderDiskSpace, nil, "ran outside the menu")
    eq(card(), nil, "a card outside the menu")
elseif scenario == "preview" then
    -- The sample cards for a look at their layout: each shows, and the real state is left as it was.
    status, space = report("deployed"), drive(50 * 1024 * MIB, PACKAGES)
    run()
    tick()
    eq(card(), nil, "a card with enough space")
    commands.nativeloader_disk_space_preview(nil, nil, {})
    has(text(), "needed 2.3 GB free on drive H:", "need sample")
    has(logs[#logs], "preview of the need card (sample numbers): failed", "need line")
    commands.nativeloader_disk_space_preview(nil, nil, { "full" })
    has(text(), "drive H: ran out of space", "full sample")
    -- 3700 + 64 + 512 - 2000 = 2276 MiB: 2.3 GB, rounded up.
    has(text(), "Free at least 2.3 GB on drive H:", "full sample's amount")
    commands.nativeloader_disk_space_preview(nil, nil, { "low" })
    has(text(), "Drive H: has 2.0 GB free", "low sample")
    eq(NativeLoaderDiskSpace.Failure(), nil, "the sample failure stayed")
    eq(NativeLoaderDiskSpace.Measured().available, 50 * 1024 * MIB, "the sample measure stayed")
    commands.nativeloader_disk_space()
    has(logs[#logs], "no card: there is space for updates", "the real state after the samples")
elseif scenario == "translations" then
    -- The player's language from the companion's catalog: titles, paragraphs, units and buttons.
    convars.gmod_language = "ja"
    catalogSource = 'return { ja = { ["Little free disk space for updates"] = "JA-LOW", ' ..
        '["%s GB"] = "%s JA-GB", ["%s MB"] = "%s JA-MB", ["OK"] = "JA-OK", ' ..
        '["Free at least %s on drive %s so that updates can be installed."] = "JA-HOW %s %s" } }'
    status, space = report("deployed"), drive(2000 * MIB, PACKAGES)
    run()
    tick()
    local shown = text()
    has(shown, "JA-LOW", "title")
    has(shown, "JA-HOW 2.3 JA-GB H:", "paragraph with translated units")
    has(buttons(), "JA-OK", "button")
    -- Untranslated text stays English.
    has(shown, "With less free space than that", "fallback")
else
    error("unknown scenario " .. tostring(scenario))
end
print("PASS " .. scenario)
