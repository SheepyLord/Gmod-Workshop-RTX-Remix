-- Free disk space for the loader's unpacking (ADR 0260). At each start the loader (winmm.dll) unpacks the new versions
-- of RTX Remix and its content packs after it has checked that their new files fit on the game's drive with 64 MiB to
-- spare. When they do not, or when the drive fills while it unpacks, it changes nothing and the game runs the versions
-- it had; its start-up report, data/native-loader/status.json, says why (deployment "failed" and its reason), and
-- nothing a player sees does. So the package says it in the menu of an RTX start:
-- * after such a start, a card with what was needed and free, that nothing changed, and how much to free;
-- * before it happens, a card when the drive has less free space than the largest deployed package would need to
--   unpack again (its payload folder, unpacked whole for each new version, and its other files), with the loader's
--   spare and room for the game's own caches.
-- The RTX client module (gmsv_nlrtxclient) runs this once in the menu realm of an RTX start; the free space and each
-- package's size come from its menu API (disk_space), which an older module lacks: then only the first card can show.
-- Edit the English text below; its translations are in companion/i18n/<language>.po. Documented in disk_space.lua.md.
if not MENU_DLL or NativeLoaderDiskSpace then return end

local api = rawget(_G, "__NATIVELOADER_MENU_API")
local read = istable(api) and isfunction(api.read) and api.read or nil
local diskSpace = istable(api) and isfunction(api.disk_space) and api.disk_space or nil
local function N(text) return text end

local TEXT = {
    failedTitle = N"Not enough disk space to install updates",
    failedNeed = N"At the last start the RTX Remix loader needed %s free on drive %s to unpack updates of RTX Remix or its content packs, and keeps another %s free, but only %s were free.",
    failedFull = N"At the last start drive %s ran out of space while the RTX Remix loader unpacked updates of RTX Remix or its content packs.",
    failedKept = N"Nothing was changed: the game runs the versions that were installed before.",
    failedHow = N"Free at least %s on drive %s, then restart the game: the updates are installed at the next start.",
    failedHowSome = N"Free some space on drive %s, then restart the game: the updates are installed at the next start.",
    lowTitle = N"Little free disk space for updates",
    lowWhat = N"Drive %s has %s free. RTX Remix and its content packs unpack their updates on this drive, and the largest of them needs up to %s at once.",
    lowWhy = N"With less free space than that, an update is not installed and the game keeps the versions it has.",
    lowHow = N"Free at least %s on drive %s so that updates can be installed.",
    gigabytes = N"%s GB",
    megabytes = N"%s MB",
    ok = N"OK",
    never = N"Don't show this again",
}

local COOKIE = "nativeloader.disk-space-notice"
local MIB = 1048576
local SPARE = 64 * MIB   -- what the loader keeps free after its new files (loader/core/src/deploy.cpp, kSpareBytes)
local MARGIN = 512 * MIB -- room for the game's own caches and logs on top of it

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

-- A size as Windows shows one: tenths of a GB from 1 GB, else whole MB; up = rounded up (an amount to free). Its
-- spaces are no-break spaces, so a line is never broken between the number and its unit.
local NBSP = "\194\160"
local function size(bytes, up)
    bytes = math.max(0, tonumber(bytes) or 0)
    local text
    if bytes >= 1024 * MIB then
        local tenths = bytes / (1024 * MIB) * 10
        tenths = up and math.ceil(tenths - 1e-9) or math.floor(tenths + 0.5)
        text = string.format(L(TEXT.gigabytes), string.format("%.1f", tenths / 10))
    else
        local mib = bytes / MIB
        text = string.format(L(TEXT.megabytes), string.format("%d", up and math.ceil(mib - 1e-9) or math.floor(mib + 0.5)))
    end
    return (string.gsub(text, " ", NBSP))
end

