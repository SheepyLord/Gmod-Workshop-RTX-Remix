-- authored_mod_probe.lua: client side of authored_mod_session.py. Reads the Remix texture hashes of the
-- crowbar's view model and of two props, and closes the package's own windows before a screenshot.
NLAM = NLAM or {}

local function hash(name)
    if not RemixMaterial or not RemixMaterial.GetTextureHash then return nil end
    local ok, _, text = pcall(RemixMaterial.GetTextureHash, name)
    if ok and isstring(text) then return text end
    return nil
end

local function materials(ent)
    local list = {}
    if not IsValid(ent) then return list end
    for _, name in ipairs(ent:GetMaterials() or {}) do
        local m = Material(name)
        local base = m and not m:IsError() and m:GetTexture("$basetexture")
        list[#list + 1] = { material = name, texture = base and base:GetName() or "", hash = hash(name) }
    end
    return list
end

local function viewmodel()
    local ply = LocalPlayer()
    if not (IsValid(ply) and ply.GetViewModel) then ply = Entity(1) end
    local vm = (IsValid(ply) and ply.GetViewModel) and ply:GetViewModel() or NULL
    if not IsValid(vm) then
        for _, e in ipairs(ents.GetAll()) do
            local class = e:GetClass()
            if class == "viewmodel" or class == "predicted_viewmodel" then vm = e break end
        end
    end
    return vm
end

function NLAM.Hashes(a, b)
    local ok, err = pcall(function()
        local out = { api = RemixMaterial ~= nil and RemixMaterial.GetTextureHash ~= nil, props = {} }
        local vm = viewmodel()
        out.viewmodel = { model = IsValid(vm) and vm:GetModel() or "", materials = materials(vm) }
        for _, index in ipairs({ a, b }) do
            local e = Entity(index)
            out.props[#out.props + 1] = { index = index, model = IsValid(e) and e:GetModel() or "", materials = materials(e) }
        end
        print("NLAM_HASHES " .. util.TableToJSON(out))
    end)
    if not ok then print("NLAM_HASHES " .. util.TableToJSON({ error = tostring(err) })) end
end

-- Closes the package's first-start guide and its other windows, so a screenshot shows the scene.
function NLAM.CloseUI()
    local closed = 0
    for _, p in ipairs(vgui.GetWorldPanel():GetChildren()) do
        if IsValid(p) and p.GetTitle then
            local ok, title = pcall(p.GetTitle, p)
            if ok and isstring(title) and (title:find("RTX", 1, true) or title:find("Remix", 1, true)) then
                p:Remove()
                closed = closed + 1
            end
        end
    end
    gui.EnableScreenClicker(false)
    print("NLAM_CLOSED " .. util.TableToJSON({ closed = closed }))
end

print("NLAM_INSTALLED {}")
