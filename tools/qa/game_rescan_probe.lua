-- game_rescan_session.py's client probe (ADR 0263, the user's report of 2026-11-24): imports a character through the
-- Model Hotloader's own library flow (so its MMDHL.Imported hook runs, as for the player's import), spawns it in view
-- and reports the RTX fixes' imported game PBR view of each of its materials. Sent by the driver through the console;
-- prints NLRS_* lines, writes each report to data/nlrescan/. Not installed anywhere.
NLRS = NLRS or {}
local Q = NLRS
local function emit(kind, value) print("NLRS_" .. kind .. " " .. util.TableToJSON(value or {})) end

-- The library's import ends in MMDHL.Imported (library.lua), which the RTX fixes' Lua also hooks.
hook.Add("MMDHL.Imported", "NLRS.Imported", function(id)
    if not Q.importing then return end
    Q.importing = nil
    emit("IMPORTED", { asset = id, source = Q.source })
end)

function Q.Import(source)
    Q.source, Q.importing = source, true
    local handle, err = mmdhl.native.BeginImport(source, mmdhl.library.CharacterImportOptions())
    if not mmdhl.library.StartImport(handle, err) then
        Q.importing = nil
        print("NLRS_ERROR import did not start: " .. tostring(err or mmdhl.library.status))
    end
end

function Q.Spawn(asset)
    local options = mmdhl.GetGlobalSettings()
    options.role, options.gender, options.frozen, options.weapon = "citizen", "female", true, "none"
    local ok, err = mmdhl.RequestSpawn(asset, options, function(state, message, index)
        if state == "ready" then emit("READY", { index = index })
        elseif state == "error" then print("NLRS_ERROR spawn " .. mmdhl.Localize(tostring(message))) end
    end)
    if not ok then print("NLRS_ERROR spawn " .. tostring(err)) end
end

-- A camera in front of the character, the whole of it in the shot, the HUD off, the first-run dialogs closed.
function Q.View(index)
    for _, panel in ipairs(vgui.GetWorldPanel():GetChildren()) do
        if IsValid(panel) and isfunction(panel.GetTitle) and isfunction(panel.Close) then panel:Close() end
    end
    -- The character's chest from its skeleton (a carrier's bounding box need not be where the model is drawn).
    local function chest(e)
        for _, name in ipairs({ "ValveBiped.Bip01_Spine2", "ValveBiped.Bip01_Spine1", "ValveBiped.Bip01_Pelvis" }) do
            local bone = e:LookupBone(name)
            local at = bone and e:GetBonePosition(bone)
            if at then return at end
        end
        return e:GetPos() + Vector(0, 0, 40)
    end
    -- The entity is looked up each frame: a character spawned a moment ago may reach the client after this is sent.
    hook.Add("CalcView", "NLRS.View", function()
        local e = Entity(index)
        if not IsValid(e) then return end
        local center = chest(e) - Vector(0, 0, 8)
        local facing = Angle(0, e:GetAngles().y, 0)
        local eye = center + facing:Forward() * 95 + facing:Right() * 22 + Vector(0, 0, 6)
        return { origin = eye, angles = (center - eye):Angle(), fov = 50, drawviewer = true }
    end)
    hook.Add("HUDShouldDraw", "NLRS.View", function() return false end)
    gui.HideGameUI()
end

-- The imported game PBR view of each material of the asset (MaterialPipeline.ToPBR.GetGameMaterial), counted by
-- state; the materials still converting (RTXGamePBRProgress, the RTX fixes' Lua); whether the module has the rescan.
-- The whole list goes to data/nlrescan/states_<n>.json, the counts to the console.
Q.reports = Q.reports or 0
function Q.States(asset)
    local p = MaterialPipeline and MaterialPipeline.ToPBR
    local info = mmdhl.assets and mmdhl.assets[asset]
    local materials, counts = {}, {}
    for _, part in ipairs(info and info.materials or {}) do
        local view = p and p.GetGameMaterial and p.GetGameMaterial(part.path) or {}
        local state = tostring(view.state or "absent")
        counts[state] = (counts[state] or 0) + 1
        materials[#materials + 1] = { path = part.path, state = state, family = view.family or "", error = view.error or "" }
    end
    local pending, batch = 0, 0
    if isfunction(RTXGamePBRProgress) then pending, batch = RTXGamePBRProgress() end
    Q.reports = Q.reports + 1
    file.CreateDir("nlrescan")
    file.Write("nlrescan/states_" .. string.format("%03d", Q.reports) .. ".json",
        util.TableToJSON({ asset = asset, materials = materials, counts = counts, pending = pending, batch = batch }, true))
    emit("STATES", { report = Q.reports, counts = counts, materials = #materials, pending = pending, batch = batch,
        rescan = p ~= nil and isfunction(p.RescanGameSource), loaded = info ~= nil })
end

-- The settings the driver changes for its screenshots, as they were, and putting them back before the game quits.
Q.saved = Q.saved or {}
for _, name in ipairs({ "nativeloader_sky_time_passes", "nativeloader_sky_time" }) do
    local cvar = GetConVar(name)
    if cvar and Q.saved[name] == nil then Q.saved[name] = cvar:GetString() end
end
function Q.Restore()
    for name, value in pairs(Q.saved) do RunConsoleCommand(name, value) end
    print("NLRS_RESTORED")
end

emit("INSTALLED", { library = istable(mmdhl) and istable(mmdhl.library), topbr = MaterialPipeline ~= nil and MaterialPipeline.ToPBR ~= nil })
