-- The companion's notice at the top right (R22's frame generation hint, ADR 0129; shared since R23):
-- the hint, the start-up stall notice (ADR 0130) and the imported characters' PBR progress use it.
-- Client only. include("nativeloader/notice.lua") returns the module; documented in notice.lua.md.
--   Notice.Show(text, options) -> panel, or nil without VGUI
--     options.seconds  how long it stays (default 15); 0 keeps it until closed or finished
--     options.title    the title line (default "RTX Remix")
--     options.progress a number from 0 to 1: a bar under the text
--   panel:SetNoticeText(text), panel:SetNoticeProgress(fraction), panel:FinishNotice(seconds)
if NATIVELOADER_NOTICE then return NATIVELOADER_NOTICE end

local SECONDS, FONT, TITLE_FONT = 15, "NativeLoaderHintNotice", "NativeLoaderHintNoticeTitle"
local ACCENT = { 118, 185, 0 } -- the accent of the loading window and RTX Remix

local function noticeTop(self, width, px)
    -- Below the other notices already in the top-right corner (the Hotloader's sits at y = 40): only
    -- notice-sized panels count, never a visible full-screen menu.
    local top = px(40)
    local world = type(vgui.GetWorldPanel) == "function" and vgui.GetWorldPanel()
    if not world or type(world.GetChildren) ~= "function" then return top end
    local left = ScrW() - width - px(20)
    for _ = 1, 6 do
        local moved = false
        for _, child in ipairs(world:GetChildren()) do
            if child ~= self and IsValid(child) and child:IsVisible() then
                local x, y = child:GetPos()
                local w, h = child:GetSize()
                if w < ScrW() / 2 and h < ScrH() / 2 and x + w > left and y < top + px(110) and y + h > top then
                    top, moved = y + h + px(10), true
                end
            end
        end
        if not moved then break end
    end
    return top
end

local function Show(text, options)
    if type(vgui) ~= "table" or type(vgui.Create) ~= "function" or type(ScrW) ~= "function" then return end
    options = options or {}
    local seconds = tonumber(options.seconds) or SECONDS
    local scale = math.max(0.65, ScrH() / 1080) -- the companion's windows scale with the screen (4K)
    local function px(n) return math.floor(n * scale + 0.5) end
    surface.CreateFont(TITLE_FONT, { font = "Arial", size = px(19), weight = 700 })
    surface.CreateFont(FONT, { font = "Arial", size = px(17), weight = 400 })
    local width = math.min(px(500), ScrW() - px(40))
    local panel = vgui.Create("DPanel")
    panel.nativeloaderHintNotice = true
    panel:SetSize(width, px(120))
    panel:DockPadding(px(18), px(12), px(40), px(14))
    local born, ends = SysTime(), seconds > 0 and SysTime() + seconds or nil
    local progress = tonumber(options.progress)
    panel.Paint = function(_, w, h)
        draw.RoundedBox(px(6), 0, 0, w, h, Color(24, 26, 30, 235))
        surface.SetDrawColor(ACCENT[1], ACCENT[2], ACCENT[3], 255)
        surface.DrawRect(0, 0, px(4), h)
        if progress then
            -- The bar along the bottom edge, inside the padding.
            local x, y, bw, bh = px(18), h - px(14), w - px(18) - px(40), px(6)
            surface.SetDrawColor(60, 64, 70, 255)
            surface.DrawRect(x, y, bw, bh)
            surface.SetDrawColor(ACCENT[1], ACCENT[2], ACCENT[3], 255)
            surface.DrawRect(x, y, math.floor(bw * math.Clamp(progress, 0, 1) + 0.5), bh)
        end
    end
    local title, body
    local function fit(self)
        -- The wrapped body sets its height during its own layout: follow it (and leave room for the bar).
        local tall = px(12) + title:GetTall() + body:GetTall() + px(14) + (progress and px(12) or 0)
        if self:GetTall() ~= tall then self:SetTall(tall) end
    end
    panel.Think = function(self)
        local now = SysTime()
        local fadeIn = (now - born) / 0.25
        local fadeOut = ends and (ends - now) / 0.6 or 1
        self:SetAlpha(255 * math.Clamp(math.min(fadeIn, fadeOut), 0, 1))
        if ends and now >= ends then self:Remove() return end
        fit(self)
    end
    title = panel:Add("DLabel")
    title:Dock(TOP)
    title:SetTall(px(26))
    title:SetFont(TITLE_FONT)
    title:SetTextColor(Color(ACCENT[1], ACCENT[2], ACCENT[3]))
    title:SetText(options.title or "RTX Remix")
    body = panel:Add("DLabel")
    body:Dock(TOP)
    body:SetFont(FONT)
    body:SetTextColor(Color(235, 237, 240))
    body:SetWrap(true)
    body:SetAutoStretchVertical(true)
    body:SetText(text)
    local close = panel:Add("DButton")
    close:SetText("\xC3\x97") -- the multiplication sign, as the Hotloader's notice uses
    close:SetFont(TITLE_FONT)
    close:SetSize(px(26), px(26))
    close.DoClick = function() panel:Remove() end
    panel.PerformLayout = function(self, w)
        close:SetPos(w - px(32), px(8))
        fit(self)
    end
    function panel:SetNoticeText(value) body:SetText(value) end
    function panel:SetNoticeProgress(fraction) progress = tonumber(fraction) end
    function panel:FinishNotice(after)
        ends = SysTime() + math.max(0.6, tonumber(after) or 0)
    end
    panel:SetPos(ScrW() - width - px(20), noticeTop(panel, width, px))
    panel:SetAlpha(0)
    if seconds > 0 then
        timer.Simple(seconds, function() if IsValid(panel) and ends and SysTime() >= ends - 0.05 then panel:Remove() end end)
    end
    return panel
end

NATIVELOADER_NOTICE = { Show = Show, SECONDS = SECONDS }
return NATIVELOADER_NOTICE
