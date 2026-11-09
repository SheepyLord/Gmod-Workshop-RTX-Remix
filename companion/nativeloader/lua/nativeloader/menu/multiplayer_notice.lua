-- The notice before the server browser (R24, ADR 0133). The RTX client module (gmsv_nlrtxclient) runs the companion's
-- verified lua/nativeloader/menu/*.lua once in the menu realm of an RTX start, so this text changes with the package,
-- not with the loader. Edit the English text below; its translations are in companion/i18n/<language>.po.
-- It replaces the notice of loaders 0.15.0-0.16.0, which this script turns off. Documented in multiplayer_notice.lua.md.
if not MENU_DLL or NativeLoaderMultiplayerNotice then return end

local api = rawget(_G, "__NATIVELOADER_MENU_API")
local read = istable(api) and isfunction(api.read) and api.read or nil
local function N(text) return text end

local TEXT = {
    title = N"Before you join a server",
    rules = N"Some servers do not allow custom renderers and shaders such as RTX Remix and ReShade. A server likely won't be able to detect that you use them, but posting photos of using RTX Remix on those servers might cause concerns. Check a server's rules before you join.",
    performance = N"Performance and stability are not guaranteed online, especially without the PBR resources (RTX content) for the map the server runs.",
    risk = N"You use this add-on on servers at your own risk: its developers take no responsibility for any consequences.",
    never = N"Don't show this again",
    proceed = N"I understand, continue",
    back = N"Back",
}

-- The choice, kept in the menu's cookies (mn.db). "Don't show this again" in the loader's own notice carries over once.
local OURS, LOADER = "nativeloader.multiplayer-notice", "nativeloader.multiplayer-warning-dismissed"
local state = cookie.GetString(OURS, "")
if state ~= "active" and state ~= "dismissed" then
    state = cookie.GetString(LOADER, "") == "1" and "dismissed" or "active"
    cookie.Set(OURS, state)
end
-- The loader's notice stays off from its next read of this cookie; retire() below turns it off on the page already open.
cookie.Set(LOADER, "1")

local ALIASES = { zh = "zh-CN", ["zh-cn"] = "zh-CN", ["zh-tw"] = "zh-TW" }
local catalog
-- The companion's own language setting is a client convar, which the menu realm cannot see (PoC, R24): the companion
-- keeps a copy for the menu in data/nativeloader_companion/language.txt (nativeloader/i18n.lua). Returns the code and
-- where it came from.
local function chosenLanguage()
    local chosen = GetConVar("nativeloader_language")
    if chosen then return chosen:GetString(), "nativeloader_language" end
    local saved = file and isfunction(file.Read) and file.Read("nativeloader_companion/language.txt", "DATA")
    if isstring(saved) and #saved <= 16 and saved:match("^[%w%-]+$") then return saved, "nativeloader_language (saved)" end
    return "", nil
end
local function language()
    local code, source = chosenLanguage()
    if code == "" then
        local gmod = GetConVar("gmod_language")
        code, source = gmod and gmod:GetString() or "en", "gmod_language"
    end
    return ALIASES[string.lower(code)] or code, source
end
-- The generated translation table. The menu realm has no CompileString (PoC, R24), only RunString (the stock menu's
-- lua.Run uses it): the table goes through a global that is taken and cleared at once.
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

local function json(value)
    return util.TableToJSON({ value }):sub(2, -2)
end

-- The page's half: Angular's navigation event to the server browser asks this script first. The loader's own
-- notice (if it is there) is told the player already chose, through its own entry point and session token.
local PAGE = [[
(function (off, session, ignored) {
  var self = window.NativeLoaderMPNotice;
  if (self) { self.off = off; return; }
  if (!window.angular || !window.lua || typeof window.lua.Run !== 'function') return;
  var element = document.querySelector('[ng-app]') || document.body;
  var injector = element && angular.element(element).injector && angular.element(element).injector();
  if (!injector) return;
  var root = injector.get('$rootScope'), loc = injector.get('$location');
  self = window.NativeLoaderMPNotice = { off: off, allowed: null };
  self.go = function (target) { self.allowed = target; root.$evalAsync(function () { loc.url(target); }); };
  var data = window.NativeLoaderDiagnostics;
  if (typeof window.NativeLoaderReceiveMenuState === 'function' && data && data.session_token) {
    try {
      window.NativeLoaderReceiveMenuState({ session_token: data.session_token, update_seen: session === data.session_token,
        ignored_version: ignored, multiplayer_dismissed: true });
    } catch (e) { }
  }
  root.$on('$locationChangeStart', function (event) {
    try {
      if (self.off || !/^\/servers(?:\/|$)/i.test(loc.path())) return;
      var target = loc.url();
      if (self.allowed === target) { self.allowed = null; return; }
      if (target.length > 512) return;
      // Held only once Lua has it: a failing call lets the browser open rather than swallow the click.
      window.lua.Run('NativeLoaderMultiplayerNotice.Open(%s)', target);
      event.preventDefault();
    } catch (e) { }
  });
})]]

local function install()
    if not IsValid(pnlMainMenu) or not pnlMainMenu.Call then return end
    -- While the page loads, JavaScript queued for it piles up in the panel (DHTML:QueueJavascript): wait for it.
    local html = pnlMainMenu.HTML
    if IsValid(html) and isfunction(html.IsLoading) and html:IsLoading() then return end
    local session = rawget(_G, "NativeLoaderUpdateSession")
    local ignored = cookie.GetString("nativeloader.loader-update-ignored", "")
    if not isstring(ignored) or #ignored > 128 then ignored = "" end
    pnlMainMenu:Call(PAGE .. "(" .. tostring(state == "dismissed") .. ", " .. json(isstring(session) and session or "") ..
        ", " .. json(ignored) .. ")")
end

local function go(target)
    if IsValid(pnlMainMenu) and pnlMainMenu.Call then
        pnlMainMenu:Call("window.NativeLoaderMPNotice && window.NativeLoaderMPNotice.go(" .. json(target) .. ")")
    end
end

local frame
local function scale() return math.max(0.65, ScrH() / 1080) end
local function build(target)
    local s = scale()
    local function px(n) return math.floor(n * s + 0.5) end
    -- Tahoma, as DermaDefault and the guide: with `extended` Windows supplies the other languages' glyphs (a GMod font
    -- without it draws Latin-1 only, and the Russian, Chinese, Japanese and Korean texts would show nothing).
    local function font(name, size, weight)
        surface.CreateFont(name, { font = "Tahoma", size = px(size), weight = weight, antialias = true, extended = true })
    end
    font("NativeLoaderMPTitle", 27, 800)
    font("NativeLoaderMPText", 19, 500)
    font("NativeLoaderMPButton", 19, 800)

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
    local function wrap(text, font, width)
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
            if line ~= "" and surface.GetTextSize(string.TrimRight(candidate)) > width then
                lines[#lines + 1] = string.TrimRight(line)
                line = string.TrimLeft(token)
            else
                line = candidate
            end
        end
        if line ~= "" then lines[#lines + 1] = string.TrimRight(line) end
        return lines
    end
    local function label(text, font, color)
        local lines = wrap(text, font, width - pad * 2)
        surface.SetFont(font)
        local _, lineTall = surface.GetTextSize("Ag")
        local item = vgui.Create("DPanel", card)
        item:SetPos(pad, y)
        item:SetSize(width - pad * 2, lineTall * #lines)
        item.Paint = function()
            for i, value in ipairs(lines) do
                draw.SimpleText(value, font, 0, (i - 1) * lineTall, color or Color(237, 244, 255))
            end
        end
        y = y + item:GetTall() + px(12)
        return item
    end
    label(L(TEXT.title), "NativeLoaderMPTitle")
    y = y + px(4)
    label(L(TEXT.rules), "NativeLoaderMPText")
    label(L(TEXT.performance), "NativeLoaderMPText")
    label(L(TEXT.risk), "NativeLoaderMPText")

    local function close()
        if IsValid(overlay) then overlay:Remove() end
        frame = nil
    end
    local function button(text, x, w, colors, action)
        local item = vgui.Create("DButton", card)
        item:SetFont("NativeLoaderMPButton")
        item:SetText(text)
        item:SetTextColor(Color(255, 255, 255))
        item:SetPos(x, y)
        item:SetSize(w, px(44))
        item.Paint = function(self, bw, bh)
            local c = self:IsHovered() and colors[2] or colors[1]
            draw.RoundedBox(px(5), 0, 0, bw, bh, colors[3])
            draw.RoundedBox(px(4), px(2), px(2), bw - px(4), bh - px(4), c)
        end
        item.DoClick = action
        return item
    end
    -- "Don't show this again" is a button of its own, the clearest one on the card: it continues and remembers.
    local never = L(TEXT.never)
    surface.SetFont("NativeLoaderMPButton")
    local inner = width - pad * 2
    local neverWide = math.min(inner, select(1, surface.GetTextSize(never)) + px(48))
    button(never, pad, neverWide, { Color(46, 125, 50), Color(67, 160, 71), Color(165, 214, 167) }, function()
        state = "dismissed"
        cookie.Set(OURS, state)
        if IsValid(pnlMainMenu) and pnlMainMenu.Call then
            pnlMainMenu:Call("if (window.NativeLoaderMPNotice) window.NativeLoaderMPNotice.off = true")
        end
        close()
        go(target)
    end)
    y = y + px(44) + px(12)
    local continueText, backText = L(TEXT.proceed), L(TEXT.back)
    local continueWide = math.min(inner, select(1, surface.GetTextSize(continueText)) + px(40))
    local backWide = math.min(inner, select(1, surface.GetTextSize(backText)) + px(40))
    local primary = button(continueText, pad, continueWide, { Color(38, 72, 103), Color(52, 98, 140), Color(138, 177, 215) }, function()
        close()
        go(target)
    end)
    local backX = pad + continueWide + px(12)
    if backX + backWide > width - pad then
        y = y + px(44) + px(10)
        backX = pad
    end
    button(backText, backX, backWide, { Color(48, 52, 60), Color(70, 76, 88), Color(120, 128, 140) }, close)
    card:SetTall(y + px(44) + px(24))
    card:SetPos(math.floor((ScrW() - width) / 2), math.max(px(12), math.floor((ScrH() - card:GetTall()) / 2)))
    overlay.OnKeyCodePressed = function(_, key)
        if key == KEY_ESCAPE then close() elseif key == KEY_ENTER or key == KEY_PAD_ENTER then primary:DoClick() end
    end
    primary:RequestFocus()
    return overlay
end

NativeLoaderMultiplayerNotice = {}
-- `force`: shown even after "Don't show this again" (the console command below). The page held this navigation for
-- the notice, so every way out but Back goes on to it: a target that is not the server browser's (the page matches
-- any case) or that is too long goes on at once.
function NativeLoaderMultiplayerNotice.Open(target, force)
    if not isstring(target) then return end
    if #target > 512 or not string.lower(target):find("^/servers") or (state == "dismissed" and not force) then
        go(target)
        return
    end
    if IsValid(frame) then return end -- the card that is open goes on when the player chooses
    local ok, result = pcall(build, target)
    if ok then
        frame = result
    else
        -- A notice that cannot be shown never keeps the server browser closed.
        MsgN("[nativeloader] multiplayer notice failed: " .. tostring(result))
        go(target)
    end
end
function NativeLoaderMultiplayerNotice.State() return state end
function NativeLoaderMultiplayerNotice.Reset()
    state = "active"
    cookie.Set(OURS, state)
    if IsValid(pnlMainMenu) and pnlMainMenu.Call then
        pnlMainMenu:Call("if (window.NativeLoaderMPNotice) window.NativeLoaderMPNotice.off = false")
    end
end

if concommand and concommand.Add then
    concommand.Add("nativeloader_multiplayer_notice", function()
        NativeLoaderMultiplayerNotice.Open("/servers/", true) -- the menu's only server browser route (menuApp.js)
    end, nil, "Show the notice before the server browser now")
    concommand.Add("nativeloader_multiplayer_notice_reset", NativeLoaderMultiplayerNotice.Reset, nil,
        "Show the notice before the server browser again after \"Don't show this again\"")
    concommand.Add("nativeloader_multiplayer_notice_status", function()
        local code, source = language()
        local title = L(TEXT.title)
        MsgN(string.format("[nativeloader] multiplayer notice: %s; language %s (from %s); translations %s; title: %s",
            state, code, source or "none", catalog == nil and "not needed" or catalog == false and
                ("unavailable (read " .. type(read) .. ", CompileString " .. type(CompileString) .. ", RunString " ..
                type(RunString) .. ")") or "read", title))
    end, nil, "Print the notice's state, its language and whether its translations were read")
end

-- The page can reload (a language change, a menu update): the page's half is installed again, once per page.
install()
timer.Create("NativeLoaderMultiplayerNotice", 2, 0, install)
