-- Supplement M's short settings capture with S's actual module/settings/visible-control receipts.
local ID, active, recorded, first = "vr_v4_scaffold_probe", false, false, true
local function emit(name, data) data.kind, data.name = "v4s", name print("NLVR_Q " .. util.TableToJSON(data)) end
local function tree(p, fn)
    if not IsValid(p) then return end
    if fn(p) then return p end
    for _, child in ipairs(p:GetChildren()) do local value = tree(child, fn) if value then return value end end
end
local names = {"physical_reload", "foregrip", "ammo_counter", "gun_angle"}
hook.Add("PreRender", ID, function()
    if not NLVR then
        if active then
            hook.Remove("PreRender", ID)
            emit("stopped", {global_absent = NLVR == nil})
        end
        return
    end
    if first then
        first, active = false, true
        local modules, settings = {}, {}
        for _, entry in ipairs(NLVR.Registry.entries) do
            modules[#modules + 1] = {name = entry.module.name, order = entry.module.order, active = entry.active}
        end
        for _, name in ipairs(names) do settings[name] = NLVR.Settings[name] end
        emit("started", {modules = modules, settings = settings, window = {ScrW(), ScrH()}})
    end
    local root = tree(vgui.GetWorldPanel(), function(p) return p.NLVRPanel == "settings" end)
    if not root or recorded then return end
    local scroll = tree(root, function(p) return p:GetName() == "DScrollPanel" end)
    local label = tree(root, function(p) return p.GetText and p:GetText() == NATIVELOADER_I18N.L("Weapons") end)
    if not scroll or not label or not scroll:GetVBar().Enabled then return end
    scroll:GetVBar():SetScroll(100000) -- expose the final group, without changing the page or the scaler
    local guiScale = GetConVar("guiscaler_scale_multiplier")
    recorded = true
    emit("weapons-page", {width = root:GetWide(), height = root:GetTall(),
        scroll = scroll:GetVBar():GetScroll(), gui_scale = guiScale and guiScale:GetString()})
end)
