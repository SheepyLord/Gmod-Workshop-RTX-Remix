-- A note on the main menu of an RTX start (ADR 0217, ADR 0219): more PBR resources for maps are in SheepyLord's RTX
-- Remix collection on the Steam Workshop. A small panel at the top right of the main menu, hidden while a map loads or
-- runs: a title, one line and three buttons. "Open the collection" opens it, "Hide" hides the note until the next start
-- and "Don't show again" for good. The note hides itself 10 seconds after it appears; the time stops while the pointer
-- is over it. The RTX client module (gmsv_nlrtxclient) runs this once in the menu realm of an RTX start (ADR 0133).
-- Edit the English text below; its translations are in companion/i18n/<language>.po. Documented in pbr_note.lua.md.
if not MENU_DLL or NativeLoaderPbrNote then return end

local api = rawget(_G, "__NATIVELOADER_MENU_API")
local read = istable(api) and isfunction(api.read) and api.read or nil
local function N(text) return text end

-- SheepyLord's collection of RTX Remix resources: the RTX package, PBR packs for maps, and more.
local COLLECTION = "3834474695"
local URL = "https://steamcommunity.com/sharedfiles/filedetails/?id=" .. COLLECTION
local SHOWN_SECONDS = 10

local TEXT = {
    title = N"Obtaining more PBR resources",
    short = N"Demo PBR packs for maps are in SheepyLord's RTX Remix collection on the Workshop.",
    open = N"Open the collection",
    hide = N"Hide",
    never = N"Don't show again",
}

local COOKIE = "nativeloader.pbr-note"

local ALIASES = { zh = "zh-CN", ["zh-cn"] = "zh-CN", ["zh-tw"] = "zh-TW" }
local catalog
-- As the other menu notices: the companion's language is a client convar the menu realm cannot see, so the companion
-- keeps a copy in data/nativeloader_companion/language.txt (nativeloader/i18n.lua).
local function language()
    local chosen = GetConVar("nativeloader_language")
    local code = chosen and chosen:GetString() or ""
    if code == "" then
        local saved = file and isfunction(file.Read) and file.Read("nativeloader_companion/language.txt", "DATA")
        if isstring(saved) and #saved <= 16 and saved:match("^[%w%-]+$") then code = saved end
    end
    if code == "" then
        local gmod = GetConVar("gmod_language")
        code = gmod and gmod:GetString() or "en"
    end
    return ALIASES[string.lower(code)] or code
end
-- The menu realm has no CompileString (PoC, R24), only RunString: the table goes through a global taken at once.
local function loadCatalog(source)
    if isfunction(CompileString) then
        local chunk = CompileString(source, "nativeloader/i18n_data.lua", false)
        local ok, data = false, nil
        if isfunction(chunk) then ok, data = pcall(chunk) end
        return ok and istable(data) and data or nil
    end
    if not isfunction(RunString) then return nil end
    local key = "__NATIVELOADER_I18N_DATA"
    rawset(_G, key, nil)
    pcall(RunString, key .. " = (function()\n" .. source .. "\nend)()", "nativeloader/i18n_data.lua", false)
    local data = rawget(_G, key)
    rawset(_G, key, nil)
    return istable(data) and data or nil
end
local cachedLanguage -- the language the last look found (update below); nil before it
local function L(text)
    local code = cachedLanguage or language()
    if code == "en" or code == "" then return text end
    if catalog == nil then
        catalog = false
        local source = read and read("nativeloader/nativeloader/i18n_data.lua")
        if isstring(source) then catalog = loadCatalog(source) or false end
    end
    local phrases = catalog and catalog[code]
    local translated = istable(phrases) and phrases[text]
    return isstring(translated) and translated ~= "" and translated or text
end

local state = cookie.GetString(COOKIE, "") == "dismissed" and "dismissed" or "shown"
local hidden = false -- "Hide" or the 10 seconds: until the next start
local note -- the panel while it exists
local failed = false -- a build failed once: said in the console, not tried again
local builtFor -- the screen size and language the note was built for
local shownFor, lastFrame = 0, nil -- seconds the note has been up without the pointer over it

