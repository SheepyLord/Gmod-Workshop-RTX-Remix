if not CLIENT then return end
if not RTXPatcher then return end

-- ARC9 Weapon Base under RTX Remix (R24 and R25, the native-loader project).
--
-- 1. The DirectX warning. RTX sessions run Source at DirectX level 80, so ARC9 opened its "BAD GMOD SETTINGS"
--    window on the first deploy of any ARC9 weapon; its advice (-dxlevel 95) does not apply to a path-traced
--    renderer. Its DirectX check answers "fine" in RTX sessions: ARC9's own setting (arc9_ignore_dx) and every
--    other check it makes are left as they are.
-- 2. Parts dressed by sub-materials. Under RTX a client-side model's SetMaterial/SetSubMaterial does not change what
--    draws (R7), and ARC9 dresses parts that way: a sticker's model has no material of its own (the error material:
--    a white plate z-fighting with the receiver), and a gun screen charm puts its live screen on index 2. While ARC9
--    draws its custom models, those parts are drawn through render.MaterialOverrideByIndex instead, which does reach
--    the image; the sticker materials also go through the view model material pass, which makes them Remix decals.
-- 3. Gun screens. Their render target is black in the path-traced image; the companion's screen redraw draws them as
--    2D in the HUD pass, as it does the toolgun's screen.
-- 4. Magnified scopes (R25). ARC9 draws a scope's picture with a second view of the world into a render target and
--    puts it on the lens through screen-space shaders RTX cannot run: the lens showed the error material and nothing
--    was magnified. Under RTX the lens is drawn with a render target of this patch's own that the RTX runtime treats
--    as a raytraced render target: rays that hit the lens go on from the scope's camera (ahead of the eye, looking
--    where it looks, with ARC9's field of view), so the picture through the scope is path traced. One empty triangle
--    drawn into that target each frame gives the runtime that camera; no second view of the world is drawn. The lens
--    is a copy of the scope model's lens mesh, just in front of it, whose texture coordinates are its place on the
--    screen mapped as ARC9 maps its picture (a square of the screen's height in the middle), so the magnification
--    is ARC9's. The model's own lens is black, as ARC9 shows a lens nobody looks through. The reticle is drawn over
--    the lens as 2D, after the view model and the path-traced image, where ARC9's reticle would be.
-- 5. ARC9's screen-space work around the view model (R25). The RTX runtime path traces a frame up to its first 2D
--    draw or read of the screen and rasterizes everything after it. ARC9 reads the screen just before its gun every
--    frame (its sight blur), and draws 2D there in its customization view and with its blur options: those reads and
--    draws are skipped in RTX sessions, and the screen is read once after the view models instead. Its holosights
--    (a read) and the view model's lens flares (2D) are drawn after the view models too. Its sight blur drew the scope
--    again, black with a white lens, into a mask target the render guard leaves inert, so the copy went into the image
--    over the real scope: the sight blur and its mask are skipped in RTX sessions too.
local Patcher = RTXPatcher

local function createClientConVar(name, default, help)
    if CreateClientConVar then
        local convar = CreateClientConVar(name, default, true, false, help)
        if convar then return convar end
    end
    if GetConVar then
        local convar = GetConVar(name)
        if convar then return convar end
    end
    return {
        GetBool = function() return tostring(default) ~= "0" end,
        GetInt = function() return tonumber(default) or 0 end,
        GetString = function() return tostring(default) end,
    }
end

local cvEnabled = createClientConVar("rtx_patcher_arc9", "1", "Enable ARC9 RTX Remix compatibility patches")
local cvDxWarning = createClientConVar("rtx_patcher_arc9_dx_warning", "0",
    "Show ARC9's DirectX level warning in RTX sessions (it does not apply to RTX Remix)")
local cvParts = createClientConVar("rtx_patcher_arc9_parts", "1",
    "Draw ARC9 stickers and gun screens with their materials in RTX sessions")
local cvScopes = createClientConVar("rtx_patcher_arc9_scopes", "1",
    "Path-trace ARC9's magnified scopes in RTX sessions (0: ARC9's own scope pictures, which RTX cannot show)")
local cvScopeHash = createClientConVar("rtx_patcher_arc9_scope_hash", "",
    "The scope target's descriptor hash for the RTX runtime (0x...; empty: the one this patch was measured with)")

Patcher.ARC9 = Patcher.ARC9 or {}
local ARC9Patch = Patcher.ARC9
local GUNSCREEN = "effects/arc9/gunscreen"
local SCREEN_INDEX = 2
local materials = {}
local function material(name)
    local found = materials[name]
    if found == nil then
        found = Material(name)
        if found:IsError() then found = false end
        materials[name] = found
    end
    return found or nil
end

function ARC9Patch.IsReady()
    if type(ARC9) ~= "table" then return false, "ARC9 missing" end
    if type(ARC9.BadConfigStuff) ~= "table" then return false, "ARC9.BadConfigStuff missing" end
    if not weapons or type(weapons.GetStored) ~= "function" or not weapons.GetStored("arc9_base") then
        return false, "arc9_base missing"
    end
    return true, { base = weapons.GetStored("arc9_base") }
end

function ARC9Patch.PatchDirectXWarning()
    local dx = ARC9.BadConfigStuff and ARC9.BadConfigStuff.dx
    if type(dx) ~= "table" or type(dx.cause) ~= "function" then return false, "no DirectX check" end
    return Patcher.InterceptFunction(dx, "cause", {
        patchId = "arc9",
        id = "dx_warning",
        around = function(original, ...)
            if cvDxWarning:GetBool() then return original(...) end
            return false
        end
    })
end

local function category(atttbl, name)
    local value = istable(atttbl) and atttbl.Category
    if value == name then return true end
    if istable(value) then
        for _, item in ipairs(value) do if item == name then return true end end
    end
    return false
end

-- The material of each sub-material index a part is dressed with, from ARC9's own tables (a client-side model's
-- GetSubMaterial reads back nothing). Nil for an ordinary part.
function ARC9Patch.PartMaterials(weapon, model)
    local slottbl = model.slottbl
    if not istable(slottbl) or type(weapon.GetFinalAttTable) ~= "function" then return nil end
    local ok, atttbl = pcall(weapon.GetFinalAttTable, weapon, slottbl)
    if not ok or not istable(atttbl) then return nil end
    if slottbl.StickerModel and isstring(atttbl.StickerMaterial) then
        local sticker = material(atttbl.StickerMaterial)
        if not sticker then return nil end
        model.NLARC9Sticker = atttbl.StickerMaterial
        return { [0] = sticker, [1] = sticker, [2] = sticker }
    end
    if category(atttbl, "gunscreen") and isfunction(atttbl.DrawFunc) then
        model.NLARC9GunScreen = true
        local screen = material(GUNSCREEN)
        return screen and { [SCREEN_INDEX] = screen } or nil
    end
    return nil
