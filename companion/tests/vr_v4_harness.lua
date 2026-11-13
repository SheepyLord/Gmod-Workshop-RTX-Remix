-- Each case's method/structure contract is linked in vr_v4_harness.lua.md.
local root, scenario = ...
local S = assert(loadfile(root .. "/companion/tests/vr_stubs.lua"))() S.Math()
local function eq(a, b) assert(a == b, tostring(a) .. " ~= " .. tostring(b)) end
local function near(a, b) assert(math.abs(a - b) < 0.00001, a .. " ~= " .. b) end
local function vec(a, b) near((a - b):Length(), 0) end
local cases = {}
function cases.weapon() eq(S.Weapon{class = "weapon_pistol"}:GetClass(), "weapon_pistol") end
function cases.clips()
    local w = S.Weapon{clip1 = 12, clip2 = -1, maxClip1 = 18}
    eq(w:Clip1(), 12) eq(w:Clip2(), -1) eq(w:GetMaxClip1(), 18)
    w:SetClip1(21) eq(w:Clip1(), 21) w:SetClip1(0) eq(w:Clip1(), 0) w:SetClip2(2) eq(w:Clip2(), 2)
end
function cases.ammo_types()
    local w = S.Weapon{primary = 3, secondary = 4} eq(w:GetPrimaryAmmoType(), 3) eq(w:GetSecondaryAmmoType(), 4)
    eq(S.Weapon():GetPrimaryAmmoType(), -1)
end
function cases.next_fire() local w = S.Weapon() w:SetNextPrimaryFire(123.25) eq(w:GetNextPrimaryFire(), 123.25) end
function cases.world_model() eq(S.Weapon{model = "models/weapons/w_pistol.mdl"}:GetWeaponWorldModel(), "models/weapons/w_pistol.mdl") end
function cases.hold_type() eq(S.Weapon{holdType = "ar2"}:GetHoldType(), "ar2") end
function cases.scripted() eq(S.Weapon{scripted = true}:IsScripted(), true) eq(S.Weapon():IsScripted(), false) end
local function player()
    return S.Player{weapons = {S.Weapon{class = "weapon_pistol"}, S.Weapon{class = "weapon_smg1"}},
        ammoTypes = {pistol = 1, smg1 = 3}, ammo = {[1] = 20}, ammoMax = {[1] = 150}}