-- The loader's start-up report, or nil.
local function report()
    local ok, text = pcall(file.Read, "native-loader/status.json", "DATA")
    if not ok or not isstring(text) or #text > 8 * 1024 * 1024 then return nil end
    local status = util.JSONToTable(text)
    return istable(status) and status or nil
end

-- What the last start's deployment says about disk space: nil, or { kind = "need", need, spare, free } (bytes) from the
-- loader's check before it unpacks, { kind = "full" } for a drive that filled while it unpacked (Windows errors 112 and
-- 39), or { kind = "space" } for another wording of the check.
local function failure(status)
    local deployment = istable(status) and status.deployment
    if not istable(deployment) or deployment.outcome ~= "failed" then return nil end
    local reason = tostring(deployment.reason or "")
    local need, spare, free = reason:match("not enough free disk space: the new files need (%d+) MiB and (%d+) MiB should stay free, but only (%d+) MiB are free")
    if need then
        return { kind = "need", need = tonumber(need) * MIB, spare = tonumber(spare) * MIB, free = tonumber(free) * MIB }
    end
    if reason:find("(Windows error 112)", 1, true) or reason:find("(Windows error 39)", 1, true) then return { kind = "full" } end
    if reason:find("free disk space", 1, true) then return { kind = "space" } end
    return nil
end

-- The drive's letter from the runtime folder the loader activated (an absolute path), for a module without disk_space.
local function driveOf(status)
    local activation = istable(status) and status.activation
    local runtime = istable(activation) and activation.runtime
    local folder = istable(runtime) and runtime.folder
    local letter = isstring(folder) and folder:match("^(%a:)[\\/]")
    return letter and string.upper(letter) or nil
end

-- The drive's free space now and the largest deployed package (bytes), from the RTX client module; nil and why without.
local function measure()
    if not diskSpace then return nil, "this RTX client module does not measure disk space" end
    local ok, space, why = pcall(diskSpace)
    if not ok then return nil, tostring(space) end
    if not istable(space) then return nil, tostring(why or "no answer") end
    local largest, largestId = 0, nil
    for _, package in ipairs(istable(space.packages) and space.packages or {}) do
        if istable(package) then
            local bytes = math.max(0, tonumber(package.payload) or 0) + math.max(0, tonumber(package.files) or 0)
            if bytes > largest then largest, largestId = bytes, tostring(package.id or "") end
        end
    end
    local drive = isstring(space.drive) and space.drive:match("^%a:$") and string.upper(space.drive) or nil
    return { available = math.max(0, tonumber(space.available) or 0), total = math.max(0, tonumber(space.total) or 0),
             drive = drive, largest = largest, largestId = largestId }
end

-- What an update of the largest package would want free: its files, the loader's spare and room for the game.
local function wanted(measured) return measured.largest + SPARE + MARGIN end

local state = cookie.GetString(COOKIE, "") == "dismissed" and "dismissed" or "watching"
local status = report()
local lastFailure = failure(status)
local measured, measureProblem = measure()
local frame

local function drive()
    return measured and measured.drive or driveOf(status) or "?"
end

