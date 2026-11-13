local Math = include("nlvr/modules/sh_tools_math.lua")
local Presentation = include("nlvr/modules/cl_tools_presentation.lua")
local Wheel = {}
function Wheel.New(ctx, controls)
    local base = weapons.GetStored("weapon_base")
    local baseSelection = base and base.DrawWeaponSelection
    local baseIcon = base and base.WepSelectIcon
    local self = {open = false, page = 1}
    local paints = 0
    local display, inventoryAt = nil, 0
    local debug = {entries = {}}
    local members = {}
    local noticeUntil = 0
    local overlay, entries, rows, pages, origin, angle, hand, highlighted, queued, latch, cancelled
    local function describe(weapon)
        if not IsValid(weapon) then return end
        local class = weapon:GetClass()
        local name = weapon.GetPrintName and weapon:GetPrintName() or weapon.PrintName or class
        if class == "nlvr_hands" then name = "Hands" end
        name = language.GetPhrase((name or class):gsub("^#", ""))
        return {class = class, name = name, ent = weapon, slot = weapon.GetSlot and weapon:GetSlot() or weapon.Slot or 0,
            position = weapon.GetSlotPos and weapon:GetSlotPos() or weapon.SlotPos or 0,
            icon = weapon.WepSelectIcon ~= baseIcon and weapon.WepSelectIcon or nil,
            drawSelection = weapon.DrawWeaponSelection ~= baseSelection and weapon.DrawWeaponSelection or nil}
    end
    local function inventory()
        local list = Math.Entries(LocalPlayer():GetWeapons(), describe)
        return list
    end
    local function fit(text, width, font)
        surface.SetFont(font)
        while surface.GetTextSize(text) > width and #text > 0 do
            local shorter = text:gsub("[%z\1-\127\194-\244][\128-\191]*$", "")
            if shorter == text then return "" end
            text = shorter
        end
        return text
    end
    local function paint(_, w, h)
        paints = paints + 1
        surface.SetDrawColor(10, 18, 28, 238) surface.DrawRect(0, 0, w, h)
        if self.notice then
            draw.SimpleText("Could not select", "NLVRToolsTitle", w / 2, h / 2 - 35, Color(255, 190, 150), TEXT_ALIGN_CENTER)
            draw.SimpleText(fit(self.notice, w - 60, "NLVRToolsName"), "NLVRToolsName", w / 2, h / 2 + 12, color_white, TEXT_ALIGN_CENTER)
            return
        end
        local title = highlighted and entries[highlighted].name or (NATIVELOADER_I18N and NATIVELOADER_I18N.L("Weapons") or "Weapons")
        draw.SimpleText(fit(title, 390, "NLVRToolsTitle"), "NLVRToolsTitle", w / 2, h / 2 - 50, Color(170, 221, 242), TEXT_ALIGN_CENTER)
        draw.SimpleText(self.page .. " / " .. pages, "NLVRToolsName", w / 2, h / 2, color_white, TEXT_ALIGN_CENTER)
        draw.SimpleText("Release B to select", "NLVRToolsName", w / 2, h / 2 + 36, color_white, TEXT_ALIGN_CENTER)
        if pages > 1 then draw.SimpleText("Move above / below ring for pages", "NLVRToolsSmall", w / 2, h / 2 + 74, color_white, TEXT_ALIGN_CENTER) end
        for _, row in ipairs(rows) do
            local entry = entries[row.index]
            local x, y = w / 2 + row.x * w * 0.35, h / 2 - row.y * h * 0.35
            surface.SetDrawColor(row.index == highlighted and Color(33, 121, 161, 250) or Color(28, 42, 57, 250))
            surface.DrawRect(x - 84, y - 60, 168, 120)
            local custom = false
            if type(entry.drawSelection) == "function" and not entry.iconError then
                render.SetScissorRect(x - 60, y - 54, x + 60, y + 6, true)
                custom = pcall(entry.drawSelection, entry.ent, x - 60, y - 54, 120, 60, 255)
                render.SetScissorRect(0, 0, 0, 0, false)
                entry.iconError = not custom
            end
            if custom then
                -- The SWEP drew its real selection icon.
            elseif type(entry.icon) == "number" and entry.icon > 0 then
                surface.SetDrawColor(235, 244, 255, 255) surface.SetTexture(entry.icon)
                surface.DrawTexturedRect(x - 60, y - 54, 120, 60)
            elseif entry.glyph then
                draw.SimpleText(entry.glyph, "NLVRToolsHL2", x, y - 54, Color(240, 213, 118), TEXT_ALIGN_CENTER)
            else
                draw.SimpleText(entry.class == "nlvr_hands" and "[ ]" or tostring(entry.slot + 1), "NLVRToolsTitle", x, y - 45, color_white, TEXT_ALIGN_CENTER)
            end
            -- Elide visually, retain the complete class/name in the probe.
            local label = fit(entry.name, 156, "NLVRToolsName")
            draw.SimpleText(label, "NLVRToolsName", x, y + 23, color_white, TEXT_ALIGN_CENTER)
        end
    end
    local glyphs = {weapon_crowbar = "c", weapon_stunstick = "n", weapon_pistol = "d", weapon_357 = "e",
        weapon_smg1 = "a", weapon_ar2 = "l", weapon_shotgun = "b", weapon_crossbow = "g", weapon_rpg = "i",
        weapon_frag = "k", weapon_physcannon = "m", weapon_physgun = "h", weapon_bugbait = "j"}
    local function layout()
        rows, pages, self.page = Math.Layout(#entries, self.page)
        for _, entry in ipairs(entries) do entry.glyph = glyphs[entry.class] end
    end
    function self.Close(select)
        if select and highlighted and entries[highlighted] and IsValid(entries[highlighted].ent) then
            queued = {ent = entries[highlighted].ent, name = entries[highlighted].name, expires = RealTime() + 1, attempted = false}
            self.selected = entries[highlighted].class
            self.selectionError = nil
        end
        self.open, highlighted = false, nil
        if display then display.Show(false) end
    end
    function self.Frame()
        local input, player = ctx.Input, LocalPlayer()
        if self.notice and RealTime() >= noticeUntil then self.notice = nil if display and not self.open then display.Show(false) end end
        local pose, head = ctx.Pose[input.mainHand], ctx.Pose.head
        if not input.main.b then cancelled = nil end
        if not IsValid(player) or not player:Alive() or not pose or not pose.valid or not head or not head.valid then
            if self.open then cancelled = true end
            self.Close(false) queued = nil self.notice = nil return
        end
        if self.open and hand ~= input.mainHand then self.Close(false) cancelled = true end
        local bOwner = input.Owner("main", "b")
        if self.open and bOwner and bOwner ~= ctx.name then
            self.Close(false) queued = nil cancelled = true
        end
        -- K can retain an earlier tap until native readiness. A new hold must not
        -- consume that pending reload or operate a control another module owns.
        if not self.open and not cancelled and (not bOwner or bOwner == ctx.name) and input.Held("main", "b", 0.3) then
            queued, self.notice = nil, nil
            entries = inventory()
            members = {} for _, entry in ipairs(entries) do members[entry.ent] = true end
            debug.entries = {} for _, entry in ipairs(entries) do debug.entries[#debug.entries + 1] = {class = entry.class, name = entry.name, slot = entry.slot, position = entry.position} end
            inventoryAt = RealTime() + 0.25
            if #entries == 0 then return end
            hand, origin = input.mainHand, Vector(pose.pos.x, pose.pos.y, pose.pos.z)
            angle = (origin - head.pos):Angle() angle.r = 0
            self.page, latch, highlighted = 1, false, nil layout()
            if not overlay then
                local size = ctx.Overlay.Sizes.wheel
                overlay = ctx.Overlay.New{key = "wheel", name = "Weapon wheel", width = size[1], height = size[2], paint = paint}
                display = Presentation.New(overlay)
            end
            local p, a = ctx.ToTracking(origin, angle)
            display.Place(p, a, 0.42) overlay:Invalidate() display.Show(true)
            self.open = true
        end
        if self.open then
            input.Claim("main", "b", ctx.name)
            -- W owns armed triggers. The final mover also consumes its command button, without stealing a claim.
            input.Claim("main", "trigger", ctx.name)
            controls.Trigger(input.mainHand)
            local p, a = ctx.ToTracking(origin, angle)
            display.Place(p, a, 0.42)
            if not input.main.b then self.Close(true) return end
            local invalid = false
            for _, entry in ipairs(entries) do if not IsValid(entry.ent) then invalid = true break end end
            if invalid or RealTime() >= inventoryAt then
                inventoryAt = RealTime() + 0.25
                local weapons = player:GetWeapons()
                local same = #weapons == #entries
                for _, weapon in ipairs(weapons) do if not members[weapon] or not IsValid(weapon) then same = false break end end
                if invalid or not same then
                    entries = Math.Entries(weapons, describe) highlighted = nil layout()
                    members, debug.entries = {}, {}
                    for _, entry in ipairs(entries) do
                        members[entry.ent] = true
                        debug.entries[#debug.entries + 1] = {class = entry.class, name = entry.name, slot = entry.slot, position = entry.position}
                    end
                    overlay:Invalidate()
                end
            end
            local delta = (pose.pos - origin) / ctx.Space.scale
            local x, y = delta:Dot(angle:Right()), delta:Dot(angle:Up())
            local page, changed
            page, latch, changed = Math.Page(self.page, pages, x, y, latch)
            if changed then self.page = page layout() overlay:Invalidate() end
            local pick = not latch and Math.Pick(#entries, self.page, x, y) or nil
            if pick ~= highlighted then highlighted = pick overlay:Invalidate() end
        end
    end
    function self.Move(cmd)
        if self.open then cmd:SetButtons(bit.band(cmd:GetButtons(), bit.bnot(bit.bor(IN_ATTACK, IN_ATTACK2, IN_RELOAD)))) end
        controls.Move(cmd)
        if queued then
            local player = LocalPlayer()
            if not IsValid(queued.ent) or queued.ent:GetOwner() ~= player or not IsValid(player) or not player:Alive() then
                queued = nil
            elseif player:GetActiveWeapon() == queued.ent then
                self.confirmed = self.selected queued = nil
            elseif RealTime() > queued.expires then
                self.selectionError, self.notice = "refused", queued.name
                noticeUntil = RealTime() + 2 queued = nil
                if overlay then overlay:Invalidate() display.Show(true) end
                debug.selection_error, debug.notice = self.selectionError, self.notice
            elseif not queued.attempted and (not cmd.CommandNumber or cmd:CommandNumber() ~= 0) and
                (not cmd.TickCount or cmd:TickCount() ~= 0) then
                cmd:SelectWeapon(queued.ent) queued.attempted = true
            end
        end
        debug.pending, debug.confirmed = queued ~= nil, self.confirmed
    end
    function self.Debug()
        debug.open, debug.page, debug.pages = self.open, self.page, pages
        debug.highlighted, debug.selected, debug.confirmed = highlighted, self.selected, self.confirmed
        debug.pending, debug.selection_error, debug.notice = queued ~= nil, self.selectionError, self.notice
        debug.origin, debug.angle, debug.handle, debug.paints = origin, angle, overlay and overlay.handle, paints
        return debug
    end
    function self.Stop() self.Close(false) queued = nil if overlay then overlay:Destroy() overlay = nil end end
    return self
end
return Wheel
