-- A note on the main menu of an RTX start (ADR 0217): demo PBR resources for maps are in SheepyLord's RTX Remix
-- collection on the Steam Workshop, and what a map without PBR materials looks like under RTX Remix. A small panel at the
-- top right of the main menu, hidden while a map loads or runs. "Maps without PBR" opens a card with the explanation,
-- "Hide" hides the note until the next start, and the card's "Don't show the note again" hides it for good.
-- The RTX client module (gmsv_nlrtxclient) runs this once in the menu realm of an RTX start (ADR 0133). Edit the
-- English text below; its translations are in companion/i18n/<language>.po. Documented in pbr_note.lua.md.
if not MENU_DLL or NativeLoaderPbrNote then return end

local api = rawget(_G, "__NATIVELOADER_MENU_API")
local read = istable(api) and isfunction(api.read) and api.read or nil
local function N(text) return text end

-- SheepyLord's collection of RTX Remix resources: the RTX package, PBR packs for maps, and more.
local COLLECTION = "3834474695"
local URL = "https://steamcommunity.com/sharedfiles/filedetails/?id=" .. COLLECTION

local TEXT = {
    title = N"PBR materials for maps",
    short = N"Maps look their best in RTX Remix with PBR materials. Demo PBR resources are in SheepyLord's RTX Remix collection on the Steam Workshop.",
    open = N"Open the collection",
    expect = N"Maps without PBR",
    hide = N"Hide",
    cardTitle = N"What to expect on a map without PBR",
    everywhere = N"RTX Remix path traces every map, with or without PBR: sunlight, lamps, shadows, reflections, glass, water and the sky are real on all of them.",
    flat = N"A map without PBR materials keeps its original textures, which hold only colour. Without roughness, normal and metal maps its surfaces are lit as if smooth and evenly matte or glossy, so walls and floors can look flat, metal can look like painted plastic, and shine or shadows painted into old textures can look doubled.",
    topbr = N"ToPBR (Utilities, RTX Remix, ToPBR) can build approximate materials from what a map's own materials already reference, such as normal maps and specular masks. Real PBR packs look much better.",
    demo = N"For demo PBR resources, subscribe to the items you want in SheepyLord's RTX Remix collection (Workshop item %s), then restart Garry's Mod: RTX Remix installs them at the next start. Each pack improves the maps or models it was made for.",
    ok = N"OK",
    never = N"Don't show the note again",
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
local hidden = false -- "Hide": until the next start
local note, card -- the panels while they exist
local failed = false -- a build failed once: said in the console, not tried again
local builtFor -- the screen size and language the note was built for

-- Opens the collection in the Steam overlay, or in GMod's own browser when the overlay is off.
local function openCollection()
    if istable(steamworks) and isfunction(steamworks.ViewFile) and pcall(steamworks.ViewFile, COLLECTION) then
        return "overlay"
    end
    if istable(gui) and isfunction(gui.OpenURL) and pcall(gui.OpenURL, URL) then return "browser" end
    MsgN("[nativeloader] PBR note: the collection is at " .. URL)
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
    font("NativeLoaderPbrCardTitle", 27, 800)
    font("NativeLoaderPbrCardText", 19, 500)
    font("NativeLoaderPbrCardButton", 19, 800)
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

local function closeCard()
    if IsValid(card) then card:Remove() end
    card = nil
end

-- The card: what a map without PBR looks like, and where the demo resources are. Modal, as the other notices.
local function buildCard()
    local s = scale()
    local function px(n) return math.floor(n * s + 0.5) end
    fonts(px)
    local overlay = vgui.Create("DPanel")
    overlay:SetSize(ScrW(), ScrH())
    overlay:SetPos(0, 0)
    overlay:MakePopup()
    overlay:SetKeyboardInputEnabled(true)
    overlay.Paint = function(_, w, h) surface.SetDrawColor(0, 0, 0, 195) surface.DrawRect(0, 0, w, h) end

    local panel = vgui.Create("DPanel", overlay)
    local width = math.min(ScrW() - px(48), px(780))
    panel:SetWide(width)
    panel.Paint = function(_, w, h)
        draw.RoundedBox(px(8), 0, 0, w, h, Color(70, 142, 208))
        draw.RoundedBox(px(7), px(2), px(2), w - px(4), h - px(4), Color(22, 35, 51))
    end
    local pad, y = px(28), px(24)
    local white = Color(237, 244, 255)
    y = y + label(panel, L(TEXT.cardTitle), "NativeLoaderPbrCardTitle", pad, y, width - pad * 2, white) + px(16)
    for _, text in ipairs({ L(TEXT.everywhere), L(TEXT.flat), L(TEXT.topbr), string.format(L(TEXT.demo), COLLECTION) }) do
        y = y + label(panel, text, "NativeLoaderPbrCardText", pad, y, width - pad * 2, white) + px(12)
    end

    -- Buttons in a row, wrapping to a new row when the language's words are long.
    local x, tall = pad, px(44)
    local function place(text, colors, action)
        surface.SetFont("NativeLoaderPbrCardButton")
        local wide = select(1, surface.GetTextSize(text)) + px(32)
        if x > pad and x + wide > width - pad then
            x = pad
            y = y + tall + px(10)
        end
        local made = button(panel, text, "NativeLoaderPbrCardButton", x, y, tall, width - pad * 2, colors, px, action)
        x = x + made:GetWide() + px(12)
        return made
    end
    local primary = place(L(TEXT.ok), BLUE, closeCard)
    place(L(TEXT.open), BLUE, function() openCollection() end)
    place(L(TEXT.never), GREY, function()
        state = "dismissed"
        cookie.Set(COOKIE, state)
        closeCard()
    end)
    panel:SetTall(y + tall + px(24))
    panel:SetPos(math.floor((ScrW() - width) / 2), math.max(px(12), math.floor((ScrH() - panel:GetTall()) / 2)))
    overlay.OnKeyCodePressed = function(_, key)
        if key == KEY_ESCAPE or key == KEY_ENTER or key == KEY_PAD_ENTER then closeCard() end
    end
    primary:RequestFocus()
    return overlay
end

local function showCard()
    closeCard()
    local ok, result = pcall(buildCard)
    if ok then
        card = result
    else
        MsgN("[nativeloader] PBR note card failed: " .. tostring(result))
    end
end

-- The note: a small panel at the top right of the main menu. It takes mouse clicks, never the keyboard.
local function buildNote()
    local s = scale()
    local function px(n) return math.floor(n * s + 0.5) end
    fonts(px)
    local width = math.min(ScrW() - px(24), px(400))
    local panel = vgui.Create("DPanel")
    panel:SetWide(width)
    panel.Paint = function(_, w, h)
        draw.RoundedBox(px(6), 0, 0, w, h, Color(70, 142, 208, 235))
        draw.RoundedBox(px(5), px(2), px(2), w - px(4), h - px(4), Color(22, 35, 51, 235))
    end
    local pad, y = px(14), px(12)
    local white = Color(237, 244, 255)
    y = y + label(panel, L(TEXT.title), "NativeLoaderPbrNoteTitle", pad, y, width - pad * 2, white) + px(6)
    y = y + label(panel, L(TEXT.short), "NativeLoaderPbrNoteText", pad, y, width - pad * 2, Color(200, 214, 232)) + px(10)
    local x, tall = pad, px(30)
    local function place(text, colors, action)
        surface.SetFont("NativeLoaderPbrNoteButton")
        local wide = select(1, surface.GetTextSize(text)) + px(32)
        if x > pad and x + wide > width - pad then
            x = pad
            y = y + tall + px(8)
        end
        local made = button(panel, text, "NativeLoaderPbrNoteButton", x, y, tall, width - pad * 2, colors, px, action)
        x = x + made:GetWide() + px(8)
        return made
    end
    place(L(TEXT.open), BLUE, function() openCollection() end)
    place(L(TEXT.expect), BLUE, showCard)
    place(L(TEXT.hide), GREY, function()
        hidden = true
        if IsValid(note) then note:Remove() end
        note = nil
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

-- Every frame only the cheap part: is the note wanted. The screen size and the language (a file read when the companion's
-- convar is empty) are looked at every two seconds, and the note is rebuilt when either changed.
local nextLook = 0
local function update()
    if IsValid(card) and IsInLoading() then closeCard() end
    local want = wanted()
    if not want then
        if IsValid(note) then note:Remove() end
        note = nil
        return
    end
    local now = SysTime()
    if now < nextLook then return end
    nextLook = now + 2
    if ScrW() < 640 or ScrH() < 360 then return end
    cachedLanguage = language()
    local key = ScrW() .. "x" .. ScrH() .. "/" .. cachedLanguage
    if IsValid(note) then
        if builtFor == key then return end
        note:Remove()
        note = nil
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
    concommand.Add("nativeloader_pbr_note", function() showCard() end, nil,
        "Show the card about PBR materials for maps and the demo resources now")
    concommand.Add("nativeloader_pbr_note_reset", function()
        state, hidden, failed, nextLook = "shown", false, false, 0
        cookie.Set(COOKIE, state)
    end, nil, "Show the main menu's PBR note again after \"Hide\" or \"Don't show the note again\"")
end