end
function cases.inventory()
    local p = player() local list = p:GetWeapons() eq(#list, 2) eq(list[1]:GetOwner(), p)
    list[1] = nil eq(#p:GetWeapons(), 2) eq(p:GetWeapon("missing").valid, false)
end
function cases.active() local p = player() eq(p:GetActiveWeapon().valid, false) p:SelectWeapon("weapon_pistol") eq(p:GetActiveWeapon():GetClass(), "weapon_pistol") end
function cases.ammo_count() local p = player() eq(p:GetAmmoCount(1), 20) eq(p:GetAmmoCount("Pistol"), 20) eq(p:GetAmmoCount(-1), 0) end
function cases.give_ammo() local p = player() eq(p:GiveAmmo(140, "Pistol", true), 130) eq(p:GetAmmoCount(1), 150) eq(p:GiveAmmo(1, -1), 0) end
function cases.remove_ammo() local p = player() p:RemoveAmmo(8, 1) eq(p:GetAmmoCount("Pistol"), 12) p:RemoveAmmo(50, "Pistol") eq(p:GetAmmoCount(1), 0) end
function cases.set_ammo() local p = player() p:SetAmmo(47, "Pistol") eq(p:GetAmmoCount(1), 47) p:SetAmmo(3, 1) eq(p:GetAmmoCount("Pistol"), 3) end
function cases.give()
    S.WeaponRegistry() weapons.Register({Primary = {ClipSize = -1, DefaultClip = 10, Ammo = "Pistol"}}, "nlvr_hands")
    local p = player() local w = p:Give("nlvr_hands", true)
    eq(w:GetClass(), "nlvr_hands") eq(w:GetOwner(), p) eq(p:GetAmmoCount(1), 20)
    eq(p:Give("nlvr_hands").valid, false) eq(p:Give("missing").valid, false)
    p:StripWeapon("nlvr_hands") p:Give("nlvr_hands") eq(p:GetAmmoCount(1), 30)
end
function cases.strip() local p = player() p:SelectWeapon("weapon_pistol") local w = p:GetActiveWeapon() p:StripWeapon("weapon_pistol") eq(w.valid, false) eq(#p:GetWeapons(), 1) eq(p:GetActiveWeapon().valid, false) end
function cases.select() local p = player() p:SelectWeapon("weapon_smg1") eq(p:GetActiveWeapon(), p:GetWeapons()[2]) p:SelectWeapon("missing") eq(p:GetActiveWeapon():GetClass(), "weapon_smg1") end
function cases.buttons()
    local c = S.Command() c:SetButtons(1) c:AddKey(8192) assert(c:KeyDown(1) and c:KeyDown(8192))
    c:RemoveKey(1) eq(c:GetButtons(), 8192) c:ClearButtons() eq(c:GetButtons(), 0)
end
function cases.wheel() local c = S.Command() eq(c:GetMouseWheel(), 0) c:SetMouseWheel(-2) eq(c:GetMouseWheel(), -2) end
function cases.command_select() local p, c = player(), S.Command() c:SelectWeapon(p:GetWeapons()[2]) eq(c.selected, p:GetWeapons()[2]) eq(p:GetActiveWeapon().valid, false) end
function cases.bullets()
    local callback = function() end local data = S.Bullet{Src = Vector(3, 4, 5), Dir = Vector(0, 1, 0), Num = 3, Callback = callback}
    local hookData = data hookData.Src = Vector(7, 8, 9) hookData.Dir = Vector(1, 0, 0)
    vec(data.Src, Vector(7, 8, 9)) vec(data.Dir, Vector(1, 0, 0)) eq(data.Num, 3) eq(data.Callback, callback)
    local defaults = S.Bullet() -- independent tables/vectors for separate bullets
    vec(defaults.Src, Vector()) vec(defaults.Dir, Vector()) vec(defaults.Spread, Vector())
    eq(defaults.HullSize, 0) eq(defaults.AmmoType, "") eq(defaults.Inflictor.valid, false) eq(defaults.IgnoreEntity.valid, false)
end
function cases.register()
    local stored = S.WeaponRegistry() local def = {Spawnable = false, Primary = {ClipSize = -1}}
    weapons.Register(def, "nlvr_hands") eq(stored.nlvr_hands.ClassName, "nlvr_hands") eq(weapons.GetStored("nlvr_hands").Spawnable, false)
end
function cases.attachments()
    local m = S.Model{model = "gun.mdl", pos = Vector(10, 20, 30), ang = Angle(0, 90, 0),
        attachments = {{name = "muzzle", pos = Vector(4, 0, 0), ang = Angle(0, 15, 0)}}}
    eq(m:LookupAttachment("muzzle"), 1) eq(m:LookupAttachment("absent"), 0) eq(S.Model():LookupAttachment("muzzle"), -1)
    eq(m:GetAttachment(0), nil) local a = m:GetAttachment(1) vec(a.Pos, Vector(10, 24, 30)) near(a.Ang.y, 105)
end
function cases.bones()
    local m = S.Model{model = "gun.mdl", pos = Vector(10, 20, 30), ang = Angle(0, 90, 0),
        bones = {{name = "ValveBiped.Bip01_R_Hand", pos = Vector(2, 0, 1)}}}
    eq(m:LookupBone("ValveBiped.Bip01_R_Hand"), 0) eq(m:LookupBone("absent"), nil) eq(m:GetBoneCount(), 1)
    vec(m:GetBonePosition(0), m:GetPos()) eq(m:GetBoneMatrix(0), nil)
    m:SetupBones() vec(m:GetBonePosition(0), Vector(10, 22, 31))
    vec(m:GetBoneMatrix(0):GetTranslation(), Vector(10, 22, 31)) near(m:GetBoneMatrix(0):GetAngles().y, 90)
    eq(m:GetBoneMatrix(1), nil)
end
function cases.model_lifecycle()
    local models = S.ClientsideModels({["gun.mdl"] = {bones = {{name = "grip"}}}})
    local m = ClientsideModel("gun.mdl", 0) eq(models[1], m) eq(m:GetModel(), "gun.mdl") eq(m:LookupBone("grip"), 0)
    m:SetNoDraw(true) eq(m:GetNoDraw(), true) m:DrawModel() eq(m.draws, 1) m:Remove() eq(m.valid, false)
end
assert(cases[scenario], scenario)()
print("PASS " .. scenario)
