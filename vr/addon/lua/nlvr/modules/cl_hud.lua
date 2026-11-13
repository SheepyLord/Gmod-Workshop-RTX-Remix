local module = {name = "hud", order = 10}
local overlay, previous, values, copied, failures, lastError, core
local function hud_values()
    local player = LocalPlayer()
    if not IsValid(player) then return end
    local weapon = player:GetActiveWeapon()
    local clip, reserve = -1, -1
    if IsValid(weapon) then
        clip = weapon:Clip1()
        local ammo = weapon:GetPrimaryAmmoType()
        if ammo >= 0 then reserve = player:GetAmmoCount(ammo) end
    end
    return {player:Health(), player:Armor(), clip, reserve}
end
function module.Start(ctx)
    core, previous, copied, failures, lastError = ctx.core, nil, false, 0, nil
    surface.CreateFont("NLVRWristLabel", {font = "Tahoma", size = 33, weight = 600, extended = true})
    surface.CreateFont("NLVRWristValue", {font = "Tahoma", size = 63, weight = 700, extended = true})
    overlay = core.Overlay.New{key = "wrist", name = "RTX VR wrist HUD", width = 769, height = 257,
        device = core.Input.offHand, pos = Vector(0, 0, 0.065), ang = Angle(0, 0, 90), metres = 0.23, clear = {12, 18, 26, 235},
        paint = function(_, width)
            -- Keep the V1 canvas, text and alpha exactly; the manager owns the RT/2D scopes.
            if not values then return end
            local i18n = NATIVELOADER_I18N
            local function word(text) return i18n and i18n.L(text) or text end
            local labels = NativeLoaderVR.WristLabels
            local ammo = values[3] >= 0 and tostring(values[3]) or "-"
            if values[4] >= 0 then ammo = ammo .. " / " .. values[4] end
            for i, value in ipairs({tostring(values[1]), tostring(values[2]), ammo}) do
                local x = (i - 0.5) * width / 3
                draw.SimpleText(word(labels[i]), "NLVRWristLabel", x, 34, Color(164, 213, 229), TEXT_ALIGN_CENTER)
                draw.SimpleText(value, "NLVRWristValue", x, 105, color_white, TEXT_ALIGN_CENTER)
            end
        end}
    overlay:Show(core.Settings.wrist_hud == 1)
    ctx.On("setting", function(name)
        if name == "wrist_hud" then overlay:Show(core.Settings.wrist_hud == 1) end
        if name == "dominant" then overlay:Place(core.Input.offHand, overlay.pos, overlay.ang, overlay.metres) end
    end)
    ctx.On("before_overlay_paint", function()
        values = hud_values()
        if not values then return end
        if not copied then
            local info, detail = ctx.native.Info()
            if detail then
                local message = tostring(detail)
                if message ~= lastError then MsgN("[nativeloader] VR wrist: " .. message) lastError = message end
                failures = failures + 1
                if failures >= 30 then core.Fail(message) return end
            else failures, lastError = 0, nil end
            copied = info and (tonumber(info.overlayUpdates) or 0) > 0 or false
        end
        local changed = not previous
        if previous then for i = 1, 4 do if values[i] ~= previous[i] then changed = true break end end end
        if changed or not copied then overlay:Invalidate() end
        previous = values
    end)
end
function module.Stop()
    if overlay then overlay:Destroy() end
    overlay, previous, values, core = nil, nil, nil, nil
end
return module
