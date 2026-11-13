local phase, class, began, last, initial = -1, nil, 0, 0, {}
local heldWall, heldId, deployLocked
local function out(kind, data) data = data or {} data.kind, data.phase, data.class = kind, phase, class print("NLVR_K " .. util.TableToJSON(data)) end
weapons.Register({Base = "weapon_base", PrintName = "Reload fixture", Spawnable = false,
    WorldModel = "models/weapons/w_pistol.mdl", Primary = {ClipSize = 4, DefaultClip = 4, Ammo = "Pistol"},
    Secondary = {Ammo = "none", ClipSize = -1}, Reload = function(self)
        self.kReloads = (self.kReloads or 0) + 1
        out("swep-reload", {count = self.kReloads}) self:DefaultReload(ACT_VM_RELOAD)
    end}, "nlvr_k_swep")
concommand.Add("nlvr_k_phase", function(ply, _, args)
    ply = Entity(1)
    if not NLVR_SV or not NLVR_SV.Players[ply] then return end
    local nextPhase, nextClass = tonumber(args[1]), args[2]
    if not nextPhase or not nextClass then return end
    if phase ~= nextPhase then
        local at, clock = tonumber(args[3]), tonumber(args[4])
        if not at or not clock or math.abs(SysTime() - clock) > 5 then return end
        phase, class, began, last = nextPhase, nextClass, clock - at, -10
        heldWall, heldId, deployLocked = nil, nil, false
        ply:GodEnable() ply:Give(class)
        local w = ply:GetWeapon(class)
        if not IsValid(w) then out("missing-weapon") return end
        ply:SelectWeapon(class)
        local clip = w:GetMaxClip1() > 0 and math.min(3, w:GetMaxClip1()) or -1
        if class == "weapon_shotgun" or class == "weapon_crossbow" then clip = 1 end
        if K_HOLSTER and class == "weapon_pistol" then clip = 1 end
        if K_EMPTY then clip = class == "weapon_rpg" and -1 or 0 end
        w:SetClip1(clip)
        if w:GetPrimaryAmmoType() >= 0 then ply:SetAmmo(K_EMPTY and 0 or 60, w:GetPrimaryAmmoType()) end
        if w:GetSecondaryAmmoType() >= 0 then ply:SetAmmo(4, w:GetSecondaryAmmoType()) end
        initial = {clip = clip, reserve = ply:GetAmmoCount(w:GetPrimaryAmmoType()), max_clip = w:GetMaxClip1()}
        out("setup", initial)
        if K_HOLSTER then
            local cv=GetConVar("sk_auto_reload_time")
            local before=w:GetInternalVariable("m_flHolsterTime")
            w:SetSaveValue("m_flHolsterTime",CurTime())
            out("holster-env",{auto_reload_time=cv and cv:GetString() or "missing",singleplayer=game.SinglePlayer(),
                before=before,set=CurTime(),readback=w:GetInternalVariable("m_flHolsterTime")})
        end
        if class == "gmod_tool" and not w.kObservedReload then
            local original = w.Reload
            w.kObservedReload = true
            w.Reload = function(self, ...)
                out("tool-reload", {time = SysTime() - began})
                if original then return original(self, ...) end
            end
        end
        local d = include("nlvr/modules/sh_reload.lua").Guns[class]
        if d then out("ammo-model", {path = d.ammo, exists = file.Exists(d.ammo, "GAME"), valid = util.IsValidModel(d.ammo)}) end
        local id = w:LookupAttachment("muzzle") local a = id > 0 and w:GetAttachment(id)
        if d and a then
            local p, r = WorldToLocal(a.Pos, a.Ang, w:GetPos(), w:GetAngles())
            out("stock-muzzle", {pos = {p.x, p.y, p.z}, ang = {r.p, r.y, r.r}})
        end
    end
    ply:SendLua("NLVR_K_ACK=" .. phase)
end)
concommand.Add("nlvr_k_select", function(ply, _, args)
    if not K_HOLSTER then return end
    ply = Entity(1) ply:SelectWeapon(args[1])
    out("holster-select", {selected = args[1], time = SysTime() - began})
end)
hook.Add("StartCommand", "nlvr_k_button_probe", function(ply, cmd)
    if ply == Entity(1) and cmd:KeyDown(IN_RELOAD) then out("reload-button", {tick = engine.TickCount(), time = SysTime() - began, player_next_attack = ply:GetInternalVariable("m_flNextAttack")}) end
    if ply == Entity(1) and cmd:KeyDown(IN_ATTACK) then out("attack-button", {tick = engine.TickCount(), time = SysTime() - began}) end
end)
hook.Add("OnPhysgunReload", "nlvr_k_physgun_probe", function(w, ply)
    if ply == Entity(1) then out("physgun-reload", {time = SysTime() - began}) end
end)
hook.Add("Think", "nlvr_k_server_probe", function()
    if not class or CurTime() - last < 0.1 then return end
    last = CurTime()
    local ply = Entity(1) local w = ply:GetActiveWeapon()
    if not IsValid(w) then return end
    local d = NLVR_SV and NLVR_SV.Debug.reload and NLVR_SV.Debug.reload[1]
    if d and d.class == class and d.holding then
        if heldId ~= d.hold_since then heldWall, heldId = SysTime(), d.hold_since end
    else heldWall, heldId = nil, nil end
    if K_HOLSTER then
        local watched = ply:GetWeapon(class)
        if IsValid(watched) then out("holster-watch", {time = SysTime() - began, active = w:GetClass(),
            clip = watched:Clip1(), reserve = ply:GetAmmoCount(watched:GetPrimaryAmmoType()),
            holster = watched:GetInternalVariable("m_flHolsterTime"), game_time = CurTime(),
            primary = watched:GetNextPrimaryFire() - CurTime(), reload = d}) end
    end
    if K_DEPLOY and not deployLocked and SysTime()-began>=2.5 then
        deployLocked=true
        ply:SetSaveValue("m_flNextAttack",1)
        out("deploy-lock",{time=SysTime()-began,remaining=ply:GetInternalVariable("m_flNextAttack")})
    end
    local s = w:GetSaveTable()
    out("sample", {time = SysTime() - began, server_time = CurTime(), hold_wall_seconds = heldWall and SysTime() - heldWall or 0,
        active = w:GetClass(), clip = w:Clip1(), reserve = ply:GetAmmoCount(w:GetPrimaryAmmoType()),
        player_next_attack = ply:GetInternalVariable("m_flNextAttack"), primary = w:GetNextPrimaryFire() - CurTime(), secondary = w:GetNextSecondaryFire() - CurTime(), reload = d,
        native = {in_reload = s.m_bInReload, pump = s.m_bNeedPump, must_reload = s.m_bMustReload,
            delayed1 = s.m_bDelayedFire1, delayed2 = s.m_bDelayedFire2,
            soonest = w:GetInternalVariable("m_flSoonestPrimaryAttack")}, swep_reloads = w.kReloads or 0})
end)
concommand.Add("nlvr_k_done", function()
    hook.Remove("Think", "nlvr_k_server_probe")
    hook.Remove("StartCommand", "nlvr_k_button_probe")
    hook.Remove("OnPhysgunReload", "nlvr_k_physgun_probe")
    concommand.Remove("nlvr_k_select")
    concommand.Remove("nlvr_k_phase") concommand.Remove("nlvr_k_done")
    out("server-stopped", {global_absent = NLVR_SV == nil})
end)
