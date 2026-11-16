-- The window that tells a player RTX Remix is left in this game without its loader (ADR 0235), in two forms from one
-- spec: the long one the client autorun nativeloader_leftovers_popup.lua shows while the files are still there, and the
-- short one the server's nativeloader_leftovers.lua sends after it removed them. It needs nothing else of this add-on
-- (no include, no translation: the spec's texts are already in the player's language), so the server can send its
-- source to a client whose copy of the add-on it has just deleted. Returns { Show = function(spec) }.
--
-- spec = {
--   title = "...",                                    the window's title
--   paragraphs = { "...", ... },                      the text, top to bottom
--   sections = { { heading = "...", lines = { "...", ... } }, ... },
--   buttons = { { text = "...", url = "https://..." }                       opens the page, the window stays
--             | { text = "...", copy = "...", copied = "..." }             puts the text on the clipboard
--             | { text = "...", dismiss = "nativeloader_companion/x.txt" } remembers, then closes
--             | { text = "...", close = true } },                          closes
-- }
local ACCENT = Color(118, 185, 0) -- the accent of the loading window and RTX Remix
local BACKGROUND = Color(24, 26, 30, 245)
local TEXT = Color(235, 237, 240)
local DISMISS_FOLDER = "nativeloader_companion/"

local function Show(spec)
    if type(spec) ~= "table" or type(vgui) ~= "table" or type(vgui.Create) ~= "function" then return end
    if IsValid(NativeLoaderLeftoversWindow) then NativeLoaderLeftoversWindow:Remove() end
    -- The companion's windows scale with the screen (4K), and the fonts take every script (extended).
    local scale = math.max(0.65, ScrH() / 1080)
    local function px(n) return math.floor(n * scale + 0.5) end
    surface.CreateFont("NativeLoaderLeftoversTitle", { font = "Tahoma", size = px(22), weight = 700, extended = true })
    surface.CreateFont("NativeLoaderLeftoversHeading", { font = "Tahoma", size = px(18), weight = 700, extended = true })
    surface.CreateFont("NativeLoaderLeftoversBody", { font = "Tahoma", size = px(16), weight = 400, extended = true })

    local frame = vgui.Create("DFrame")
    NativeLoaderLeftoversWindow = frame
    local long = istable(spec.sections) and #spec.sections > 0
    frame:SetSize(math.min(px(long and 760 or 560), ScrW() - px(40)), math.min(px(long and 660 or 300), ScrH() - px(40)))
    frame:SetTitle("")
    frame:ShowCloseButton(false)
    frame:SetDraggable(true)
    frame:DockPadding(px(24), px(20), px(24), px(18))
    frame.Paint = function(_, w, h)
        draw.RoundedBox(px(8), 0, 0, w, h, BACKGROUND)
        surface.SetDrawColor(ACCENT.r, ACCENT.g, ACCENT.b, 255)
        surface.DrawRect(0, 0, w, px(4))
    end

    local title = frame:Add("DLabel")
    title:Dock(TOP)
    title:SetFont("NativeLoaderLeftoversTitle")
    title:SetTextColor(ACCENT)
    title:SetWrap(true)
    title:SetAutoStretchVertical(true)
    title:SetText(tostring(spec.title or "RTX Remix"))
    title:DockMargin(0, 0, 0, px(10))

    local row = frame:Add("DPanel")
    row:Dock(BOTTOM)
    row:SetTall(px(34))
    row:DockMargin(0, px(14), 0, 0)
    row.Paint = function() end

    local scroll = frame:Add("DScrollPanel")
    scroll:Dock(FILL)
    local labels = {}
    local function label(text, font, color, top)
        local line = scroll:Add("DLabel")
        line:Dock(TOP)
        line:DockMargin(0, top, px(10), 0)
        line:SetFont(font)
        line:SetTextColor(color)
        line:SetWrap(true)
        line:SetAutoStretchVertical(true)
        line:SetText(tostring(text))
        labels[#labels + 1] = { panel = line, top = top }
        return line
    end
    for i, text in ipairs(istable(spec.paragraphs) and spec.paragraphs or {}) do
        label(text, "NativeLoaderLeftoversBody", TEXT, i > 1 and px(8) or 0)
    end
    for _, section in ipairs(istable(spec.sections) and spec.sections or {}) do
        label(section.heading or "", "NativeLoaderLeftoversHeading", ACCENT, px(16))
        for _, text in ipairs(istable(section.lines) and section.lines or {}) do
            label(text, "NativeLoaderLeftoversBody", TEXT, px(6))
        end
    end

    -- The buttons, left to right as the spec lists them.
    for _, item in ipairs(istable(spec.buttons) and spec.buttons or {}) do
        if istable(item) then
            local button = row:Add("DButton")
            button:Dock(LEFT)
            button:DockMargin(0, 0, px(10), 0)
            button:SetFont("NativeLoaderLeftoversBody")
            button:SetText(tostring(item.text or "OK"))
            button:SizeToContentsX(px(28))
            button.DoClick = function()
                if isstring(item.url) and item.url:find("^https://") then
                    gui.OpenURL(item.url)
                    return
                end
                if isstring(item.copy) then
                    SetClipboardText(item.copy)
                    if isstring(item.copied) then
                        button:SetText(item.copied)
                        button:SizeToContentsX(px(28))
                    end
                    return
                end
                if isstring(item.dismiss) and item.dismiss:sub(1, #DISMISS_FOLDER) == DISMISS_FOLDER
                        and not item.dismiss:find("..", 1, true) then
                    file.CreateDir(DISMISS_FOLDER:sub(1, -2))
                    file.Write(item.dismiss, "dismissed\n")
                end
                frame:Remove()
            end
        end
    end

    -- The height follows the text, up to the size set above: the short form gets no empty band above its button, the
    -- long one scrolls. A wrapped label has its height only after its own layout, so the window fits itself on every
    -- frame of its first second (after DFrame's own Think: dragging).
    local largest = frame:GetTall()
    local function fit()
        local text = 0
        for _, item in ipairs(labels) do text = text + item.top + item.panel:GetTall() end
        local needed = px(20) + title:GetTall() + px(10) + text + px(8) + px(14) + row:GetTall() + px(18)
        local tall = math.min(largest, math.max(px(120), needed))
        if tall ~= frame:GetTall() then
            frame:SetTall(tall)
            frame:Center()
        end
    end
    local frameThink, fitUntil = frame.Think, SysTime and SysTime() + 1 or 0
    frame.Think = function(self)
        if frameThink then frameThink(self) end
        if SysTime() < fitUntil then fit() end
    end

    frame:Center()
    frame:MakePopup()
    return frame
end

return { Show = Show }