-- The card to show, or nil: the last start's failure first, then too little space for the largest package.
local function decide(forced)
    if lastFailure then
        local paragraphs
        if lastFailure.kind == "need" then
            local short = lastFailure.need + lastFailure.spare - lastFailure.free + MARGIN
            paragraphs = {
                string.format(L(TEXT.failedNeed), size(lastFailure.need, true), drive(), size(lastFailure.spare, true), size(lastFailure.free)),
                L(TEXT.failedKept),
                string.format(L(TEXT.failedHow), size(math.max(short, MIB), true), drive()),
            }
        else
            local how = string.format(L(TEXT.failedHowSome), drive())
            if lastFailure.kind == "full" and measured and measured.largest > 0 then
                local short = wanted(measured) - measured.available
                if short > 0 then how = string.format(L(TEXT.failedHow), size(short, true), drive()) end
            end
            paragraphs = { lastFailure.kind == "full" and string.format(L(TEXT.failedFull), drive()) or nil, L(TEXT.failedKept), how }
            local packed = {}
            for i = 1, 3 do if paragraphs[i] then packed[#packed + 1] = paragraphs[i] end end
            paragraphs = packed
        end
        return { kind = "failed", title = L(TEXT.failedTitle), paragraphs = paragraphs }
    end
    if measured and measured.largest > 0 and measured.available < wanted(measured) and (state ~= "dismissed" or forced) then
        return { kind = "low", title = L(TEXT.lowTitle), never = true, paragraphs = {
            string.format(L(TEXT.lowWhat), drive(), size(measured.available), size(measured.largest, true)),
            L(TEXT.lowWhy),
            string.format(L(TEXT.lowHow), size(wanted(measured) - measured.available, true), drive()),
        } }
    end
    return nil
end

local function scale() return math.max(0.65, ScrH() / 1080) end
-- A card: { title = text, paragraphs = { text, ... }, never = whether "Don't show this again" is offered }; as the
-- unsubscribed notice's.
local function build(content)
    local s = scale()
    local function px(n) return math.floor(n * s + 0.5) end
    -- Tahoma with `extended`, as the multiplayer notice: Windows then supplies the other languages' glyphs.
    local function font(name, size, weight)
        surface.CreateFont(name, { font = "Tahoma", size = px(size), weight = weight, antialias = true, extended = true })
    end
    font("NativeLoaderDiskTitle", 27, 800)
    font("NativeLoaderDiskText", 19, 500)
    font("NativeLoaderDiskButton", 19, 800)

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
        draw.RoundedBox(px(8), 0, 0, w, h, Color(208, 150, 70))
        draw.RoundedBox(px(7), px(2), px(2), w - px(4), h - px(4), Color(40, 30, 22))
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
            for i, value in ipairs(lines) do draw.SimpleText(value, font, 0, (i - 1) * lineTall, Color(255, 246, 232)) end
        end
        y = y + panel:GetTall() + px(12)
    end
    label(content.title, "NativeLoaderDiskTitle")
    y = y + px(4)
    for _, paragraph in ipairs(content.paragraphs) do label(paragraph, "NativeLoaderDiskText") end

    local function close()
        if IsValid(overlay) then overlay:Remove() end
        frame = nil
    end
    local function button(text, x, colors, action)
        surface.SetFont("NativeLoaderDiskButton")
        local wide = math.min(width - pad * 2, select(1, surface.GetTextSize(text)) + px(48))
        local panel = vgui.Create("DButton", card)
        panel:SetFont("NativeLoaderDiskButton")
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
    local primary = button(L(TEXT.ok), pad, { Color(103, 72, 38), Color(140, 98, 52), Color(215, 177, 138) }, close)
    if content.never then
        local neverX = pad + primary:GetWide() + px(12)
        surface.SetFont("NativeLoaderDiskButton")
        if neverX + select(1, surface.GetTextSize(L(TEXT.never))) + px(48) > width - pad then
            y = y + px(44) + px(10)
            neverX = pad
        end
        button(L(TEXT.never), neverX, { Color(48, 52, 60), Color(70, 76, 88), Color(120, 128, 140) }, function()
            state = "dismissed"
            cookie.Set(COOKIE, state)
            close()
        end)
    end
    card:SetTall(y + px(44) + px(24))
    card:SetPos(math.floor((ScrW() - width) / 2), math.max(px(12), math.floor((ScrH() - card:GetTall()) / 2)))
    overlay.OnKeyCodePressed = function(_, key)
        if key == KEY_ESCAPE or key == KEY_ENTER or key == KEY_PAD_ENTER then close() end
    end
    primary:RequestFocus()
    return overlay
end

local function show(forced)
    local content = decide(forced)
    if not content then return nil end
    if IsValid(frame) then frame:Remove() end
    local ok, result = pcall(build, content)
    if ok then
        frame = result
    else
        frame = nil
        MsgN("[nativeloader] disk space notice failed: " .. tostring(result))
    end
    return content.kind
end

local function describe()
    local parts = { "notice " .. state }
    if measured then
        parts[#parts + 1] = string.format("drive %s has %d MiB free of %d MiB", drive(), math.floor(measured.available / MIB),
            math.floor(measured.total / MIB))
        parts[#parts + 1] = string.format("largest package %s: %d MiB; wanted free %d MiB", tostring(measured.largestId),
            math.floor(measured.largest / MIB), math.floor(wanted(measured) / MIB))
    else
        parts[#parts + 1] = "free space unknown (" .. tostring(measureProblem) .. ")"
    end
    local deployment = istable(status) and status.deployment
    parts[#parts + 1] = "last deployment " .. tostring(istable(deployment) and deployment.outcome or "unknown")
        .. (lastFailure and (" (disk space: " .. lastFailure.kind .. ")") or "")
    return table.concat(parts, "; ")
end

-- A card with sample numbers, to see its layout and translations: "need" (the loader's refusal), "full" (a drive that
-- filled while unpacking) or "low" (the warning). Nothing it shows is measured.
local function preview(kind)
    local saved = { lastFailure, measured, state }
    local sample = { available = 2000 * MIB, total = 1000000 * MIB, drive = drive(), largest = 3700 * MIB, largestId = "sample" }
    if kind == "low" then
        lastFailure, measured = nil, sample
    elseif kind == "full" then
        lastFailure, measured = { kind = "full" }, sample
    else
        lastFailure = { kind = "need", need = 2300 * MIB, spare = SPARE, free = 1500 * MIB }
    end
    state = "watching"
    local shown = show(true)
    lastFailure, measured, state = saved[1], saved[2], saved[3]
    return shown
end

NativeLoaderDiskSpace = {}
function NativeLoaderDiskSpace.Failure() return lastFailure end
function NativeLoaderDiskSpace.Measured() return measured end
function NativeLoaderDiskSpace.Card() return decide(true) end
function NativeLoaderDiskSpace.Shown() return IsValid(frame) end
NativeLoaderDiskSpace.Preview = preview

if lastFailure or measured then
    MsgN("[nativeloader] disk space: " .. describe())
    -- After the menu is up: a card built before the menu's own panels would sit under them.
    local tries = 0
    timer.Create("NativeLoaderDiskSpace", 2, 15, function()
        tries = tries + 1
        if ScrW() < 640 or ScrH() < 360 then return end
        timer.Remove("NativeLoaderDiskSpace")
        show(false)
    end)
end

if concommand and concommand.Add then
    concommand.Add("nativeloader_disk_space", function()
        measured, measureProblem = measure()
        local kind = show(true)
        MsgN("[nativeloader] disk space: " .. describe() .. (kind and ("; card: " .. kind) or "; no card: there is space for updates"))
    end, nil, "Show the disk space notice now, or say why there is none")
    concommand.Add("nativeloader_disk_space_reset", function()
        state = "watching"
        cookie.Set(COOKIE, state)
    end, nil, "Show the low disk space notice again after \"Don't show this again\"")
    concommand.Add("nativeloader_disk_space_status", function()
        measured, measureProblem = measure()
        MsgN("[nativeloader] disk space: " .. describe())
    end, nil, "Print the free space of the game's drive, what the largest package needs and the last start's deployment")
    concommand.Add("nativeloader_disk_space_preview", function(_, _, args)
        local kind = tostring(args and args[1] or "need")
        if kind ~= "low" and kind ~= "full" then kind = "need" end
        MsgN("[nativeloader] disk space: preview of the " .. kind .. " card (sample numbers): " .. tostring(preview(kind)))
    end, nil, "Show a disk space card with sample numbers: need (default), full or low")
end