end

-- 4. Magnified scopes ----------------------------------------------------------------------------------------------

local SCOPE_TARGET = "nativeloader_arc9_scope_v1"
-- Only the camera drawn into the target matters (the runtime sends the rays on from it; nothing samples its pixels).
-- An unusual size: every target with the same description shares its hash, and the runtime would treat that one as
-- raytraced too. The camera's square viewport is the target's height; the rest is never drawn.
local SCOPE_W, SCOPE_H = 1016, 508
-- GMod names no IMAGE_FORMAT_BGRX8888 (the global is nil): Source's value. The render guard reviews it.
local FORMAT_BGRX8888 = 16
-- The RTX runtime knows a raytraced render target by Remix's descriptor hash of its D3D9 texture (XXH3-64 over
-- D3D9_COMMON_TEXTURE_DESC): this target's is 1016 x 508, one level, D3DUSAGE_RENDERTARGET, D3DFMT_X8R8G8B8 (what
-- Source makes of its BGRX8888), D3DPOOL_DEFAULT. Set through RemixConfig, it joins the hashes already in
-- rtx.raytracedRenderTargetTextures (in the runtime's user layer: the RTX menu then counts it as a changed setting).
local SCOPE_HASH = "0x9F721457A944740A"
-- A small black target of its own: the black lens's and the camera triangle's texture. A shared file texture (a plain
-- white or black one) has the hash of every identical texture, and a category the fixes give it would reach them all.
local BLACK_TARGET = "nativeloader_arc9_scope_black_v1"
-- The runtime draws the view model scaled towards the eye (rtx.viewModel.scale, 0.25 in the package's settings), and
-- rays that go on from the lens can still meet it: the scope's camera starts just past the gun's front, at least
-- ARC9's own near plane (8 units) ahead of the eye.
local VIEWMODEL_SCALE = 0.25
local AHEAD_MIN, AHEAD_MARGIN, AHEAD_MAX = 8, 2, 24
-- A part further than this from the eye is not where ARC9 draws it this frame (a model it has not placed sits where it
-- was made); a gun reaches well under it in view model space.
local PART_RANGE = 128
-- The lens copy sits this far in front of the model's lens, towards the eye, so the rays meet it first.
local LENS_LIFT = 0.1
-- The runtime wraps texture coordinates; a lens partly outside ARC9's square keeps its edge there instead.
local EDGE = 0.001
local MAX_LENS_VERTICES = 2048
local MATERIAL_VAR_ADDITIVE = 128

local scope = { stats = {} }
ARC9Patch.Scope = scope

-- On, and a runtime that can take a raytraced render target through RemixConfig.
local function scopesOn()
    if not cvEnabled:GetBool() or not cvScopes:GetBool() then return false end
    if scope.ready == false then return false end
    return istable(RemixConfig) and isfunction(RemixConfig.SetConfigVariable)
end
ARC9Patch.ScopesOn = scopesOn

local function scopeHash()
    local custom = cvScopeHash.GetString and cvScopeHash:GetString() or ""
    if isstring(custom) and custom:match("^0[xX]%x+$") then return custom end
    return SCOPE_HASH
end

-- The targets and materials, made the first time a magnified scope is used (never for players who use none). False
-- when the runtime does not take the target: ARC9's own scopes are then left as they are for the session.
local function scopeReady()
    if scope.ready ~= nil then return scope.ready end
    scope.ready = false
    if not istable(RemixConfig) or not isfunction(RemixConfig.SetConfigVariable) then
        scope.reason = "no RemixConfig.SetConfigVariable"
        return false
    end
    if not GetRenderTargetEx or not CreateMaterial or not mesh or not render.PushRenderTarget then
        scope.reason = "no render target API"
        return false
    end
    local made, target = pcall(GetRenderTargetEx, SCOPE_TARGET, SCOPE_W, SCOPE_H, RT_SIZE_LITERAL,
        MATERIAL_RT_DEPTH_SEPARATE, bit.bor(4, 8, 256, 512), 0, FORMAT_BGRX8888)
    local madeBlack, black = pcall(GetRenderTargetEx, BLACK_TARGET, 16, 16, RT_SIZE_LITERAL, MATERIAL_RT_DEPTH_NONE,
        bit.bor(4, 8, 256, 512), 0, IMAGE_FORMAT_RGBA8888)
    if not made or not target or not madeBlack or not black then
        scope.reason = "the scope targets could not be made"
        return false
    end
    local sized, width, height = pcall(function() return target:Width(), target:Height() end)
    if not sized or width ~= SCOPE_W or height ~= SCOPE_H then
        scope.reason = "the scope target is " .. tostring(width) .. " x " .. tostring(height) .. ", not " .. SCOPE_W ..
            " x " .. SCOPE_H
        return false
    end
    local hash = scopeHash()
    local ok, added = pcall(RemixConfig.SetConfigVariable, "rtx.raytracedRenderTargetTextures", hash)
    if not ok or added == false then
        scope.reason = "the runtime did not take the scope target"
        return false
    end
    pcall(function()
        render.PushRenderTarget(black)
        render.Clear(0, 0, 0, 255, true, true)
        render.PopRenderTarget()
    end)
    scope.target, scope.hash = target, hash
    scope.lens = CreateMaterial("nativeloader_arc9_scope_lens", "UnlitGeneric", {["$basetexture"] = target:GetName()})
    scope.black = CreateMaterial("nativeloader_arc9_scope_black", "UnlitGeneric", {["$basetexture"] = black:GetName()})
    scope.camera = CreateMaterial("nativeloader_arc9_scope_camera", "UnlitGeneric", {["$basetexture"] = black:GetName()})
    scope.reticle = CreateMaterial("nativeloader_arc9_scope_reticle", "UnlitGeneric", {["$basetexture"] = black:GetName(),
        ["$translucent"] = "1", ["$vertexalpha"] = "1", ["$vertexcolor"] = "1", ["$ignorez"] = "1"})
    scope.additive = CreateMaterial("nativeloader_arc9_scope_reticle_add", "UnlitGeneric",
        {["$basetexture"] = black:GetName(), ["$additive"] = "1", ["$vertexalpha"] = "1", ["$vertexcolor"] = "1",
         ["$ignorez"] = "1"})
    scope.position = Vector(0, 0, 0)
    scope.ready = true
    scope.reason = nil
    return true
end

-- The lens of an RT scope part (0-based sub-material index), from ARC9's tables, or false.
local function lensIndex(weapon, model)
    local slottbl = model.slottbl
    if not istable(slottbl) or type(weapon.GetFinalAttTable) ~= "function" then return false end
    local ok, atttbl = pcall(weapon.GetFinalAttTable, weapon, slottbl)
    if not ok or not istable(atttbl) or not atttbl.RTScope then return false end
    local index = tonumber(atttbl.RTScopeSubmatIndex)
    if not index or index < 0 or index > 31 or index % 1 ~= 0 then return false end
    return index
end

-- Source's body number for the model's bodygroups (what util.GetModelMeshes calls the bodygroup mask).
local function bodyMask(model)
    local mask, base = 0, 1
    local ok, count = pcall(model.GetNumBodyGroups, model)
    for id = 0, (ok and tonumber(count) or 0) - 1 do
        local values = tonumber(model:GetBodygroupCount(id)) or 1
        mask = mask + (tonumber(model:GetBodygroup(id)) or 0) * base
        base = base * math.max(values, 1)
    end
    return mask
end

-- The lens triangles of a model (its material at the index), as numbers, with their bones; cached by model, skin,
-- bodygroups and index. The buffers are reused every frame.
local lensCache, lensCacheSize = {}, 0
local function lensMesh(model, index)
    local path = model:GetModel()
    if not isstring(path) then return nil end
    local skin, mask = tonumber(model:GetSkin()) or 0, bodyMask(model)
    local key = path .. ":" .. skin .. ":" .. mask .. ":" .. index
    local cached = lensCache[key]
    if cached ~= nil then return cached or nil end
    if lensCacheSize >= 32 then lensCache, lensCacheSize = {}, 0 end
    local found = false
    local names = model:GetMaterials()
    local name = istable(names) and names[index + 1]
    if isstring(name) then
        name = string.lower(name):gsub("\\", "/"):gsub("%.vmt$", "")
        local meshes, bind = util.GetModelMeshes(path, 0, mask, skin)
        if istable(meshes) and istable(bind) then
            local data = { n = 0, px = {}, py = {}, pz = {}, weights = {}, bones = {}, bind = bind, mats = {},
                x = {}, y = {}, z = {}, screen = {} }
            for _, part in ipairs(meshes) do
                local own = isstring(part.material) and string.lower(part.material):gsub("\\", "/"):gsub("%.vmt$", "")
                if own == name and istable(part.triangles) then
                    for _, vertex in ipairs(part.triangles) do
                        local n = data.n + 1
                        if n > MAX_LENS_VERTICES then break end
                        data.n = n
                        data.px[n], data.py[n], data.pz[n] = vertex.pos.x, vertex.pos.y, vertex.pos.z
                        local list = {}
                        for _, weight in ipairs(vertex.weights or {}) do
                            list[#list + 1] = weight.bone
                            list[#list + 1] = weight.weight
                            data.bones[weight.bone] = true
                        end
                        data.weights[n] = list
                        data.screen[n] = { x = 0, y = 0, u = 0, v = 0 }
                    end
                end
            end
            if data.n >= 3 and data.n <= MAX_LENS_VERTICES and data.n % 3 == 0 then found = data end
        end
    end
    lensCache[key] = found
    lensCacheSize = lensCacheSize + 1
    return found or nil
end

-- The lens at the pose ARC9 gave the model this frame, into data.x/y/z; false when a bone has no pose.
local function posed(model, data)
    local mats = data.mats
    for bone in pairs(data.bones) do
        local pose, rest = model:GetBoneMatrix(bone), data.bind[bone]
        if not pose or not rest or not rest.matrix then return false end
        local e = mats[bone]
        if not e then e = {} mats[bone] = e end
        e[1], e[2], e[3], e[4], e[5], e[6], e[7], e[8], e[9], e[10], e[11], e[12] = (pose * rest.matrix):Unpack()
    end
    -- ARC9 scales a part with a RenderMultiply matrix (cl_model.lua: model.Scale); unless the bones carry it, the
    -- copy is scaled about the model's origin as the engine scales what it draws.
    local scale, sx, sy, sz = model.Scale, 1, 1, 1
    if isvector(scale) and (math.abs(scale.x - 1) > 0.001 or math.abs(scale.y - 1) > 0.001 or math.abs(scale.z - 1) > 0.001) then
        local bone = next(data.bones)
        local carried = bone ~= nil and model:GetBoneMatrix(bone):GetScale()
        if not carried or math.abs(carried.x - scale.x) > 0.01 then sx, sy, sz = scale.x, scale.y, scale.z end
    end
    local origin, angles = model:GetPos(), model:GetAngles()
    local f, l, u = angles:Forward(), -angles:Right(), angles:Up()
    local scaled = sx ~= 1 or sy ~= 1 or sz ~= 1
    for i = 1, data.n do
        local x, y, z, total = 0, 0, 0, 0
        local list = data.weights[i]
        local px, py, pz = data.px[i], data.py[i], data.pz[i]
        for k = 1, #list, 2 do
            local e, w = mats[list[k]], list[k + 1]
            x = x + (e[1] * px + e[2] * py + e[3] * pz + e[4]) * w
            y = y + (e[5] * px + e[6] * py + e[7] * pz + e[8]) * w
            z = z + (e[9] * px + e[10] * py + e[11] * pz + e[12]) * w
            total = total + w
        end
        if total <= 0 then return false end
        x, y, z = x / total, y / total, z / total
        if scaled then
            local dx, dy, dz = x - origin.x, y - origin.y, z - origin.z
            local a = (dx * f.x + dy * f.y + dz * f.z) * sx
            local b = (dx * l.x + dy * l.y + dz * l.z) * sy
            local c = (dx * u.x + dy * u.y + dz * u.z) * sz
            x = origin.x + f.x * a + l.x * b + u.x * c
            y = origin.y + f.y * a + l.y * b + u.y * c
            z = origin.z + f.z * a + l.z * b + u.z * c
        end
        data.x[i], data.y[i], data.z[i] = x, y, z
    end
    return true
end

-- How far ahead of the eye the runtime's view model reaches: the gun's and its parts' furthest corner along the view,
-- scaled as the runtime scales the view model; the scope's camera starts past it.
local function cameraAhead(weapon, eye, forward)
    local reach = 0
    local function consider(ent)
        if not IsValid(ent) or ent.hidden or ent.NoDraw or ent.IsAnimationProxy or ent.charmparent then return end
        local ok, mins, maxs = pcall(ent.GetRenderBounds, ent)
        if not ok or not mins or not maxs then return end
        local origin, angles = ent:GetPos(), ent:GetAngles()
        local offset = origin - eye
        if offset:Dot(offset) > PART_RANGE * PART_RANGE then return end
        local f, r, u = angles:Forward(), angles:Right(), angles:Up()
        local base = (origin - eye):Dot(forward)
        local df, dr, du = f:Dot(forward), r:Dot(forward), u:Dot(forward)
        -- The furthest of the eight corners along the view: each axis at whichever end reaches further.
        local cx = df >= 0 and maxs.x or mins.x
        local cy = dr <= 0 and maxs.y or mins.y -- local y is left (-right): its term is -cy * dr
        local cz = du >= 0 and maxs.z or mins.z
        reach = math.max(reach, base + cx * df - cy * dr + cz * du)
    end
    -- The view model's own render bounds cover its whole animation, far past the gun (the FA:S M249's reach 171 units
    -- ahead): its attachment points (the muzzle's among them) mark the gun's front instead.
    local vm = isfunction(weapon.GetVM) and weapon:GetVM() or nil
    if IsValid(vm) and isfunction(vm.GetAttachments) then
        local ok, list = pcall(vm.GetAttachments, vm)
        for _, item in ipairs(ok and istable(list) and list or {}) do
            local point = istable(item) and item.id and vm:GetAttachment(item.id)
            if istable(point) and point.Pos then
                local offset = point.Pos - eye
                if offset:Dot(offset) <= PART_RANGE * PART_RANGE then reach = math.max(reach, offset:Dot(forward)) end
            end
        end
    end
    for _, part in ipairs(istable(weapon.VModel) and weapon.VModel or {}) do consider(part) end
    return math.Clamp(reach * VIEWMODEL_SCALE + AHEAD_MARGIN, AHEAD_MIN, AHEAD_MAX)
end

local function clampEdge(value)
    if value < EDGE then return EDGE end
    if value > 1 - EDGE then return 1 - EDGE end
    return value
end

-- The camera of the scope's picture: one empty triangle drawn into the scope target. The runtime takes the camera of
-- whatever is drawn into a raytraced render target; the triangle has no area, so nothing of it is ever seen. It is
-- tested against depth (the target has its own depth buffer): a draw without a depth test into such a target counts
-- as sky. Whatever fails, the camera is ended and the target popped.
local function drawScopeCamera(weapon, origin, angles, fov)
    local ignored = (tonumber(weapon.CustomizeDelta) or 0) > 0 or ARC9.PresetCam -- ARC9's cam.IgnoreZ(true)
    render.PushRenderTarget(scope.target)
    local ok, err = pcall(function()
        cam.Start3D(origin, angles, fov, 0, 0, SCOPE_H, SCOPE_H, 4, 30000)
        local drawn, problem = pcall(function()
            if ignored then cam.IgnoreZ(false) end
            render.SetMaterial(scope.camera)
            local point = scope.position
            point:Set(origin + angles:Forward() * 64)
            mesh.Begin(MATERIAL_TRIANGLES, 1)
            for _ = 1, 3 do
                mesh.Position(point)
                mesh.TexCoord(0, 0, 0)
                mesh.Color(255, 255, 255, 255)
                mesh.AdvanceVertex()
            end
            mesh.End()
        end)
        if ignored then cam.IgnoreZ(true) end
        cam.End3D()
        if not drawn then error(problem, 0) end
    end)
    render.PopRenderTarget()
    if not ok then error(err, 0) end
end

-- The lens copy, drawn in the view model pass with ARC9's view model camera still in place. Keeps the lens's screen
-- triangles for the reticle.
local function drawLens(weapon, model, index, view)
    local data = lensMesh(model, index)
    if not data or not posed(model, data) then return false end
    local eye, angles = EyePos(), EyeAngles()
    local vmfov = weapon.ViewModelFOV or (isfunction(weapon.GetViewModelFOV) and weapon:GetViewModelFOV()) or 90
    local fov = isfunction(weapon.WidescreenFix) and weapon:WidescreenFix(vmfov) or vmfov
    local w, h = ScrW(), ScrH()
    local forward, right, up = angles:Forward(), angles:Right(), angles:Up()
    local scale = 1 / math.tan(math.rad(fov) * 0.5)
    local aspect, left = w / h, (w - h) * 0.5
    local ex, ey, ez = eye.x, eye.y, eye.z
    for i = 1, data.n do
        local dx, dy, dz = data.x[i] - ex, data.y[i] - ey, data.z[i] - ez
        local depth = dx * forward.x + dy * forward.y + dz * forward.z
        if depth <= 0.05 then return false end
        local sx = (1 + (dx * right.x + dy * right.y + dz * right.z) * scale / depth) * w * 0.5
        local sy = (1 - (dx * up.x + dy * up.y + dz * up.z) * scale * aspect / depth) * h * 0.5
        local point = data.screen[i]
        point.x, point.y, point.u, point.v = sx, sy, clampEdge((sx - left) / h), clampEdge(sy / h)
    end
    local ahead = cameraAhead(weapon, eye, forward)
    local origin = MainEyePos() + view.angles:Forward() * ahead
    drawScopeCamera(weapon, origin, view.angles, view.fov)
    render.SetMaterial(scope.lens)
    local position = scope.position
    mesh.Begin(MATERIAL_TRIANGLES, data.n / 3)
    for i = 1, data.n do
        local x, y, z = data.x[i], data.y[i], data.z[i]
        local dx, dy, dz = ex - x, ey - y, ez - z
        local length = math.sqrt(dx * dx + dy * dy + dz * dz)
        if length > LENS_LIFT * 2 then
            local k = LENS_LIFT / length
            x, y, z = x + dx * k, y + dy * k, z + dz * k
        end
        position:SetUnpacked(x, y, z)
        mesh.Position(position)
        local point = data.screen[i]
        mesh.TexCoord(0, point.u, point.v)
        mesh.Color(255, 255, 255, 255)
        mesh.AdvanceVertex()
    end
    mesh.End()
    weapon.NLARC9Lens = { frame = view.frame, data = data, ahead = ahead }
    scope.stats.lenses = (scope.stats.lenses or 0) + 1
    return true
end

-- The view ARC9 renders its scope picture with (cl_pipscope_new.lua: RenderRTExpensive, or RenderRTCheap for its
-- "cheap" sights: collimators, 1x sights, arc9_cheapscopes), kept for this frame's lens.
function ARC9Patch.RenderRT(original, self, cheap, magnification, ...)
    if not scopesOn() then return original(self, cheap, magnification, ...) end
    if not scopeReady() then return original(self, cheap, magnification, ...) end
    local atttbl = self:IsScoping()
    if not atttbl or ARC9.OverDraw then return end
    local setup = render.GetViewSetup()
    local mainFov = istable(setup) and tonumber(setup.fov) or 90
    local fov
    if cheap then
        -- ARC9 shows its (whole-view zoomed) screen 1:1 on a cheap sight's lens: the view's own height.
        fov = self:ScaleFOVByWidthRatio(mainFov, ScrH() / ScrW())
    else
        magnification = tonumber(magnification) or self:GetRTScopeMagnification() or 1
        if magnification <= 0 then magnification = 1 end
        fov = self:ScaleFOVByWidthRatio(mainFov, 0.75) / magnification
    end
    if not (fov > 0.05 and fov < 170) then return end
    ARC9.RTScopeRenderFOV = fov
    self.NLARC9ScopeView = { frame = FrameNumber(), fov = fov, angles = MainEyeAngles() }
end

-- The reticle over the lens, as 2D after the path-traced image: each lens vertex's place on ARC9's reticle square (the
-- ray from the eye through it with ARC9's 90-degree camera, met with the square's plane), the lens triangles cut to
-- the square. Faded in as the sight comes up, as ARC9 darkens its picture until then.
local function clipPolygon(points, key, keep)
    local out = {}
    local count = #points
    for i = 1, count do
        local a, b = points[i], points[i % count + 1]
        local va, vb = a[key], b[key]
        local ina, inb = keep(va), keep(vb)
        if ina then out[#out + 1] = a end
        if ina ~= inb then
            local bound = (va < 0 or vb < 0) and 0 or 1
            local t = (bound - va) / (vb - va)
            out[#out + 1] = { x = a.x + (b.x - a.x) * t, y = a.y + (b.y - a.y) * t, u = a.u + (b.u - a.u) * t,
                v = a.v + (b.v - a.v) * t }
        end
    end
    return out
end
local function atLeast0(value) return value >= 0 end
local function atMost1(value) return value <= 1 end

local function drawReticle(self, placement, amount)
    local lens = self.NLARC9Lens
    if not lens or lens.frame ~= FrameNumber() then return end
    local reticle = placement.material
    local texture = reticle:GetTexture("$basetexture")
    if not texture or texture:IsError() then return end
    local additive = bit.band(tonumber(reticle:GetInt("$flags")) or 0, MATERIAL_VAR_ADDITIVE) ~= 0
    local mat = additive and scope.additive or scope.reticle
    mat:SetTexture("$basetexture", texture)
    local w, h = ScrW(), ScrH()
    local eye, angles = MainEyePos(), EyeAngles()
    local f, r, u = angles:Forward(), angles:Right(), angles:Up()
    local center, qr, qu, qn, half = placement.center, placement.right, placement.up, placement.normal, placement.half
    local toCenter = (center - eye):Dot(qn)
    local data = lens.data
    local corners = {}
    for i = 1, data.n do
        local point = data.screen[i]
        local nx, ny = 2 * point.x / w - 1, 1 - 2 * point.y / h
        local dir = f + r * nx + u * (ny * h / w) -- 90 degrees across the screen's width
        local denom = dir:Dot(qn)
        if math.abs(denom) < 1e-6 then return end
        local hit = eye + dir * (toCenter / denom) - center
        corners[i] = { x = point.x, y = point.y, u = (hit:Dot(qr) + half) / (2 * half), v = (half - hit:Dot(qu)) / (2 * half) }
    end
    local color = placement.color
    surface.SetMaterial(mat)
    surface.SetDrawColor(color.r or 255, color.g or 255, color.b or 255, (color.a or 255) * math.Clamp(amount, 0, 1))
    for i = 1, data.n - 2, 3 do
        local poly = { corners[i], corners[i + 1], corners[i + 2] }
        poly = clipPolygon(poly, "u", atLeast0)
        if #poly >= 3 then poly = clipPolygon(poly, "u", atMost1) end
        if #poly >= 3 then poly = clipPolygon(poly, "v", atLeast0) end
        if #poly >= 3 then poly = clipPolygon(poly, "v", atMost1) end
        if #poly >= 3 then surface.DrawPoly(poly) end
    end
    scope.stats.reticles = (scope.stats.reticles or 0) + 1
end

-- ARC9's per-frame scope bookkeeping (cl_pipscope_new.lua, DrawRTReticle, from its RenderScreenspaceEffects hook):
-- whether the scope is looked through, and its reticle where ARC9 would draw it. Nothing goes into ARC9's targets.
local function alwaysDraw()
    -- ARC9 makes its settings when it loads, which may be after this file.
    local convar = GetConVar and GetConVar("arc9_fx_rt_alwaysdraw")
    return convar ~= nil and convar:GetBool()
end
function ARC9Patch.DrawRTReticle(original, self, model, atttbl, nonatt, cheap, ...)
    if not scopesOn() or not scopeReady() then
        -- ARC9's own picture: it pushes its full-frame scope target and draws 2D into it. The RTX runtime puts the
        -- frame's path-traced image into the target bound at the frame's first 2D draw, and with ARC9's screen copy
        -- before the gun skipped (section 5) nothing has ended path tracing yet: the screen would stay black. A read of
        -- the screen ends it there first.
        if cvEnabled:GetBool() and IsValid(model) and render.UpdateScreenEffectTexture
            and (alwaysDraw() or (tonumber(self:GetSightDelta()) or 0) > 0.01) then
            render.UpdateScreenEffectTexture()
        end
        return original(self, model, atttbl, nonatt, cheap, ...)
    end
    if not IsValid(model) then return end
    atttbl = atttbl or {}
    if atttbl.RTScopeNew_DisableShaderEyeOffset then nonatt = true end
    local always = not atttbl.RTScopeNew_OnlyInSights and alwaysDraw()
    local amount = tonumber(self:GetSightDelta()) or 0
    local active = always or amount > 0.01
    local modelang = model:GetAngles()
    local forward = modelang:Forward()
    local sight = self:GetSight() or {}
    local sightpos = sight.OriginalSightTable and sight.OriginalSightTable.Pos or Vector(0, 0, 0)
    local base = model:GetPos() - modelang:Up() * sightpos.z - modelang:Right() * sightpos.x
    local eye = MainEyePos()
    local diff = eye - base
    local distance = diff:Length()
    if not nonatt and distance > 0 and math.abs(forward:Dot(diff) / distance) < 0.7 then
        active = false -- not looking along the scope
    end
    model.RTScopeDrawingRN = active
    if not active or (isfunction(self.ShouldDoScope) and not self:ShouldDoScope()) then return end
    local reticle = sight.Reticle or atttbl.RTScopeReticle
    if not reticle or (isfunction(reticle.IsError) and reticle:IsError()) then return end
    -- ARC9 draws the reticle as a square of 2 * scale units, 1.5 units ahead (along the scope, after its fix angle) of
    -- a point that moves from the scope's front to the eye's line as the sight comes up.
    local fix = atttbl.RTScopeNew_FixAngle
    if istable(fix) then
        modelang = Angle(modelang.p, modelang.y, modelang.r)
        modelang:RotateAroundAxis(forward, -(fix[3] or 0))
        modelang:RotateAroundAxis(modelang:Right(), -(fix[1] or 0))
        modelang:RotateAroundAxis(modelang:Up(), -(fix[2] or 0))
    end
    local mins = model:GetModelBounds()
    local front = mins and mins.x or 0
    local position = base + forward * front * (atttbl.Scale or 1) * (sight.Scale or 1)
    if nonatt then position, forward = eye, MainEyeAngles():Forward() end
    local eased = math.ease and math.ease.InBack and math.ease.InBack(amount) or amount
    local along = math.abs((position - eye):Dot(forward))
    local lerped = LerpVector(eased, position, eye + forward * along)
    local w, h = ScrW(), ScrH()
    local half = 4 * (atttbl.RTScopeReticleScale or 1) * (atttbl.ScopeScreenRatio or 0.5) - (w / h - 16 / 9)
    if not (half > 0.01) then return end
    local color = atttbl.RTScopeColor or color_white
    if atttbl.RTScopeColorable then
        local cr, cg, cb = GetConVar("arc9_scope_r"), GetConVar("arc9_scope_g"), GetConVar("arc9_scope_b")
        color = Color(cr and cr:GetInt() or 255, cg and cg:GetInt() or 255, cb and cb:GetInt() or 255)
    end
    local placement = { center = lerped + modelang:Forward() * 1.5, right = modelang:Right(), up = modelang:Up(),
        normal = modelang:Forward(), half = half, material = reticle, color = color }
    cam.Start2D()
    local ok, err = pcall(drawReticle, self, placement, math.max(amount, always and 1 or 0))
    cam.End2D()
    if not ok then scope.stats.error = tostring(err) end
end

-- A scope built into the weapon's own view model (ARC9's SWEP.RTScope): its lens is on the view model, which the
-- engine draws between PreDrawViewModel and ViewModelDrawn. Its lens is black for that draw, and the copy follows.
local function ownLens(self)
    if not self.RTScope then return false end
    local index = tonumber(self.RTScopeSubmatIndex)
    if not index or index < 0 or index > 31 or index % 1 ~= 0 then return false end
    return index
end

local function clearOwnLens(self)
    local index = self.NLARC9OwnLens
    if index then
        render.MaterialOverrideByIndex(index, nil)
        self.NLARC9OwnLens = nil
    end
    return index
end

-- 5. ARC9's screen-space work before the view model. The RTX runtime path traces a frame up to its first 2D draw and
-- up to the first read of the back buffer (it finishes the image for the read), and rasterizes what comes after: the
-- gun. ARC9 draws its customization background and its blur options in 2D there, and copies the screen for its sight
-- blur every frame (arc9_fx_adsblur_bleeding, on by default; the blur itself is skipped below). Its translucent pass
-- copies the screen before its translucent parts. The engine draws the view model twice a frame (its opaque and its
-- translucent pass, each with ARC9's hooks), and ARC9 draws its holosights (which read the screen first) and the view
-- model's lens flares (2D) inside each pass: in the first, either would end path tracing before the second. Those of
-- the last pass are drawn after the view models instead, where the holosights' stencilled reticle is rasterized as
-- before.
local function skipped() end
local SCREEN_DRAWS = { { "surface", "DrawRect" }, { "surface", "DrawTexturedRect" }, { "render", "DrawScreenQuad" },
    { "render", "DrawScreenQuadEx" } }
local SCREEN_READS = { { "render", "UpdateScreenEffectTexture" }, { "render", "UpdateFullScreenDepthTexture" },
    { "render", "UpdateRefractTexture" }, { "render", "UpdatePowerOfTwoTexture" },
    { "render", "CopyRenderTargetToTexture" }, { "render", "CopyTexture" } }
local BEFORE_VIEW_MODEL = {}
for _, item in ipairs(SCREEN_DRAWS) do BEFORE_VIEW_MODEL[#BEFORE_VIEW_MODEL + 1] = item end
for _, item in ipairs(SCREEN_READS) do BEFORE_VIEW_MODEL[#BEFORE_VIEW_MODEL + 1] = item end

-- The frame whose ARC9 screen copy before the gun was skipped (path tracing then ends after the view models).
local skippedFrame = -1

-- The holosights and view-model flares of the view model's last pass this frame, drawn after the view models.
local deferred = { holosights = {}, flares = {} }
local function clearDeferred()
    for i = #deferred.holosights, 1, -1 do deferred.holosights[i] = nil end
    for i = #deferred.flares, 1, -1 do deferred.flares[i] = nil end
end

-- Runs fn with the listed library functions doing nothing; they are put back afterwards, also after an error.
local function without(list, fn, ...)
    local saved = {}
    for i, item in ipairs(list) do
        local library = _G[item[1]]
        if istable(library) then
            saved[i] = library[item[2]]
            library[item[2]] = skipped
        end
    end
    local results = { pcall(fn, ...) }
    for i, item in ipairs(list) do
        local library = _G[item[1]]
        if istable(library) then library[item[2]] = saved[i] end
    end
    if not results[1] then error(results[2], 0) end
    return unpack(results, 2)
end

function ARC9Patch.PreDrawViewModel(original, self, ...)
    clearOwnLens(self)
    if not cvEnabled:GetBool() then return original(self, ...) end
    skippedFrame = FrameNumber()
    clearDeferred() -- a new pass: only the last pass's holosights and flares are drawn
    local results = { without(BEFORE_VIEW_MODEL, original, self, ...) }
    -- True hides the view model: then nothing is drawn and nothing is overridden.
    if results[1] ~= true and not ARC9.RTScopeRender and not ARC9.PresetCam and scopesOn() then
        local index = ownLens(self)
        if index and scopeReady() then
            render.MaterialOverrideByIndex(index, scope.black)
            self.NLARC9OwnLens = index
        end
    end
    return unpack(results)
end

function ARC9Patch.ViewModelDrawn(original, self, ...)
    local index = clearOwnLens(self)
    local results = { pcall(original, self, ...) }
    local model = self.RTScopeModel
    local view = self.NLARC9ScopeView
    if index and IsValid(model) and isfunction(self.GetVM) and model == self:GetVM() and model.RTScopeDrawingRN
        and view and view.frame == FrameNumber() then
        local ok, err = pcall(drawLens, self, model, index, view)
        if not ok then scope.stats.error = tostring(err) end
    end
    if not results[1] then error(results[2], 0) end
    return unpack(results, 2)
end

-- ARC9 draws its holosights at the end of its PostDrawViewModel: they are kept for after the view models.
function ARC9Patch.PostDrawViewModel(original, self, ...)
    clearOwnLens(self) -- in case ViewModelDrawn was not called
    if skippedFrame ~= FrameNumber() or not cvEnabled:GetBool() then return original(self, ...) end
    local draw = self.DoHolosight
    if not isfunction(draw) then return original(self, ...) end
    local tbl = isfunction(self.GetTable) and self:GetTable() or self
    local own = rawget(tbl, "DoHolosight")
    tbl.DoHolosight = function(weapon, model, atttbl)
        deferred.holosights[#deferred.holosights + 1] = { draw = draw, weapon = weapon, model = model, atttbl = atttbl }
    end
    local results = { pcall(original, self, ...) }
    tbl.DoHolosight = own
    if not results[1] then error(results[2], 0) end
    return unpack(results, 2)
end

-- A lens flare of the view model (ARC9's DrawLightFlare with vm set: its lights and lasers, from ViewModelDrawn) is a
-- 2D draw inside the pass: kept for after the view models, its arguments copied. Other flares are drawn at once.
local function copied(value)
    if isvector and isvector(value) then return Vector(value.x, value.y, value.z) end
    if isangle and isangle(value) then return Angle(value.p, value.y, value.r) end
    return value
end
function ARC9Patch.DrawLightFlare(original, self, ...)
    local vm = select(5, ...)
    if vm and skippedFrame == FrameNumber() and cvEnabled:GetBool() then
        local args = { n = select("#", ...), ... }
        for i = 1, args.n do args[i] = copied(args[i]) end
        deferred.flares[#deferred.flares + 1] = { draw = original, weapon = self, args = args }
        return
    end
    return original(self, ...)
end

-- The kept holosights and flares, with the view model's camera as ARC9 draws its holosights.
local function drawDeferred()
    local first = deferred.holosights[1] or deferred.flares[1]
    if first and IsValid(first.weapon) then
        local weapon = first.weapon
        local vmfov = (isfunction(weapon.GetViewModelFOV) and weapon:GetViewModelFOV()) or weapon.ViewModelFOV or 90
        local fov = isfunction(weapon.WidescreenFix) and weapon:WidescreenFix(vmfov) or vmfov
        cam.Start3D(nil, nil, fov, nil, nil, nil, nil, 1, 10000)
        for _, item in ipairs(deferred.holosights) do
            local ok, err = pcall(item.draw, item.weapon, item.model, item.atttbl)
            if not ok then scope.stats.error = tostring(err) end
        end
        for _, item in ipairs(deferred.flares) do
            local ok, err = pcall(item.draw, item.weapon, unpack(item.args, 1, item.args.n))
            if not ok then scope.stats.error = tostring(err) end
        end
        cam.End3D()
    end
    clearDeferred()
end

-- Path tracing ends after the view models, in a frame whose ARC9 screen copy before the gun was skipped: a read of the
-- screen in GMod's PreDrawEffects, which runs once all view models are drawn (the engine draws ARC9's view model twice
-- a frame, in its opaque and its translucent pass, each with ARC9's hooks: a read after the first would rasterize the
-- second). ARC9 draws its HUD next, partly in perspective (its hints and its ammo card): with nothing ending path
-- tracing before the HUD, the runtime would trace those as lit objects in front of the gun. Everything ARC9 draws after
-- its view models is rasterized over the image, as before; so is ARC9's own scope picture, which binds a target of the
-- screen's size for its 2D.
function ARC9Patch.EndPathTracing()
    if skippedFrame ~= FrameNumber() or ARC9.RTScopeRender or ARC9.PresetCam then return end
    skippedFrame = -1 -- once a frame
    if render.UpdateScreenEffectTexture then render.UpdateScreenEffectTexture() end
    drawDeferred()
end
if hook and hook.Add then hook.Add("PreDrawEffects", "rtx_patcher_arc9_after_view_models", ARC9Patch.EndPathTracing) end

-- The view model's translucent parts: drawn without the screen copy before them (world models: ARC9's own).
function ARC9Patch.DrawTranslucentPass(original, self, wm, ...)
    if wm or not cvEnabled:GetBool() then return original(self, wm, ...) end
    return without(SCREEN_READS, original, self, wm, ...)
end

-- The sight blur and its mask: nothing to do in RTX sessions.
function ARC9Patch.NoBlur(original, self, ...)
    if cvEnabled:GetBool() then return end
    return original(self, ...)
end

-- The models ARC9 itself draws one by one in this DrawCustomModel call (weapons/arc9_base/cl_drawmodel.lua), or nil
-- when it draws none of them: no view model without an owner or for an NPC or a distant player, nothing for a world
-- model while an RT scope renders, and only the base model for a world model at LOD 2 (its parts keep a stale pose).
-- A preset icon (custompos) draws the preset's own models.
local function drawnModels(self, wm, custompos)
    local owner = self:GetOwner()
    local validOwner = IsValid(owner)
    if not wm and not validOwner then return nil end
    local lodOk, lod = pcall(self.ShouldLOD, self)
    lod = lodOk and tonumber(lod) or 0
    local npc = (validOwner and owner:IsNPC()) or lod > 0
    if not wm and npc then return nil end
    if wm and ARC9.RTScopeRender then return nil end
    local world = wm or custompos -- ARC9: "if custompos then wm = true end", after the checks above
    if world and lod >= 2 then return nil end
    local models = world and (custompos and self.CModel or self.WModel) or self.VModel
    return istable(models) and models or nil
end

-- Wraps DrawCustomModel: dressed parts are skipped by ARC9 (NoDraw for the call) and drawn here afterwards, at the
-- pose ARC9 gave them, with their materials. ARC9's DrawFunc (the gun screen's render target) still runs. Parts
-- ARC9 does not draw in its loop are left to it: animation proxies, charm models (their parent draws them) and
-- translucent parts (its translucent pass draws them). In RTX sessions an RT scope part of the view model is one of
-- them: its lens black, and the path-traced lens copy in front of it while it is looked through (R25).
local sentToPass = {}
function ARC9Patch.DrawCustomModel(original, self, wm, custompos, ...)
    local parts, scopes = cvParts:GetBool(), not wm and not custompos and scopesOn()
    if not parts and not scopes then return original(self, wm, custompos, ...) end
    local models = drawnModels(self, wm, custompos)
    local dressed
    if models then
        for _, model in ipairs(models) do
            if IsValid(model) and not model.NoDraw and not model.IsAnimationProxy and not model.charmparent
                and not model.istranslucent then
                -- ARC9 makes new part models whenever the weapon is customized: the answers are kept on the model.
                local subs = false
                if parts then
                    subs = model.NLARC9Subs
                    if subs == nil then
                        subs = ARC9Patch.PartMaterials(self, model) or false
                        model.NLARC9Subs = subs
                    end
                end
                local lens = false
                if scopes then
                    lens = model.NLARC9LensIndex
                    if lens == nil then
                        lens = lensIndex(self, model)
                        model.NLARC9LensIndex = lens
                    end
                    if lens and not scopeReady() then lens = false end
                end
                if subs or lens then
                    dressed = dressed or {}
                    dressed[#dressed + 1] = { model = model, subs = subs or {}, lens = lens }
                    model.NoDraw = true
                end
            end
        end
    end
    if not dressed then return original(self, wm, custompos, ...) end
    local results = { pcall(original, self, wm, custompos, ...) }
    for _, item in ipairs(dressed) do item.model.NoDraw = false end
    for _, item in ipairs(dressed) do
        local model = item.model
        if IsValid(model) and not model.hidden then
            local overrides = item.subs
            if item.lens then
                local merged = {}
                for index, mat in pairs(overrides) do merged[index] = mat end
                merged[item.lens] = scope.black
                overrides = merged
            end
            for index, mat in pairs(overrides) do render.MaterialOverrideByIndex(index, mat) end
            model:DrawModel()
            for index in pairs(overrides) do render.MaterialOverrideByIndex(index, nil) end
            local view = self.NLARC9ScopeView
            if item.lens and model == self.RTScopeModel and model.RTScopeDrawingRN and view
                and view.frame == FrameNumber() then
                local ok, err = pcall(drawLens, self, model, item.lens, view)
                if not ok then scope.stats.error = tostring(err) end
            end
        end
        local sticker = model.NLARC9Sticker
        if sticker and not sentToPass[sticker] and RTXViewModelMaterials and RTXViewModelMaterials.ProcessMaterial then
            sentToPass[sticker] = true
            pcall(RTXViewModelMaterials.ProcessMaterial, sticker)
        end
    end
    if not results[1] then error(results[2], 0) end
    return unpack(results, 2)
end

-- The screen's mesh and its live texture, one function each (the companion caches a model's screen meshes per
-- function: new closures every frame would read the model's meshes again every frame).
local function isGunScreen(name)
    return (string.lower(name):gsub("%.vmt$", "")) == "models/sherrifdoggo/gunscreen/gs_screen"
end
local function gunScreenTexture()
    local screen = material(GUNSCREEN)
    return screen and screen:GetTexture("$basetexture") or nil
end
local function screenProvider(player, weapon)
    if not cvEnabled:GetBool() or not cvParts:GetBool() then return nil end
    if not IsValid(weapon) or not weapon.ARC9 or not istable(weapon.VModel) then return nil end
    local out
    for _, model in ipairs(weapon.VModel) do
        if IsValid(model) and model.NLARC9GunScreen and not model.hidden then
            out = out or {}
            out[#out + 1] = { model = model, screen = isGunScreen, texture = gunScreenTexture }
        end
    end
    return out
end

-- The companion's screen redraw keeps a table that is already there, so the provider is in place whichever of the
-- two loads first.
local function offerScreens()
    NativeLoaderScreens = istable(NativeLoaderScreens) and NativeLoaderScreens or {}
    NativeLoaderScreens.providers = istable(NativeLoaderScreens.providers) and NativeLoaderScreens.providers or {}
    if isfunction(NativeLoaderScreens.Register) then
        NativeLoaderScreens.Register("arc9_gunscreen", screenProvider)
        return "redrawn in 2D"
    end
    NativeLoaderScreens.providers.arc9_gunscreen = screenProvider
    return "offered to the companion's screen redraw"
end

local intercepted = {
    { name = "DrawCustomModel", around = ARC9Patch.DrawCustomModel },
    { name = "RenderRT", around = ARC9Patch.RenderRT },
    { name = "DrawRTReticle", around = ARC9Patch.DrawRTReticle },
    { name = "PreDrawViewModel", around = ARC9Patch.PreDrawViewModel },
    { name = "ViewModelDrawn", around = ARC9Patch.ViewModelDrawn },
    { name = "PostDrawViewModel", around = ARC9Patch.PostDrawViewModel },
    { name = "DrawTranslucentPass", around = ARC9Patch.DrawTranslucentPass },
    { name = "DrawLightFlare", around = ARC9Patch.DrawLightFlare },
    { name = "RenderDoFMask", around = ARC9Patch.NoBlur },
    { name = "RenderDoF", around = ARC9Patch.NoBlur },
}

-- A weapon table's functions; the first failure is the answer (DrawCustomModel's, which R24 reported, comes first).
local function patchWeaponTable(tbl, id)
    if type(tbl) ~= "table" then return false, "no weapon table" end
    local firstOk, firstErr
    for i, item in ipairs(intercepted) do
        local ok, err
        if type(tbl[item.name]) ~= "function" then
            ok, err = false, "no " .. item.name
        else
            ok, err = Patcher.InterceptFunction(tbl, item.name, {
                patchId = "arc9",
                id = id .. (i == 1 and "" or "_" .. string.lower(item.name)),
                around = item.around
            })
        end
        if i == 1 then firstOk, firstErr = ok, err end
    end
    return firstOk, firstErr
end

if concommand and concommand.Add then concommand.Add("rtx_patcher_arc9_scope_status", function()
    local state = {
        enabled = cvEnabled:GetBool() and cvScopes:GetBool(),
        ready = scope.ready,
        reason = scope.reason,
        hash = scope.hash or scopeHash(),
        lenses = scope.stats.lenses or 0,
        reticles = scope.stats.reticles or 0,
        error = scope.stats.error,
    }
    print("[RTXPatcher] ARC9 scopes " .. util.TableToJSON(state))
end) end

Patcher.RegisterPatch({
    id = "arc9",
    label = "ARC9 Weapon Base",
    side = "client",
    enabled = function() return cvEnabled:GetBool() end,
    depends = ARC9Patch.IsReady,
    apply = function(_, _, context)
        local dxOk, dxErr = ARC9Patch.PatchDirectXWarning()
        if not dxOk then Patcher.Debug("arc9", "DirectX warning not patched: " .. tostring(dxErr)) end
        -- New weapons copy the base's functions when they are made; weapons already made keep their own copies.
        local partsOk, partsErr = patchWeaponTable(context.base, "parts_base")
        for _, ent in ipairs(ents.GetAll()) do
            if IsValid(ent) and ent.ARC9 and ent:IsWeapon() then
                patchWeaponTable(ent:GetTable(), "parts_" .. ent:EntIndex())
            end
        end
        local screens = offerScreens()
        Patcher.State.arc9 = {
            dxWarning = dxOk and "hidden" or tostring(dxErr),
            parts = partsOk and "drawn with their materials" or tostring(partsErr),
            screens = screens,
            scopes = "path traced when looked through (rtx_patcher_arc9_scopes)",
        }
    end,
    retryInterval = 1,
    maxAttempts = 120
})

return ARC9Patch
