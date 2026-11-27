-- Native Derma forms use the spawn menu's width, scrolling, fonts and input scaling.
local i18n = include("nativeloader/i18n.lua")
local L, N = i18n.L, i18n.N

-- A tenth of the track covers clear air to 50 m. Equal distances on the rest multiply
-- visibility by equal factors. The number box always reads and accepts actual metres.
local function visibilityFraction(m)
    if m <= 50 then return m / 500 end
    return 0.1 + 0.9 * math.log(m / 50) / math.log(1000)
end
local function visibilityMetres(x)
    if x <= 0.1 then return 500 * x end
    return 50 * 1000 ^ ((x - 0.1) / 0.9)
end

local function addControl(form, ed, f, readers)
    local label, sync, last = L(f.label), false, nil
    local show
    if f.kind == "bool" then
        local box = form:CheckBox(label)
        box.OnChange = function(_, on) if not sync then ed.write(f, on) end end
        show = function(v) box:SetValue(v and 1 or 0) end
    elseif f.kind == "colour" then
        form:Help(label)
        local mix = vgui.Create("DColorMixer", form)
        mix:SetPalette(false)
        mix:SetAlphaBar(false)
        mix:SetWangs(false)
        mix:SetTall(draw.GetFontHeight("DermaDefault") * 4)
        form:AddItem(mix)
        mix.ValueChanged = function(_, c)
            if not sync then ed.write(f, {c.r / 255, c.g / 255, c.b / 255}) end
        end
        form:Help(L("Red, green, blue (0 to 1). Press Enter to apply."))
        local rgb = vgui.Create("DTextEntry", form)
        form:AddItem(rgb)
        rgb.OnEnter = function(self)
            if not ed.writeColour(f, self:GetValue()) then self:SetText(f.cv:GetString()) end
        end
        show = function(v)
            mix:SetColor(Color(math.floor(v[1] * 255 + 0.5), math.floor(v[2] * 255 + 0.5), math.floor(v[3] * 255 + 0.5)))
            rgb:SetText(f.cv:GetString())
        end
    elseif f.kind == "mist" then
        local box = form:ComboBox(label)
        local labels = {L("Enhanced mist"), L("Remix fog near you"), L("Off")}
        box:SetSortItems(false)
        for i, title in ipairs(labels) do box:AddChoice(title, i - 1) end
        box.OnSelect = function(_, _, _, data) if not sync then ed.write(f, data) end end
        show = function(v) box:SetValue(labels[v + 1]) end
    else
        local slider = form:NumSlider(label, nil, f.min, f.max, f.decimals)
        local function sliderValue(v)
            if f.kind == "absorption" then return v[1] / f.unit end
            return v
        end
        slider:SetDefaultValue(sliderValue(f.default))
        local units = 10 ^ f.decimals
        local toFraction, fromFraction
        if f.kind == "visibility" then
            toFraction, fromFraction = visibilityFraction, visibilityMetres
        elseif f.kind == "haze" then
            -- log(1 + density) gives the common 0–10 range just over half of the 0–100 track.
            local span = math.log(1 + f.max)
            toFraction = function(density) return math.log(1 + density) / span end
            fromFraction = function(x) return math.exp(x * span) - 1 end
        end
        if toFraction then
            slider.Scratch.GetFraction = function(s) return toFraction(s:GetFloatValue()) end
            slider.TranslateSliderValues = function(s, x, y)
                s:SetValue(math.floor(fromFraction(x) * units + 0.5) / units)
                return toFraction(s:GetValue()), y
            end
        end
        slider.OnValueChanged = function(_, v)
            if sync then return end
            last = nil -- a look can restore the previously shown value before the next panel refresh
            v = math.floor(v * units + 0.5) / units
            if f.kind == "absorption" then
                local coefficient = v * f.unit
                ed.write(f, {coefficient, coefficient, coefficient})
            else
                ed.write(f, v)
            end
        end
        show = function(v) slider:SetValue(sliderValue(v)) end
    end
    form:ControlHelp(L(f.help))
    local function read()
        local text = f.cv:GetString()
        if last == text then return end
        sync = true
        show(ed.value(f))
        sync, last = false, text
    end
    readers[#readers + 1] = read
    read()
end

local function group(panel, title, fields, ed, readers, open)
    local form = vgui.Create("DForm", panel)
    form:SetName(L(title))
    i18n.PreparePanel(form)
    form:SetExpanded(open)
    panel:AddItem(form)
    local built = false
    local function populate()
        if built then return end
        built = true
        for _, f in ipairs(fields) do addControl(form, ed, f, readers) end
        form:InvalidateLayout(true)
    end
    form.OnToggle = function(_, expanded) if expanded then populate() end end
    if open then populate() end
    return form
end

return function(panel, ed, weathers, weatherName, inVR, quality)
    local state = panel:Help("")
    local switch = panel:Button(L("Switch to Enhanced"), "nativeloader_sky_enhanced", "1")
    -- DForm docks a padded DSizeToContents row around each control. The row owns the space.
    local stateRow, switchRow = state:GetParent(), switch:GetParent()
    local own = panel:CheckBox(L("My own look"), "nativeloader_sky_own_look")
    local readers, lastState, lastFog, revision = {}, nil, nil, nil
    local function refresh()
        local status = inVR() and "vr" or (not quality:GetBool() and "standard" or
            (NATIVELOADER_SKY.enhanced() and "enhanced" or "map"))
        local fogOverride = hook.Run("NativeLoaderRemixFogOverride") == true
        if status ~= lastState or fogOverride ~= lastFog then
            local msg = status == "vr" and L("Enhanced sky is unavailable in VR. The RTX sky uses Standard.")
                or (status == "standard" and L("These settings shape the Enhanced sky. Switch to Enhanced to see your edits.")
                or (status == "map" and NATIVELOADER_SKY.line(true) or ""))
            if fogOverride then
                local fogText = L("A Remix fog preset is active. Clear it on the Remix settings page to see this look's fog.")
                msg = msg ~= "" and (msg .. " " .. fogText) or fogText
            end
            state:SetText(msg)
            stateRow:SetVisible(msg ~= "")
            switchRow:SetVisible(status == "standard")
            lastState, lastFog = status, fogOverride
            if msg ~= "" then
                state:InvalidateLayout(true)
                stateRow:InvalidateLayout(true)
            end
            panel:InvalidateLayout(true)
            panel:InvalidateParent(true)
        end
        if revision ~= ed.revision then
            for _, read in ipairs(readers) do read() end
            revision = ed.revision
        end
    end
    -- The checkbox lives as long as these controls, including when the page is rebuilt.
    local think = own.Think
    own.Think = function(self) if think then think(self) end refresh() end
    panel:ControlHelp(L("Editing a cloud or air setting turns on your look. Turn it off to follow the weather again. The weather always controls rain, snow and sand."))
    group(panel, N("Light and mist"), ed.style, ed, readers, false)

    local start = panel:ComboBox(L("Start from"))
    start:SetSortItems(false)
    local selected, feedback, remove
    local function say(message) if IsValid(feedback) then feedback:SetText(message or "") end end
    local function choices()
        start:Clear()
        start:SetValue(L("Choose a look"))
        for _, w in ipairs(weathers) do start:AddChoice(L(w[1]), {values = ed.weather(w[2])}) end
        start:AddSpacer()
        for _, item in ipairs(ed.builtins) do start:AddChoice(L(item.name), {values = ed.builtin(item)}) end
        local names = ed.names()
        if #names > 0 then start:AddSpacer() end
        for _, id in ipairs(names) do start:AddChoice(string.format(L("My look (%s)"), id), {id = id}) end
    end
    panel:ControlHelp(L("Choosing a starting look copies it into the controls. Light and mist settings apply to every look."))
    start.OnSelect = function(_, _, _, item)
        local values, err = item.values, nil
        if item.id then values, err = ed.read(item.id) end
        if not values or not ed.load(values) then say(err or L("The look could not be loaded.")) return end
        selected = item.id
        remove:SetEnabled(selected ~= nil)
        say("")
    end
    choices()
    panel:Button(L("Reset to current weather")).DoClick = function()
        local name = weatherName()
        if not name then say(L("Choose a weather on the Sky page to reset to its look.")) return end
        ed.load(ed.weather(name))
        selected = nil
        remove:SetEnabled(false)
        start:SetValue(L("Choose a look"))
        say("")
    end
    local function save(name, replace)
        local id, err = ed.save(name, replace)
        if not id then say(err) return end
        selected = id
        choices()
        start:SetValue(string.format(L("My look (%s)"), id))
        remove:SetEnabled(true)
        say(string.format(L("Look saved as %s."), id))
    end
    panel:Button(L("Save as")).DoClick = function()
        Derma_StringRequest(L("Save as"), L("Use letters A to Z, numbers, hyphens or underscores, up to 32 characters."), selected or "", function(name)
            if ed.exists(name) then
                Derma_Query(string.format(L("Replace saved look %s?"), name), L("Save as"),
                    L("Replace"), function() save(name, true) end, L("Cancel"))
            else save(name, false) end
        end)
    end
    remove = panel:Button(L("Delete saved look"))
    remove:SetEnabled(false)
    remove.DoClick = function()
        local id = selected
        if not id then return end
        Derma_Query(string.format(L("Delete saved look %s?"), id), L("Delete saved look"), L("Delete"), function()
            local ok, err = ed.delete(id)
            if not ok then say(err) return end
            selected = nil
            choices()
            remove:SetEnabled(false)
            say(string.format(L("Deleted %s. Your current settings are still in the editor."), id))
        end, L("Cancel"))
    end
    panel:Button(L("Copy look as text")).DoClick = function()
        SetClipboardText(ed.encode())
        say(L("Look copied. Paste the line into another Enhanced sky editor to use it."))
    end
    panel:Button(L("Paste a look")).DoClick = function()
        Derma_StringRequest(L("Paste a look"), L("Paste the line from Copy look as text."), "", function(text)
            local values, err = ed.decode(text, "pasted text")
            if not values then say(err) return end
            ed.load(values)
            selected = nil
            start:SetValue(L("Choose a look"))
            remove:SetEnabled(false)
            say(L("Pasted look loaded. Use Save as to keep a named copy."))
        end)
    end
    feedback = panel:Help("")
    for i, section in ipairs(ed.groups) do group(panel, section[1], section[2], ed, readers, i == 1) end
    refresh()
end
