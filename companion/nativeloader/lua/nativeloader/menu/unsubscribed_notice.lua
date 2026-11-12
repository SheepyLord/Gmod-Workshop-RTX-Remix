-- The notice for a Steam account that does not subscribe to the RTX package while it is installed (ADR 0188). Steam
-- keeps a Workshop item on this computer while another Steam account here still subscribes to it ("keeping
-- unsubscribed item" in its workshop log), and the loader installs per computer: RTX then stays for every account. The
-- RTX client module (gmsv_nlrtxclient) runs this once in the menu realm of an RTX start, so it reaches loaders that are
-- already installed. Edit the English text below; its translations are in companion/i18n/<language>.po. Documented in
-- unsubscribed_notice.lua.md.
if not MENU_DLL or NativeLoaderUnsubscribedNotice then return end

local api = rawget(_G, "__NATIVELOADER_MENU_API")
local read = istable(api) and isfunction(api.read) and api.read or nil
local function N(text) return text end

local TEXT = {
    title = N"RTX Remix is not subscribed on this Steam account",
    installed = N"This Steam account does not subscribe to RTX Remix (Workshop item %s), but RTX Remix is still installed in this game.",
    why = N"Steam keeps a Workshop item on this computer while any other Steam account here still subscribes to it, so RTX Remix stays installed for every account. It is removed at the first game start after no Steam account on this computer subscribes to it.",
    how = N"To remove RTX Remix, unsubscribe from it on every Steam account on this computer. If you have only just unsubscribed, restart the game.",
    ok = N"OK",
    never = N"Don't show this again",
}

local COOKIE = "nativeloader.unsubscribed-notice"
local PACKAGE = "gmod-rtx-remix"

-- The Workshop item the loader deployed the RTX package from, as its start-up report names it; nil for a local or
-- development source (no subscription to check) or when the report cannot be read.
local function sourceItem()
    local ok, text = pcall(file.Read, "native-loader/status.json", "DATA")
    if not ok or not isstring(text) or #text > 8 * 1024 * 1024 then return nil end
    local status = util.JSONToTable(text)
    local packages = istable(status) and status.packages
    if not istable(packages) then return nil end
    for _, package in ipairs(packages) do
        if istable(package) and package.id == PACKAGE and package.source == "workshop" then
            local id = tostring(package.label or "")
            if id:match("^%d+$") and #id <= 20 then return id end
        end
    end
    return nil
end

local ALIASES = { zh = "zh-CN", ["zh-cn"] = "zh-CN", ["zh-tw"] = "zh-TW" }
local catalog
-- As the multiplayer notice: the companion's language is a client convar the menu realm cannot see, so the companion
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
local function L(text)
    local code = language()
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

local item = sourceItem()
local state = cookie.GetString(COOKIE, "") == "dismissed" and "dismissed" or "watching"
local lastCount -- the subscription list's size at the previous check
local verdict -- "subscribed" or "not subscribed", once the list is known

-- Whether this account subscribes to the item, from the menu's own list of the account's subscriptions
-- (engine.GetAddons, which lists every subscribed item, mounted or not). nil while that list is not known yet: it
-- starts empty and fills when Steam has listed the subscriptions, so only a list that is not empty and has kept its size
-- for one check counts (a partial list must never tell a subscribed player that they are not).
local function subscribed()
    local ok, addons = pcall(engine.GetAddons)
    if not ok or not istable(addons) or #addons == 0 then
        lastCount = nil
        return nil
    end
    for _, addon in ipairs(addons) do
        if istable(addon) and tostring(addon.wsid or "") == item then return true end
    end
    if isfunction(steamworks.IsSubscribed) and steamworks.IsSubscribed(item) then return true end
    local stable = lastCount == #addons
    lastCount = #addons
    if not stable then return nil end
    return false
end

local frame
local function scale() return math.max(0.65, ScrH() / 1080) end
local function build()
    local s = scale()
    local function px(n) return math.floor(n * s + 0.5) end
    -- Tahoma with `extended`, as the multiplayer notice: Windows then supplies the other languages' glyphs.
    local function font(name, size, weight)
        surface.CreateFont(name, { font = "Tahoma", size = px(size), weight = weight, antialias = true, extended = true })
    end
    font("NativeLoaderUnsubTitle", 27, 800)
    font("NativeLoaderUnsubText", 19, 500)
    font("NativeLoaderUnsubButton", 19, 800)

    local overlay = vgui.Create("DPanel")
    overlay:SetSize(ScrW(), ScrH())
    overlay:SetPos(0, 0)
    overlay:MakePopup()
    overlay:SetKeyboardInputEnabled(true)
    overlay.Paint = function(_, w, h) surface.SetDrawColor(0, 0, 0, 195) surface.DrawRect(0, 0, w, h) end

    local card = vgui.Create("DPanel", overlay)
    local width = math.min(ScrW() - px(48), px(780))
    card:SetWide(width)
    card.Paint = function(_, w, h)
        draw.RoundedBox(px(8), 0, 0, w, h, Color(70, 142, 208))
        draw.RoundedBox(px(7), px(2), px(2), w - px(4), h - px(4), Color(22, 35, 51))
    end
    local pad, y = px(28), px(24)
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
    local function label(text, font)
        local lines = wrap(text, font, width - pad * 2)
        surface.SetFont(font)
        local _, lineTall = surface.GetTextSize("Ag")
        local panel = vgui.Create("DPanel", card)
        panel:SetPos(pad, y)
        panel:SetSize(width - pad * 2, lineTall * #lines)
        panel.Paint = function()
            for i, value in ipairs(lines) do draw.SimpleText(value, font, 0, (i - 1) * lineTall, Color(237, 244, 255)) end
        end
        y = y + panel:GetTall() + px(12)
    end
    label(L(TEXT.title), "NativeLoaderUnsubTitle")
    y = y + px(4)
    label(string.format(L(TEXT.installed), item), "NativeLoaderUnsubText")
    label(L(TEXT.why), "NativeLoaderUnsubText")
    label(L(TEXT.how), "NativeLoaderUnsubText")

    local function close()
        if IsValid(overlay) then overlay:Remove() end
        frame = nil
    end
    local function button(text, x, colors, action)
        surface.SetFont("NativeLoaderUnsubButton")
        local wide = math.min(width - pad * 2, select(1, surface.GetTextSize(text)) + px(48))
        local panel = vgui.Create("DButton", card)
        panel:SetFont("NativeLoaderUnsubButton")
        panel:SetText(text)
        panel:SetTextColor(Color(255, 255, 255))
        panel:SetPos(x, y)
        panel:SetSize(wide, px(44))
        panel.Paint = function(self, bw, bh)
            draw.RoundedBox(px(5), 0, 0, bw, bh, colors[3])
            draw.RoundedBox(px(4), px(2), px(2), bw - px(4), bh - px(4), self:IsHovered() and colors[2] or colors[1])
        end
        panel.DoClick = action
        return panel
    end
    local primary = button(L(TEXT.ok), pad, { Color(38, 72, 103), Color(52, 98, 140), Color(138, 177, 215) }, close)
    local neverX = pad + primary:GetWide() + px(12)
    surface.SetFont("NativeLoaderUnsubButton")
    if neverX + select(1, surface.GetTextSize(L(TEXT.never))) + px(48) > width - pad then
        y = y + px(44) + px(10)
        neverX = pad
    end
    button(L(TEXT.never), neverX, { Color(48, 52, 60), Color(70, 76, 88), Color(120, 128, 140) }, function()
        state = "dismissed"
        cookie.Set(COOKIE, state)
        close()
    end)
    card:SetTall(y + px(44) + px(24))
    card:SetPos(math.floor((ScrW() - width) / 2), math.max(px(12), math.floor((ScrH() - card:GetTall()) / 2)))
    overlay.OnKeyCodePressed = function(_, key)
        if key == KEY_ESCAPE or key == KEY_ENTER or key == KEY_PAD_ENTER then close() end
    end
    primary:RequestFocus()
    return overlay
end

local function show(force)
    if not item or IsValid(frame) or (state == "dismissed" and not force) then return end
    local ok, result = pcall(build)
    if ok then
        frame = result
    else
        MsgN("[nativeloader] unsubscribed notice failed: " .. tostring(result))
    end
end

-- Decides once the account's list is known; a change of the subscriptions later in the menu decides again.
local function check()
    if not item then return end
    local answer = subscribed()
    if answer == nil then return end
    local was = verdict
    verdict = answer and "subscribed" or "not subscribed"
    if was ~= verdict then
        MsgN("[nativeloader] RTX package from Workshop item " .. item .. ": " .. verdict .. " on this Steam account")
    end
    if verdict == "not subscribed" and was ~= verdict then show(false) end
end

NativeLoaderUnsubscribedNotice = {}
function NativeLoaderUnsubscribedNotice.Item() return item end
function NativeLoaderUnsubscribedNotice.Verdict() return verdict end

if item then
    hook.Add("WorkshopSubscriptionsChanged", "NativeLoaderUnsubscribedNotice", function() timer.Simple(1, check) end)
    hook.Add("GameContentChanged", "NativeLoaderUnsubscribedNotice", function() timer.Simple(1, check) end)
    -- Steam lists the subscriptions within seconds of the menu (RESEARCH section 24); the checks stop after two minutes.
    timer.Create("NativeLoaderUnsubscribedNotice", 5, 24, check)
end

if concommand and concommand.Add then
    concommand.Add("nativeloader_unsubscribed_notice", function() show(true) end, nil,
        "Show the notice for a Steam account that does not subscribe to the RTX package now")
    concommand.Add("nativeloader_unsubscribed_notice_reset", function()
        state = "watching"
        cookie.Set(COOKIE, state)
    end, nil, "Show the unsubscribed notice again after \"Don't show this again\"")
    concommand.Add("nativeloader_unsubscribed_notice_status", function()
        local ok, addons = pcall(engine.GetAddons)
        MsgN(string.format("[nativeloader] unsubscribed notice: %s; item %s; verdict %s; subscriptions listed %s",
            state, tostring(item), tostring(verdict), ok and istable(addons) and tostring(#addons) or "unknown"))
    end, nil, "Print the unsubscribed notice's state")
end