-- Opens the collection. gui.OpenURL uses the Steam overlay, and with the overlay off the engine opens GMod's own browser
-- window (GMOD_OpenURLNoOverlay, lua/menu/openurl.lua); steamworks.ViewFile shows nothing at all without the overlay.
local function openCollection()
    MsgN("[nativeloader] PBR note: opening " .. URL)
    if istable(gui) and isfunction(gui.OpenURL) and pcall(gui.OpenURL, URL) then return "url" end
    if istable(steamworks) and isfunction(steamworks.ViewFile) and pcall(steamworks.ViewFile, COLLECTION) then
        return "overlay"
    end
    return "console"
end

local function scale() return math.max(0.65, ScrH() / 1080) end
-- Lines broken at spaces, and between any two characters of a script written without them (CJK).
local function wrap(text, font, wide)
    surface.SetFont(font)
    local tokens, word = {}, ""
    for _, code in utf8.codes(text) do
        local char = utf8.char(code)
        if code == 32 then
            tokens[#tokens + 1] = word .. " "
            word = ""
        elseif code >= 0x2E80 then
            if word ~= "" then tokens[#tokens + 1] = word end
            tokens[#tokens + 1] = char
            word = ""
        else
            word = word .. char
        end
    end
    if word ~= "" then tokens[#tokens + 1] = word end
    local lines, line = {}, ""
    for _, token in ipairs(tokens) do
        local candidate = line .. token
        if line ~= "" and surface.GetTextSize(string.TrimRight(candidate)) > wide then
            lines[#lines + 1] = string.TrimRight(line)
            line = string.TrimLeft(token)
        else
            line = candidate
        end
    end
    if line ~= "" then lines[#lines + 1] = string.TrimRight(line) end
    return lines
end

-- Tahoma with `extended`, as the other notices: Windows then supplies the other languages' glyphs.
local function fonts(px)
    local function font(name, size, weight)
        surface.CreateFont(name, { font = "Tahoma", size = px(size), weight = weight, antialias = true, extended = true })
    end
    font("NativeLoaderPbrNoteTitle", 20, 800)
    font("NativeLoaderPbrNoteText", 16, 500)
    font("NativeLoaderPbrNoteButton", 16, 800)
end

-- A text block of wrapped lines at (x, y) in `parent`; returns its height.
local function label(parent, text, font, x, y, wide, color)
    local lines = wrap(text, font, wide)
    surface.SetFont(font)
    local _, lineTall = surface.GetTextSize("Ag")
    local panel = vgui.Create("DPanel", parent)
    panel:SetPos(x, y)
    panel:SetSize(wide, lineTall * #lines)
    panel.Paint = function()
        for i, value in ipairs(lines) do draw.SimpleText(value, font, 0, (i - 1) * lineTall, color) end
    end
    return panel:GetTall()
end

local function button(parent, text, font, x, y, tall, maxWide, colors, px, action)
    surface.SetFont(font)
    local wide = math.min(maxWide, select(1, surface.GetTextSize(text)) + px(32))
    local panel = vgui.Create("DButton", parent)
    panel:SetFont(font)
    panel:SetText(text)
    panel:SetTextColor(Color(255, 255, 255))
    panel:SetPos(x, y)
    panel:SetSize(wide, tall)
    panel.Paint = function(self, bw, bh)
        draw.RoundedBox(px(5), 0, 0, bw, bh, colors[3])
        draw.RoundedBox(px(4), px(2), px(2), bw - px(4), bh - px(4), self:IsHovered() and colors[2] or colors[1])
    end
    panel.DoClick = action
    return panel
end

local BLUE = { Color(38, 72, 103), Color(52, 98, 140), Color(138, 177, 215) }
local GREY = { Color(48, 52, 60), Color(70, 76, 88), Color(120, 128, 140) }

local function close()
    if IsValid(note) then note:Remove() end
    note = nil
end

-- The note: a small panel at the top right of the main menu, as wide as its one line needs. It takes mouse clicks, never
-- the keyboard.
local function buildNote()
    local s = scale()
    local function px(n) return math.floor(n * s + 0.5) end
    fonts(px)
    local pad, gap = px(14), px(8)
    local title, short = L(TEXT.title), L(TEXT.short)
    local labels = { L(TEXT.open), L(TEXT.hide), L(TEXT.never) }
    -- One line of text where the screen allows it: the note is as wide as its widest part.
    surface.SetFont("NativeLoaderPbrNoteTitle")
    local need = select(1, surface.GetTextSize(title))
    surface.SetFont("NativeLoaderPbrNoteText")
    need = math.max(need, select(1, surface.GetTextSize(short)))
    surface.SetFont("NativeLoaderPbrNoteButton")
    local row = 0
    for i, text in ipairs(labels) do row = row + select(1, surface.GetTextSize(text)) + px(32) + (i > 1 and gap or 0) end
    local width = math.min(ScrW() - px(24), math.max(px(320), need, row) + pad * 2)
    local panel = vgui.Create("DPanel")
    panel:SetWide(width)
    panel.Paint = function(_, w, h)
        draw.RoundedBox(px(6), 0, 0, w, h, Color(70, 142, 208, 235))
        draw.RoundedBox(px(5), px(2), px(2), w - px(4), h - px(4), Color(22, 35, 51, 235))
    end
    local y = px(12)
    local white = Color(237, 244, 255)
    y = y + label(panel, title, "NativeLoaderPbrNoteTitle", pad, y, width - pad * 2, white) + px(6)
    y = y + label(panel, short, "NativeLoaderPbrNoteText", pad, y, width - pad * 2, Color(200, 214, 232)) + px(10)
    local x, tall = pad, px(30)
    local function place(text, colors, action)
        surface.SetFont("NativeLoaderPbrNoteButton")
        local wide = select(1, surface.GetTextSize(text)) + px(32)
        if x > pad and x + wide > width - pad then
            x = pad
            y = y + tall + gap
        end
        local made = button(panel, text, "NativeLoaderPbrNoteButton", x, y, tall, width - pad * 2, colors, px, action)
        x = x + made:GetWide() + gap
        return made
    end
    place(labels[1], BLUE, function() openCollection() end)
    place(labels[2], GREY, function()
        hidden = true
        close()
    end)
    place(labels[3], GREY, function()
        state = "dismissed"
        cookie.Set(COOKIE, state)
        close()
    end)
    panel:SetTall(y + tall + px(12))
    panel:SetPos(ScrW() - width - px(16), px(16))
    panel:MakePopup()
    panel:SetKeyboardInputEnabled(false)
    return panel
end

-- Shown on the main menu only: not while a map loads or runs (the escape menu over a game is the same menu).
local function wanted()
    return state ~= "dismissed" and not hidden and not failed and not IsInGame() and not IsInLoading()
end

-- The pointer is over the note or one of its buttons.
local function pointed()
    local over = isfunction(vgui.GetHoveredPanel) and vgui.GetHoveredPanel() or nil
    while IsValid(over) do
        if over == note then return true end
        over = isfunction(over.GetParent) and over:GetParent() or nil
    end
    return false
end

-- Every frame only the cheap part: is the note wanted, and its time. The screen size and the language (a file read when
-- the companion's convar is empty) are looked at every two seconds, and the note is rebuilt when either changed.
local nextLook = 0
local function update()
    local now = SysTime()
    local step = lastFrame and math.min(math.max(now - lastFrame, 0), 0.5) or 0
    lastFrame = now
    if not wanted() then
        close()
        return
    end
    if IsValid(note) and not pointed() then
        shownFor = shownFor + step
        if shownFor >= SHOWN_SECONDS then
            hidden = true
            close()
            return
        end
    end
    if now < nextLook then return end
    nextLook = now + 2
    if ScrW() < 640 or ScrH() < 360 then return end
    cachedLanguage = language()
    local key = ScrW() .. "x" .. ScrH() .. "/" .. cachedLanguage
    if IsValid(note) then
        if builtFor == key then return end
        close()
    end
    local ok, result = pcall(buildNote)
    if ok then
        note, builtFor = result, key
    else
        failed = true
        MsgN("[nativeloader] PBR note failed: " .. tostring(result))
    end
end

NativeLoaderPbrNote = {}
function NativeLoaderPbrNote.State() return state, hidden end
function NativeLoaderPbrNote.Shown() return IsValid(note) end
NativeLoaderPbrNote.Update = update

-- Each frame costs a few comparisons: the panel is built once and kept while it is wanted.
hook.Add("Think", "NativeLoaderPbrNote", update)

if concommand and concommand.Add then
    concommand.Add("nativeloader_pbr_note", function()
        if state == "dismissed" then return end
        hidden, shownFor, nextLook = false, 0, 0
    end, nil, "Show the main menu's note on PBR resources again, for another 10 seconds")
    concommand.Add("nativeloader_pbr_note_reset", function()
        state, hidden, failed, shownFor, nextLook = "shown", false, false, 0, 0
        cookie.Set(COOKIE, state)
    end, nil, "Show the main menu's PBR note again after \"Hide\" or \"Don't show again\"")
end
