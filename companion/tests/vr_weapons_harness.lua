-- W's tests exercise the actual modules with S's independent Euler/weapon stand-ins.
local root,scenario,library,profileFixture=...
library=library or "stock"
local S=assert(loadfile(root.."/companion/tests/vr_stubs.lua"))() S.Math()
bit=require("bit") math.Clamp=function(x,a,b) return math.max(a,math.min(b,x)) end
local function near(a,b,t) assert(math.abs(a-b)<(t or 0.00001),tostring(a).." ~= "..tostring(b)) end
local function eq(a,b) assert(a==b,tostring(a).." ~= "..tostring(b)) end
local function vec(a,b,t) near((a-b):Length(),0,t) end
local V,A=getmetatable(Vector()),getmetatable(Angle())
function V:Angle() return Angle(math.deg(math.atan2(-self.z,math.sqrt(self.x^2+self.y^2))),math.deg(math.atan2(self.y,self.x)),0) end
function V:AngleEx(up) local a=self:Angle() a.r=math.deg(math.atan2(up:Dot(a:Right()),up:Dot(a:Up()))) return a end
isvector=function(v) return getmetatable(v)==V end isangle=function(a) return getmetatable(a)==A end
IsValid=function(e) return type(e)=="table" and e.valid==true end
function include(path) return assert(loadfile(root.."/vr/addon/lua/"..path))() end
IN_ATTACK,IN_ATTACK2,MASK_SHOT,RENDERGROUP_OPAQUE,DMG_CLUB,EF_NOINTERP=1,2048,1174421507,0,128,8
local clock,tick=1,66
CurTime=function() return clock end RealTime=CurTime FrameNumber=function() return tick end
engine={TickCount=function() return tick end,TickInterval=function() return 1/66 end}
local hooks,errors,effects,lights={},{},{},{}
MsgN=function(s) errors[#errors+1]=s end
local currentGM={}
gmod={GetGamemode=function() return currentGM end}
local levels
hook,hooks,levels=assert(loadfile(root.."/companion/tests/vr_hook_fixture.lua"))().New(library,hooks)
local trace
util={TraceLine=function(t) if trace then return trace(t) end return {Hit=false,HitPos=t.endpos,HitNormal=Vector(-1,0,0)} end,
    Effect=function(name,data,override,recipients) effects[#effects+1]={name=name,data=data,override=override,recipients=recipients} end}
util.TraceHull=util.TraceLine
function EffectData()
    local e={}
    for _,key in ipairs({"Start","Origin","Scale","Angles","Flags","Normal","Entity","SurfaceProp","HitBox","DamageType","Attachment"}) do e["Set"..key]=function(self,v) self[key]=v end end
    return e
end
function DynamicLight(id) lights[id]={} return lights[id] end
function DamageInfo()
    local e={}
    for _,key in ipairs({"Attacker","Inflictor","DamageType","Damage","DamagePosition","DamageForce"}) do
        e["Set"..key]=function(self,v) self[key]=v end e["Get"..key]=function(self) return self[key] end
    end
    return e
end
local registered=S.WeaponRegistry()
local modelFixtures={["gun.mdl"]={bones={{name="ValveBiped.Bip01_R_Hand",pos=Vector(1,2,3)}},
    attachments={{name="muzzle",pos=Vector(9,2,3)}}}}
modelFixtures["pistol.mdl"]={bones={{name="ValveBiped.Bip01_R_Hand",pos=Vector(1,2,3)}},
    attachments={{name="muzzle",pos=Vector(-7,2,3),ang=Angle(0,180,0)}}}
local rawModels=S.ClientsideModels(modelFixtures)
local originalModel=ClientsideModel
local function modelExtra(m)
    function m:GetTable() return self end
    function m:SetSkin(n) self.skin=n end function m:SetBodygroup() end
    function m:SetModelScale(n) self.scale=n end function m:InvalidateBoneCache() end
    function m:GetModelBounds() return Vector(-8,-2,-2),Vector(20,2,2) end
    return m
end
ClientsideModel=function(...) return modelExtra(originalModel(...)) end
local function weapon(class,model)
    class=class or "weapon_pistol"
    local w=S.Weapon{class=class,model=model or (class=="weapon_pistol" and "pistol.mdl" or "gun.mdl")}
    function w:IsPlayer() return false end function w:GetSkin() return 0 end
    function w:GetTable() return self end
    function w:GetNumBodyGroups() return 0 end function w:EmitSound(name) self.sound=name end
    return w
end
local ply=S.Player{weapons={weapon()}}
ply:SelectWeapon("weapon_pistol")
function ply:HasWeapon(c) return IsValid(self:GetWeapon(c)) end
function ply:Alive() return self.alive~=false end function ply:InVehicle() return self.vehicle==true end
ply.pos=Vector()
function ply:GetPos() return self.pos end
function ply:EyePos() return self.pos+Vector(0,0,64) end function ply:EntIndex() return 1 end
function ply:GetShootPos() return self:EyePos() end
local rawBullet=S.Bullet
function S.Bullet(data)
    local b=rawBullet(data)
    if not data or data.Src==nil then b.Src=ply:GetShootPos() end
    return b
end
LocalPlayer=function() return ply end
local function physical(p)
    local phys={valid=true,pos=p or Vector(12,-6,48),velocity=Vector(),ang=Angle(),spin=Vector()}
    function phys:GetPos() return self.pos end function phys:SetPos(v) self.pos=v end
    function phys:GetAngles() return self.ang end function phys:SetAngles(a) self.ang=a end
    function phys:GetVelocity() return self.velocity end function phys:SetVelocity(v) self.velocity=v end
    function phys:SetVelocityInstantaneous(v) self.velocity=v self.instant=true end
    function phys:GetAngleVelocity() return self.spin end function phys:AddAngleVelocity(v) self.spin=self.spin+v end
    function phys:Wake() end function phys:IsMotionEnabled() return self.motion~=false end
    function phys:EnableMotion(v) self.motion=v end function phys:ApplyForceOffset(v) self.force=v end
    return phys
end
local pairsMade={}
constraint={NoCollide=function(a,b,_,_,restore)
    eq(restore,true)
    local pair={valid=true,a=a,b=b}
    function pair:Remove() self.valid=false end
    pairsMade[#pairsMade+1]=pair return pair
end}
local function entity(class,pos,owner)
    local e={valid=true,class=class,pos=pos or Vector(),ang=Angle(),owner=owner,velocity=Vector(100,0,0),health=100,custom=false}
    function e:IsPlayer() return false end function e:IsNPC() return false end function e:IsWorld() return false end
    function e:GetClass() return self.class end function e:EntIndex() return 100 end function e:GetOwner() return self.owner or S.NULL end
    function e:GetPos() return self.pos end function e:SetPos(v) self.pos=v end
    function e:GetAngles() return self.ang end function e:SetAngles(a) self.ang=a end
    function e:GetNoDraw() return self.nodraw==true end function e:SetNoDraw(v) self.nodraw=v end
    function e:AddEffects(n) self.ef=bit.bor(self.ef or 0,n) end
    function e:RemoveEffects(n) self.ef=bit.band(self.ef or 0,bit.bnot(n)) end
    function e:IsEffectActive(n) return bit.band(self.ef or 0,n)~=0 end
    function e:GetPhysicsObject() return self.phys or S.NULL end
    function e:GetVelocity() return self.velocity end function e:SetLocalVelocity(v) self.velocity=v end
    function e:GetCustomCollisionCheck() return self.custom end function e:SetCustomCollisionCheck(v) self.custom=v end
    function e:CollisionRulesChanged() end function e:TakeDamageInfo(info) self.health=self.health-info.Damage self.damage=info end
    return e
end
local function pose(pos,ang) return {valid=true,pos=pos or Vector(12,-6,48),ang=ang or Angle(),vel=Vector(),angvel=Vector(),buttons=0} end
local function core(server,gm)
    if gm then currentGM=gm end
    local c={Debug={},Settings={gun_angle=0,foregrip=1,melee=1},Space={scale=40},Hand={},Pose={},Net={},sent={},handlers={},events={},movers={},resolvers={}}
    c.Input=include("nlvr/core/cl_input.lua").New()
    c.Input.Update({},clock,false)
    c.Pose.left,c.Pose.right,c.Pose.head=pose(Vector(12,12,48)),pose(),pose(Vector(0,0,64),Angle(0,45,0))
    for _,name in ipairs({"left","right"}) do c.Hand[name]={target=c.Pose[name],shown=pose(c.Pose[name].pos,c.Pose[name].ang),blocked=false} end
    c.Reach=function() return 100 end
    c.Players={[ply]={active=true,scale=40,lastSync=clock,head=c.Pose.head,hands={left=c.Pose.left,right=c.Pose.right},history={left={},right={}},
        interact={left={proxy=entity("hand"),phys=physical(Vector(12,12,48))},right={proxy=entity("hand"),phys=physical()},options={melee=true}}}}
    c.Aim=function(a,owner) c.aim=a c.aimOwner=owner end
    c.owners,c.releasedProjectiles={},{}
    c.ClaimHand=function(_,hand,owner,claimed)
        if c.owners[hand] and c.owners[hand]~=owner then return false end
        c.owners[hand]=claimed and owner or nil return true
    end
    c.RegisterReleased=function(_,ent,seconds) c.releasedProjectiles[ent]={ply=ply,untilTime=clock+seconds} return true end
    c.feedback={}
    c.ProjectileFeedback=function(_,hand) c.feedback[hand]=(c.feedback[hand] or 0)+1 return true end
    local registry=include("nlvr/core/sh_modules.lua").New(c) c.registry=registry
    c._On=function(entry,event,fn)
        local list=c.events[event] or {} c.events[event]=list list[#list+1]={entry,fn}
    end
    c.Emit=function(event,...)
        for _,r in ipairs(c.events[event] or {}) do registry:Call(r[1],r[2],...) end
    end
    c._Mover=function(entry,priority,fn) c.movers[#c.movers+1]={entry=entry,fn=fn,priority=priority} end
    c._Resolver=function(entry,priority,fn) c.resolvers[#c.resolvers+1]={entry=entry,fn=fn,priority=priority} end
    c.Net.On=function(kind,fn) c.handlers[kind]=fn end
    c.Net.Send=function(a,b,d)
        local kind,writer=server and b or a,server and d or b
        local wire=S.Wire() writer(wire) c.sent[kind]=wire
        if not server and kind==64 and not c.noAck then
            wire.Rewind() local class=wire.ReadString() wire.ReadBool()
            for i=1,9 do wire.ReadFloat() end
            wire.ReadBool() wire.ReadFloat() wire.ReadBool()
            local token=wire.ReadUInt(16)
            local ack=S.Wire() ack.WriteString(class) ack.WriteUInt(token,16) ack.Rewind()
            net=ack c.handlers[66]()
        end
        return true
    end
    c.move=function(cmd) for _,m in ipairs(c.movers) do registry:Call(m.entry,m.fn,cmd) end assert(#errors==0,table.concat(errors,"\n")) end
    c.frame=function() c.Input.claims={left={},right={}} c.Emit("frame") assert(#errors==0,table.concat(errors,"\n")) end
    c.module=include(server and "nlvr/modules/sv_weapons.lua" or "nlvr/modules/cl_weapons.lua")
    registry:Add(c.module) registry:Start()
    return c
end
local W=include("nlvr/modules/sh_weapons.lua")
local function receive(c,class,opts)
    opts=opts or {} local wire=S.Wire()
    wire.WriteString(class or ply:GetActiveWeapon():GetClass()) wire.WriteBool(opts.left or false)
    local kind=include("nlvr/modules/sh_weapons.lua").Kind(class or ply:GetActiveWeapon():GetClass())
    -- Existing temporal-guard fixtures use this declared synthetic profile. The
    -- real-hand/mesh cases always supply their measured three-dimensional end.
    local synthetic=(class or ply:GetActiveWeapon():GetClass())=="weapon_stunstick" and .48 or .56
    for _,v in ipairs({opts.offset or Vector(.2,0,0),opts.fore or Vector(.23,0,-.025),opts.meleeTip or (kind=="melee" and Vector(synthetic,0,0) or Vector())}) do
        wire.WriteFloat(v.x) wire.WriteFloat(v.y) wire.WriteFloat(v.z)
    end
    wire.WriteBool(opts.two or false) wire.WriteFloat(opts.pitch or 0) wire.WriteBool(opts.melee~=false)
    wire.WriteUInt(opts.token or 42,16)
    wire.Rewind() net=wire c.handlers[64](ply)
end
local function arm(c,class)
    local w=weapon(class) w.owner=ply ply.inventory[#ply.inventory+1]=w ply.active=w
    if c.Weapon and type(c.Weapon)=="function" then receive(c,class) else c.frame() end
    return w
end
local function advance(c,dt) clock=clock+dt tick=tick+1 if c then c.Players[ply].lastSync=clock end end
local function checkErrors() assert(#errors==0,table.concat(errors,"\n")) end
local cases={}
function cases.uncalibrated_thumb_up()
    local Model=include("nlvr/modules/cl_weapons_model.lua")
    for _,a in ipairs({Angle(4.6244,-179.3405,-171.2484),Angle(10.8882,2.5023,-176.2565),Angle(12.4623,178.3265,177.5289)}) do
        modelFixtures["measured.mdl"]={bones={{name="ValveBiped.Bip01_R_Hand",pos=Vector(),ang=a}}}
        local frame={pos=Vector(1.94,0,0),ang=Angle(-.52,-1.03,-.10),grip=Vector(3.3,-.96,.36)}
        local m=ClientsideModel("measured.mdl",0)
        local g=Model.Measure(m,"weapon_pistol",frame,"left")
        assert(g.handAngle:Up().z>.95,"uncalibrated left thumb points down: "..g.handAngle:Up().z)
    end
end
function cases.unknown_up_muzzle()
    local Model=include("nlvr/modules/cl_weapons_model.lua")
    for _,muzzle in ipairs({true,false}) do
        modelFixtures["unlisted_rail.mdl"]={bones={{name="ValveBiped.Bip01_R_Hand",pos=Vector()}},attachments=muzzle and {{name="muzzle",pos=Vector(-25,0,0),ang=Angle(-90,0,0)}} or {}}
        local m=ClientsideModel("unlisted_rail.mdl",0)
        function m:GetModelBounds() return Vector(-30,-2,-2),Vector(3,2,2) end
        local a={model=m,geometry=Model.Measure(m,"unlisted")};Model.Pose(a,Vector(),Angle(),40,0)
        vec(-m:GetAngles():Forward(),Vector(1,0,0)) vec(m:GetAngles():Up(),Vector(0,0,1))
    end
end
function cases.independent_grip()
    local Model=include("nlvr/modules/cl_weapons_model.lua")
    modelFixtures["own_grip.mdl"]={bones={{name="ValveBiped.Bip01_R_Hand",pos=Vector()},
        {name="ValveBiped.Bip01_R_Finger2",pos=Vector(2,0,0)},{name="ValveBiped.Bip01_R_Finger21",pos=Vector(3,1,0)},{name="ValveBiped.Bip01_R_Finger22",pos=Vector(2,2,0)}}}
    local m=ClientsideModel("own_grip.mdl",0)
    for _,side in ipairs({"right","left"}) do
        local own={pos=Vector(2,0,0),ang=Angle(),grip=Vector(3,0,0),calibrated=true}
        local a={model=m,geometry=Model.Measure(m,"weapon_smg1",own,side)};Model.Pose(a,Vector(),Angle(),40,0)
        local p={} for i=1,3 do p[i]=m:GetBoneMatrix(i):GetTranslation() end
        local centre=include("nlvr/core/cl_hand_model.lua").Circle(p[1],p[2],p[3])
        assert((centre-Vector(1,0,0)):Length()<.8,"actual weapon grip differs from holding grasp")
    end
end
function cases.holding_grasp()
    local Model=include("nlvr/modules/cl_weapons_model.lua") local m=ClientsideModel("gun.mdl",0)
    local own={pos=Vector(2,0,0),ang=Angle(),anatomy=Angle(),grip=Vector(3.3,0,0),calibrated=true}
    local previous
    for _,value in ipairs({3.3,13.1,8035}) do
        local other={pos=Vector(2,0,0),ang=Angle(),grip=Vector(value,0,0),calibrated=true}
        local g=Model.Measure(m,"weapon_smg1",own,"left",other)
        local a={model=m,geometry=g} Model.Pose(a,Vector(),Angle(),40,0)
        assert(a.grip:Length()<=4,"anchor escaped holding palm")
        if previous then vec(a.pos,previous) end previous=a.pos
    end
    own.grip=Vector(8035,0,0)
    local a={model=m,geometry=Model.Measure(m,"weapon_smg1",own,"left",own)} Model.Pose(a,Vector(),Angle(),40,0)
    assert(a.grip:Length()<=4,"holding grasp must be bounded too")
end
function cases.tip_only_aim()
    local c=core()
    c.Pose.right.ang=Angle(-30.3,0,0)
    c.Frame={controllers={right={valid=false,model="pico_4_ultra_controller_right",revision=1,aim={valid=true,pos=Vector(),ang=Angle(30.3,0,0)}}}}
    local msg=MsgN MsgN=function() end include("nlvr/core/cl_frames.lua").New(c).Apply() MsgN=msg
    vec(c.Pose.right.ang:Forward(),c.Pose.right.aim.ang:Forward())
    c.Hand.right.target=c.Pose.right c.frame()
    vec(c.Weapon.Active.aimAng:Forward(),Vector(1,0,0)) c.registry:Stop()
end
function cases.generic_models()
    local Model=include("nlvr/modules/cl_weapons_model.lua")
    for _,v in ipairs({{"weapon_crossbow","w_crossbow",1,true},{"weapon_pistol","w_pistol",-1},{"weapon_shotgun","w_shotgun",-1},{"weapon_ar2","w_irifle",-1}}) do
        for _,attachment in ipairs({true,false}) do
            local path="models/weapons/"..v[2]..".mdl"
            -- The real w_shotgun muzzle is tilted 8.6 degrees from its authored barrel.
            local angle=v[2]=="w_shotgun" and Angle(8.5238,178.8787,0) or v[4] and Angle(-90,0,0) or Angle(0,v[3]<0 and 180 or 0,0)
            modelFixtures[path]={bones={{name="ValveBiped.Bip01_R_Hand",pos=Vector()}},attachments=attachment and {{name="muzzle",pos=Vector(v[3]*20,0,0),ang=angle}} or {}}
            local m=ClientsideModel(path,0) local a={model=m,geometry=Model.Measure(m,v[1])};Model.Pose(a,Vector(),Angle(),40,0)
            local p,ang=m:GetPos(),m:GetAngles()
            a.geometry=Model.Measure(m,"unknown_"..v[2]);Model.Pose(a,Vector(),Angle(),40,0)
            vec(m:GetPos(),p) vec(m:GetAngles():Forward(),ang:Forward()) vec(m:GetAngles():Up(),ang:Up())
            local barrel=LocalToWorld(Vector(v[3],0,0),Angle(),Vector(),m:GetAngles()) vec(barrel,Vector(1,0,0))
        end
    end
    modelFixtures["unknown_minus.mdl"]={bones={{name="ValveBiped.Bip01_R_Hand",pos=Vector()}}}
    local m=ClientsideModel("unknown_minus.mdl",0)
    function m:GetModelBounds() return Vector(-30,-2,-2),Vector(3,2,2) end
    local a={model=m,geometry=Model.Measure(m,"unknown")};Model.Pose(a,Vector(),Angle(),40,0)
    vec(-m:GetAngles():Forward(),Vector(1,0,0)) vec(m:GetAngles():Up(),Vector(0,0,1))
end
function cases.trigger_release_latch()
    for _,left in ipairs({false,true}) do
        local c=core() c.Input.Mirror(left) arm(c,"weapon_smg1") local a=c.Weapon.Active local off=c.Input.offHand
        c.Hand[off].target.pos=c.Hand[c.Input.mainHand].shown.pos+a.geometry.fore*40
        c.Input[off].grip=true c.Input[off].trigger=true c.frame() assert(c.Weapon.Active.twoHanded)
        c.Hand[off].target.pos=c.Hand[off].target.pos+Vector(40,0,0) c.frame()
        eq(c.Input.Owner(off,"trigger"),"weapons")
        arm(c,"nlvr_hands") c.frame() eq(c.Input.Owner(off,"trigger"),"weapons")
        c.Input[off].trigger=false c.frame() eq(c.Input.Owner(off,"trigger"),nil)
        c.Input[off].trigger=true c.frame() eq(c.Input.Owner(off,"trigger"),nil)
        c.registry:Stop()
    end
    for _,left in ipairs({false,true}) do
        local c=core() c.Input.Mirror(left) local main=c.Input.mainHand
        c.Input[main].trigger=true arm(c,"weapon_smg1") c.frame()
        arm(c,"nlvr_hands") c.frame() eq(c.Input.Owner(main,"trigger"),"weapons")
        c.Input[main].trigger=false c.frame() eq(c.Input.Owner(main,"trigger"),nil) c.registry:Stop()
    end
end
function cases.unprofiled_frame()
    local Model=include("nlvr/modules/cl_weapons_model.lua")
    for _,attachment in ipairs({true,false}) do
        local path="models/weapons/w_smg1.mdl"
        modelFixtures[path]={bones={{name="ValveBiped.Bip01_R_Hand",pos=Vector(1,2,3),ang=Angle(4,9,13)}},
            attachments=attachment and {{name="muzzle",pos=Vector(19,2,3),ang=Angle()}} or {}}
        local model=ClientsideModel(path,RENDERGROUP_OPAQUE)
        local profiled=Model.Measure(model,"weapon_smg1")
        local generic=Model.Measure(model,"unprofiled_test_smg")
        local a={model=model,geometry=profiled} Model.Pose(a,Vector(),Angle(),40,0)
        local expected=model:GetAngles()
        a.geometry=generic Model.Pose(a,Vector(),Angle(),40,0)
        vec(model:GetAngles():Forward(),expected:Forward()) vec(model:GetAngles():Up(),expected:Up())
        vec(generic.fore,profiled.fore)
    end
    modelFixtures["barrel_y.mdl"]={bones={{name="ValveBiped.Bip01_R_Hand",pos=Vector()}},
        attachments={{name="muzzle",pos=Vector(0,30,0),ang=Angle(0,90,0)}}}
    local model=ClientsideModel("barrel_y.mdl",RENDERGROUP_OPAQUE)
    function model:GetModelBounds() return Vector(-1,-5,-1),Vector(1,30,1) end
    local g=Model.Measure(model,"unprofiled_y")
    assert(g.fore and g.fore.x>=.18 and g.fore.x<=.45,"foregrip must measure barrel extent, not X extent")
    local a={model=model,geometry=g} Model.Pose(a,Vector(),Angle(),40,0)
    local _,barrel=LocalToWorld(Vector(),Angle(0,90,0),Vector(),model:GetAngles())
    vec(barrel:Forward(),Vector(1,0,0)) vec(model:GetAngles():Up(),Vector(0,0,1))
end
function cases.grip_release_latches()
    for _,left in ipairs({false,true}) do
        for _,exit in ipairs({"distance","switch","hands"}) do
            local c=core() c.Input.Mirror(left)
            local main,off=c.Input.mainHand,c.Input.offHand
            c.Input[main].grip=true
            arm(c,"weapon_smg1")
            local a=c.Weapon.Active
            c.Hand[off].target.pos=c.Hand[main].shown.pos+a.geometry.fore*40
            c.Input[off].grip=true c.frame() assert(c.Weapon.Active.twoHanded)
            if exit=="distance" then c.Hand[off].target.pos=c.Hand[off].target.pos+Vector(40,0,0)
            elseif exit=="switch" then arm(c,"weapon_pistol")
            else arm(c,"nlvr_hands") end
            c.frame()
            eq(c.Input.Owner(off,"grip"),"weapons")
            if exit=="hands" then eq(c.Input.Owner(main,"grip"),"weapons") end
            c.Input[off].grip=false c.Input[main].grip=false c.frame()
            eq(c.Input.Owner(off,"grip"),nil)
            if exit=="hands" then eq(c.Input.Owner(main,"grip"),nil) end
            c.Input[off].grip=true c.frame()
            eq(c.Input.Owner(off,"grip"),nil) -- a real release/repress now belongs to P.
            c.registry:Stop()
        end
    end
end
function cases.palm_anchor()
    for _,side in ipairs({"right","left"}) do
        local c=core()
        c.HandModelFrames={[side]={pos=Vector(2,0,0),ang=Angle(0,0,side=="right" and 90 or -90)}}
        if side=="left" then c.Input.Mirror(true) end
        c.frame()
        local a=c.Weapon.Active
        local palm=LocalToWorld(a.geometry.gripPos,Angle(),a.model:GetPos(),a.model:GetAngles())
        vec(palm,c.Hand[side].shown.pos)
        vec(a.aimAng:Forward(),Vector(1,0,0)) vec(a.aimAng:Up(),Vector(0,0,1))
        assert(c.Hand[side].shown.ang:Up().z>.95,"anatomical thumb side must face up")
        local wrist=include("nlvr/core/cl_hand_model.lua").Wrist(c.HandModelFrames[side],c.Hand[side].shown,40)
        vec(wrist,a.model:GetBoneMatrix(a.geometry.bone):GetTranslation())
        c.registry:Stop()
    end
end
function cases.left_grip_basis()
    local c=core()
    c.HandModelFrames={right={pos=Vector(1.9432,-.0352,-.0173),ang=Angle(.51,-1.04,179.63)},left={pos=Vector(1.9432,-.035,.0176),ang=Angle(-.52,-1.03,-.10)}}
    for _,left in ipairs({false,true}) do
        c.Input.Mirror(left) c.frame() local a=c.Weapon.Active local side=left and "left" or "right"
        assert(c.Hand[side].shown.ang:Up().z>.95,"thumb side inverted")
        vec(a.model:GetAngles():Up(),Vector(0,0,1))
        local wrist=include("nlvr/core/cl_hand_model.lua").Wrist(c.HandModelFrames[side],c.Hand[side].shown,40)
        vec(wrist,a.model:GetBoneMatrix(a.geometry.bone):GetTranslation())
    end
end
function cases.remeasure_scale()
    local c=core() c.Space.scale=80 c.frame()
    local model=c.Weapon.Active.model
    local original=model.GetBoneMatrix
    function model:GetBoneMatrix(id)
        local m=original(self,id)
        if not m then return end
        local localPos=WorldToLocal(m:GetTranslation(),Angle(),self:GetPos(),self:GetAngles())
        local pos=LocalToWorld(localPos*(self.scale or 1),Angle(),self:GetPos(),self:GetAngles())
        return {GetTranslation=function() return pos end,GetAngles=function() return m:GetAngles() end}
    end
    local authored
    for _=1,2 do
        c.HandModelFrames={right={pos=Vector(2,0,0),ang=Angle()}}
        c.frame()
        authored=authored or c.Weapon.Active.geometry.gripPos
        vec(c.Weapon.Active.geometry.gripPos,authored)
        near(model.scale,2)
    end
end
function cases.grasp_anchor()
    local c=core()
    c.HandModelFrames={right={pos=Vector(2,0,0),ang=Angle(),grip=Vector(2,1,0)},
        left={pos=Vector(2,0,0),ang=Angle(),grip=Vector(2,-1,0)}}
    c.frame()
    local a=c.Weapon.Active local relative=a.model:GetPos()-c.Hand.right.shown.pos
    vec(LocalToWorld(a.geometry.gripPos,Angle(),a.model:GetPos(),a.model:GetAngles()),a.grip)
    vec(a.grip,c.Hand.right.shown.pos+Vector(0,1,0))
    c.Input.Mirror(true) c.frame() a=c.Weapon.Active
    vec(LocalToWorld(a.geometry.gripPos,Angle(),a.model:GetPos(),a.model:GetAngles()),a.grip)
    vec(a.grip,c.Hand.left.shown.pos+Vector(0,-1,0))
    -- Each authored anchor now uses the holding hand; the opposite hand is not an authoring reference.
    assert((a.grip-c.Hand.left.shown.pos):Length()<4)
end
function cases.melee_hand_frame()
    local c=core() c.HandModelFrames={right={pos=Vector(2,0,0),ang=Angle(0,0,180)},left={pos=Vector(2,0,0),ang=Angle()}}
    arm(c,"weapon_crowbar") vec(c.Hand.right.shown.ang:Up(),c.Weapon.Active.aimAng:Up())
    c.Input.Mirror(true) c.frame() vec(c.Hand.left.shown.ang:Up(),c.Weapon.Active.aimAng:Up())
end
function cases.released_weapon_curls()
    local c=core() c.frame() assert(c.Hand.right.grip_curls)
    arm(c,"nlvr_hands") eq(c.Hand.right.grip_curls,nil)
    arm(c,"weapon_smg1")
    local a=c.Weapon.Active
    c.Hand.left.target.pos=c.Hand.right.shown.pos+a.geometry.fore*40 c.Input.off.grip=true c.frame()
    assert(c.Hand.left.grip_curls)
    c.Input.off.grip=false c.frame() eq(c.Hand.left.grip_curls,nil)
end
function cases.kinds()
    local classes={nlvr_hands="hands",weapon_crowbar="melee",weapon_stunstick="melee",weapon_frag="grenade",weapon_bugbait="grenade",
        weapon_pistol="clip",weapon_357="clip",weapon_smg1="clip",weapon_ar2="clip",weapon_shotgun="shotgun",weapon_crossbow="crossbow",
        weapon_rpg="rpg",weapon_physgun="physgun",gmod_tool="toolgun",gmod_camera="swep",weapon_medkit="swep",weapon_fists="swep",unknown="swep"}
    for class,kind in pairs(classes) do eq(W.Kind(class),kind) end
end
function cases.grip_math()
    for i=1,100 do
        local p,a=Vector(i*.11,-i*.07,i*.03),Angle(i*1.1,i*2.3,-i*.9)
        local target,rotation=Vector(i,3*i,-i),Angle(i*.7,-i*1.3,i*.8)
        local origin,ang=W.Place(p,a,target,rotation,.75)
        local q,b=LocalToWorld(p*.75,a,origin,ang)
        vec(q,target) vec(b:Forward(),rotation:Forward()) vec(b:Up(),rotation:Up())
    end
end
function cases.model_muzzle()
    local c=core() c.frame() local a=c.Weapon.Active
    eq(a.geometry.bone,0) vec(a.geometry.muzzle,Vector(.2,0,0))
    vec(c.Weapon.Muzzle(),Vector(20,-6,48)) eq(a.ent,ply:GetActiveWeapon())
    c.registry:Stop() eq(c.Weapon,nil) eq(a.model.valid,false)
end
function cases.fallback()
    local c=core() ply.active=weapon("weapon_rpg","fallback.mdl") c.frame()
    vec(c.Weapon.Active.geometry.muzzle,Vector(.86,0,0)) near(c.Weapon.Active.geometry.fore.x,.34)
end
function cases.switch()
    local c=core() c.frame() local first=c.Weapon.Active.model
    arm(c,"weapon_shotgun") eq(first.valid,false) eq(c.Weapon.Active.kind,"shotgun") eq(#rawModels,2)
end
function cases.left()
    local c=core() c.frame() local old=c.Weapon.Active.model
    c.Input.Mirror(true) c.frame() eq(c.Weapon.Active.hand,"left") eq(old.valid,false)
    local a=c.Weapon.Active vec(c.Weapon.Muzzle(),c.Hand.left.shown.pos+Vector(8,0,0)) near(a.model.scale,1)
end
function cases.pitch()
    local c=core() c.Settings.gun_angle=30 c.frame()
    local _,dir=c.Weapon.Ray() vec(dir,Angle(30,0,0):Forward())
end
function cases.stopped()
    local c=core() c.Hand.right.shown.pos=Vector(4,-6,48) c.frame()
    vec(c.Weapon.Muzzle(),Vector(12,-6,48)) vec(c.Pose.right.pos,Vector(12,-6,48))
end
function cases.world_draw()
    local c=core() c.frame() local m=c.Weapon.Active.model
    hook.Run("PreDrawTranslucentRenderables",true,false) hook.Run("PreDrawTranslucentRenderables",false,true) eq(m.draws,nil)
    hook.Run("PreDrawTranslucentRenderables",false,false) eq(m.draws,1)
end
function cases.custom_draw()
    local c=core() local e=ply:GetActiveWeapon() e.scripted=true
    e.DrawWorldModel=function(self) self:DrawModel() end c.frame()
    hook.Run("PreDrawTranslucentRenderables",false,false) eq(c.Weapon.Active.customDraws,1)
    e.DrawWorldModel=function() error("requires weapon internals") end
    hook.Run("PreDrawTranslucentRenderables",false,false) eq(c.Weapon.Active.customFailed,true)
    hook.Run("PreDrawTranslucentRenderables",false,false) eq(c.Weapon.Active.model.draws,3)
end
function cases.claims()
    local c=core() c.frame() eq(c.Input.Owner("main","grip"),"weapons") eq(c.Input.Owner("main","trigger"),"weapons")
    eq(c.Input.Owner("off","grip"),nil) eq(c.Input.Owner("main","a"),nil)
    c.Input.Update({right_trigger={active=true,state=true},right_a={active=true,state=true}},clock,false)
    c.frame() local cmd=S.Command() c.move(cmd) assert(cmd:KeyDown(IN_ATTACK) and cmd:KeyDown(IN_ATTACK2))
end
function cases.ui_and_reload_claim()
    local c=core() c.Input.Update({right_trigger={active=true,state=true},right_a={active=true,state=true}},clock,false)
    c.Input.Claim("main","trigger","ui") c.Emit("frame") c.Input.Claim("main","a","reload")
    local cmd=S.Command() cmd:SetButtons(bit.bor(IN_ATTACK,IN_ATTACK2))
    c.move(cmd) eq(cmd:KeyDown(IN_ATTACK),false) eq(cmd:KeyDown(IN_ATTACK2),false)
end
function cases.convergence()
    local c=core() c.frame() local hit=Vector(200,-6,48)
    trace=function(t) return {Hit=true,HitPos=hit,HitNormal=Vector(-1,0,0)} end
    c.move(S.Command()) vec(c.aim:Forward(),(hit-ply:EyePos()):GetNormalized()) vec(c.Debug.weapons.aim_point,hit)
    c.Weapon.ConvergeAt(800) c.move(S.Command()) vec(c.Debug.weapons.aim_point,Vector(820,-6,48))
    c.Weapon.ConvergeAt(nil) c.move(S.Command()) vec(c.Debug.weapons.aim_point,hit)
end
function cases.filters()
    local c=core() local held=entity("prop_physics") c.Hand.left.held={ent=held} c.frame()
    trace=function(t) assert(t.filter(ply)==false and t.filter(held)==false and t.filter(c.Weapon.Active.model)==false)
        return {Hit=false,HitPos=t.endpos} end c.move(S.Command())
end
function cases.foregrip()
    local c=core() arm(c,"weapon_smg1")
    c.Pose.left.pos=Vector(21.2,-6,47) c.Hand.left.target=c.Pose.left
    c.Input.off.grip=true c.frame() eq(c.Weapon.Active.twoHanded,true)
    local _,dir=c.Weapon.Ray() vec(dir,(c.Pose.left.pos-c.Hand.right.shown.pos):GetNormalized())
    vec(dir,(c.Hand.left.shown.pos-c.Hand.right.shown.pos):GetNormalized())
    eq(c.Input.Owner("off","trigger"),"weapons")
    c.Input.off.trigger=true local cmd=S.Command() c.move(cmd) assert(cmd:KeyDown(IN_ATTACK2))
    c.Input.off.grip=false c.frame() eq(c.Weapon.Active.twoHanded,false)
end
function cases.foregrip_release()
    local c=core() arm(c,"weapon_shotgun") c.Pose.left.pos=Vector(26.4,-6,47) c.Input.off.grip=true c.frame()
    eq(c.Weapon.Active.twoHanded,true) c.Pose.left.pos=Vector(60,-6,48) c.frame() eq(c.Weapon.Active.twoHanded,false)
    c.Pose.left.pos=Vector(26.4,-6,47) c.Settings.foregrip=0 c.frame() eq(c.Weapon.Active.twoHanded,false)
end
function cases.hands_client()
    local c=core() local w=arm(c,"nlvr_hands") local a=c.Weapon.Active
    eq(a.kind,"hands") eq(a.model,nil) eq(c.Weapon.Ray(),nil) eq(c.Input.Owner("main","grip"),nil)
    assert(registered.nlvr_hands.Spawnable==false) local cmd=S.Command() c.Input.main.trigger=true c.move(cmd) eq(cmd:KeyDown(IN_ATTACK),false)
end
function cases.death_exit()
    local c=core() c.frame() local model=c.Weapon.Active.model
    ply.alive=false c.frame() eq(c.Weapon.Active,nil) eq(model.valid,false)
    ply.alive=true c.frame() assert(c.Weapon.Active) c.registry:Stop() eq(c.Weapon,nil)
    for _,entries in pairs(hooks) do assert(next(entries)==nil) end
end
function cases.invalid_tracking()
    local c=core() c.Hand.right.shown.valid=false c.frame() eq(c.Weapon.Muzzle(),nil)
    local cmd=S.Command() c.Input.main.trigger=true c.move(cmd) eq(cmd:KeyDown(IN_ATTACK),false)
end
function cases.server_pose()
    local c=core(true) receive(c) local g=c.Weapon(ply)
    vec(g.muzzle.pos,Vector(20,-6,48)) vec(g.muzzle.ang:Forward(),Vector(1,0,0)) eq(g.class,"weapon_pistol")
    c.Players[ply].interact.right.phys.pos=Vector(4,-6,48) vec(c.Weapon(ply).muzzle.pos,Vector(12,-6,48))
end
function cases.server_wall()
    local c=core(true) receive(c)
    trace=function(t) return {Hit=true,HitPos=Vector(5,-1,60),HitNormal=Vector(-1,0,0)} end
    local g=c.Weapon(ply) eq(g.blocked,true) vec(g.muzzle.pos,Vector(4.6,-1,60))
    trace=function(t) return {Hit=true,StartSolid=true,HitPos=t.endpos,HitNormal=Vector(-1,0,0)} end
    vec(c.Weapon(ply).muzzle.pos,ply:EyePos())
end
function cases.server_validation()
    local c=core(true)
    receive(c,"weapon_other") eq(c.Weapon(ply),nil)
    receive(c,nil,{offset=Vector(2,0,0)}) eq(c.Weapon(ply),nil)
    receive(c,nil,{pitch=46}) eq(c.Weapon(ply),nil)
    receive(c,nil,{offset=Vector(0/0,0,0)}) eq(c.Weapon(ply),nil)
    receive(c) assert(c.Weapon(ply))
    c.Players[ply].lastSync=-1 eq(c.Weapon(ply),nil)
end
function cases.bullets()
    local c=core(true) receive(c) local w=ply:GetActiveWeapon()
    local spread=Vector(.1,.2,.3) local b=S.Bullet{Spread=spread,Num=7}
    local count=0 b.Callback=function() count=count+1 return {damage=false} end
    eq(hook.Run("EntityFireBullets",ply,b),true) vec(b.Src,Vector(20,-6,48)) vec(b.Dir,Vector(1,0,0)) eq(b.Spread,spread) eq(b.Num,7) eq(b.Tracer,0)
    for i=1,7 do eq(b.Callback(ply,{HitPos=Vector(200,-6,48)},{}).damage,false) end eq(count,7)
    assert(c.sent[65]) eq(c.Players[ply].weapon.lastShot.number,1)
    local foreign=entity("player") local bullet=S.Bullet() eq(hook.Run("EntityFireBullets",foreign,bullet),nil) eq(bullet.Tracer,1)
end
function cases.server_twohand()
    local c=core(true) arm(c,"weapon_smg1")
    c.Players[ply].hands.left.buttons=1 c.Players[ply].interact.left.phys.pos=Vector(21.2,-5,47)
    receive(c,nil,{two=true}) local g=c.Weapon(ply) eq(g.twoHanded,true)
    vec(g.muzzle.ang:Forward(),(Vector(21.2,-5,47)-g.pose.pos):GetNormalized())
    c.Players[ply].interact.left.phys.pos=Vector(80,0,48) eq(c.Weapon(ply).twoHanded,false)
end
function cases.projectiles()
    local c=core(true)
    for class,weaponClass in pairs({rpg_missile="weapon_rpg",crossbow_bolt="weapon_crossbow",grenade_ar2="weapon_smg1",prop_combine_ball="weapon_ar2"}) do
        arm(c,weaponClass) local ent=entity(class,Vector(-20,2,64),ply) ent.velocity=Vector(0,130,0)
        hook.Run("OnEntityCreated",ent) advance(c,1/66) hook.Run("Tick")
        vec(ent.pos,c.Weapon(ply).muzzle.pos) vec(ent.velocity,Vector(130,0,0)) near(ent.velocity:Length(),130)
    end
end
function cases.delayed_projectile_owner()
    local c=core(true) arm(c,"weapon_rpg") local ent=entity("rpg_missile")
    hook.Run("OnEntityCreated",ent) advance(c,1/66) hook.Run("Tick") vec(ent.pos,Vector())
    ent.owner=ply advance(c,1/66) hook.Run("Tick") vec(ent.pos,c.Weapon(ply).muzzle.pos)
end
function cases.hands_server()
    local c=core(true) local state=c.Players[ply]
    c.Emit("OnStart",ply,state) assert(ply:HasWeapon("nlvr_hands")) eq(ply:GetActiveWeapon():GetClass(),"weapon_pistol")
    arm(c,"weapon_smg1") c.Emit("OnStop",ply,state) eq(ply:HasWeapon("nlvr_hands"),false) eq(ply:GetActiveWeapon():GetClass(),"weapon_smg1")
    eq(registered.nlvr_hands.WorldModel,"") eq(registered.nlvr_hands.AutoSwitchTo,false)
    registered.nlvr_hands.PrimaryAttack() registered.nlvr_hands.SecondaryAttack()
end
function cases.hands_unarmed()
    ply.active=nil local c=core(true) c.Emit("OnStart",ply,c.Players[ply]) eq(ply:GetActiveWeapon():GetClass(),"nlvr_hands")
    ply:StripWeapon("nlvr_hands") c.Emit("OnSpawn",ply,c.Players[ply]) hook.Run("Tick") assert(ply:HasWeapon("nlvr_hands"))
    c.registry:Stop() eq(ply:HasWeapon("nlvr_hands"),false) eq(c.Weapon,nil)
end
function cases.throw()
    local c=core(true) arm(c,"weapon_frag") local state=c.Players[ply]
    state.history.right={{time=clock-.1,pose=pose()},{time=clock-.02,pose=pose()}}
    state.history.right[1].pose.vel=Vector(80,0,10) state.history.right[2].pose.vel=Vector(100,0,10)
    state.hands.right.buttons=2 c.Emit("OnSync",ply,state) state.hands.right.buttons=0 c.Emit("OnSync",ply,state)
    local expected=include("nlvr/modules/sv_interact_math.lua").Throw(state.history.right,clock,40)
    local grenade=entity("npc_grenade_frag",Vector(),ply) grenade.phys=physical() grenade.phys.velocity=Vector(120,0,0)
    hook.Run("OnEntityCreated",grenade) advance(c,.1) hook.Run("Tick")
    vec(grenade.phys.velocity,expected) vec(grenade.pos,state.interact.right.phys.pos)
    eq(hook.Run("ShouldCollide",grenade,state.interact.right.proxy),false)
    assert(grenade.phys.instant) eq(#pairsMade,2)
    local action=include("nlvr/modules/sv_interact_actions.lua").New(c,function() end)
    action.physics={proxies={},held={},released=c.releasedProjectiles}
    state.interact.controls={}
    action.Hit(ply,state,state.interact.right,grenade,grenade.pos,Vector(80,0,0),80)
    eq(grenade.health,100) eq(grenade.phys.force,nil)
    advance(c,.21) hook.Run("Tick") eq(grenade.custom,false) eq(hook.Run("ShouldCollide",grenade,state.interact.right.proxy),nil)
    for _,pair in ipairs(pairsMade) do eq(pair.valid,false) end
    assert(c.releasedProjectiles[grenade],"W did not register its release with P")
    eq(state.interact.right.hitAt,nil)
end
function cases.q4r_grenade_feedback()
    local c=core(true) arm(c,"weapon_frag")
    c.Grab=function() error("grenade must not borrow an owned hand grab") end
    c.Release=function() error("grenade must not fake releasing a held prop") end
    c.Holding=function() return nil end
    local s=c.Players[ply]
    s.history.right={{time=clock-.1,pose=pose()},{time=clock-.02,pose=pose()}}
    s.hands.right.buttons=2 c.Emit("OnSync",ply,s) s.hands.right.buttons=0 c.Emit("OnSync",ply,s)
    local e=entity("npc_grenade_frag",Vector(),ply) e.phys=physical() e.phys.velocity=Vector(120,0,0)
    hook.Run("OnEntityCreated",e) advance(c,.1) hook.Run("Tick")
    eq(c.feedback.right,1) assert(c.releasedProjectiles[e])
end
function cases.melee()
    local c=core(true) local w=arm(c,"weapon_crowbar") local state=c.Players[ply]
    local target=entity("prop_physics")
    trace=function(t) if t.mins then return {Hit=true,HitPos=t.endpos,HitNormal=Vector(-1,0,0),Entity=target} end return {Hit=false,HitPos=t.endpos} end
    hook.Run("Tick") advance(c,.02) state.interact.right.phys.pos=state.interact.right.phys.pos+Vector(.1,0,0) hook.Run("Tick") eq(target.health,100)
    advance(c,.02) state.hands.right.vel=Vector(150,0,0) state.interact.right.phys.pos=state.interact.right.phys.pos+Vector(3,0,0) hook.Run("Tick")
    assert(target.health<100) eq(target.damage.DamageType,DMG_CLUB) eq(target.damage.Inflictor,w) assert(w.sound)
    local old=target.health advance(c,.02) state.interact.right.phys.pos=state.interact.right.phys.pos+Vector(3,0,0) hook.Run("Tick") eq(target.health,old)
    local actual=100-old local expected=include("nlvr/modules/sv_interact_math.lua").Damage(150,40) near(actual,expected)
end
function cases.melee_trigger()
    local c=core() arm(c,"weapon_stunstick") c.Input.main.trigger=true local cmd=S.Command() c.move(cmd) eq(cmd:KeyDown(IN_ATTACK),false)
    c.Settings.melee=0 c.move(cmd) eq(cmd:KeyDown(IN_ATTACK),true)
end
function cases.punch_suppression()
    local c=core(true) receive(c)
    eq(c.owners.right,"weapons") eq(c.owners.left,nil)
    -- P's q4_hand_ownership exercises actual contact suppression; W has no damage veto.
    eq(hook.GetTable().EntityTakeDamage,nil)
end
function cases.events_effects()
    local c=core() c.frame() local changes,fires=0,0
    local entry=c.registry.entries[1]
    c._On(entry,"weapon_changed",function(a) changes=changes+1 end)
    c._On(entry,"weapon_fired",function(a) fires=fires+1 eq(a,c.Weapon.Active) end)
    arm(c,"weapon_smg1") eq(changes,1)
    local wire=S.Wire() wire.WriteString("weapon_smg1") wire.WriteVector(Vector(20,-6,48))
    wire.WriteFloat(1) wire.WriteFloat(0) wire.WriteFloat(0) wire.WriteVector(Vector(200,-6,48)) wire.WriteBool(true) wire.WriteBool(true)
    wire.Rewind() net=wire c.handlers[65]() eq(fires,1) eq(#effects,2) vec(effects[1].data.Start,Vector(20,-6,48))
    assert(next(lights)) c.frame() assert(c.Debug.weapons.kick>0)
end
function cases.no_punch()
    local c=core() c.frame() ply.punch=Angle(30,40,15) c.move(S.Command())
    vec(c.Pose.head.ang:Forward(),Angle(0,45,0):Forward()) vec(c.aim:Forward(),(c.Debug.weapons.aim_point-ply:EyePos()):GetNormalized())
end
function cases.no_weapon_library()
    weapons=nil
    local c=core() eq(c.Weapon,nil) c.registry:Stop()
    local server=core(true) eq(server.Weapon,nil) server.registry:Stop()
    for _,entries in pairs(hooks) do assert(next(entries)==nil) end
end
function cases.barrel_calibration()
    modelFixtures["tilted.mdl"]={bones={{name="ValveBiped.Bip01_R_Hand",pos=Vector(1,2,3),ang=Angle(2,13,0)}},
        attachments={{name="muzzle",pos=Vector(-17,2,3),ang=Angle(0,180,180)}}}
    local c=core() ply.active=weapon("weapon_ar2","tilted.mdl") c.frame()
    local a=c.Weapon.Active
    local attachment=a.model:GetAttachment(1)
    vec(attachment.Ang:Forward(),a.aimAng:Forward()) vec(attachment.Pos,(c.Weapon.Muzzle()))
    local before=a.aimAng:Forward()
    for i=1,100 do c.frame() c.move(S.Command()) end
    vec(c.Weapon.Active.aimAng:Forward(),before)
    local m=a.model:GetBoneMatrix(0)
    vec(m:GetTranslation(),c.Hand.right.shown.pos) vec(a.model:GetAngles():Up(),Vector(0,0,1))
end
function cases.armed_touch_ownership()
    local c=core(true) local s=c.Players[ply] s.interact.right.useAt=.7 s.interact.left.useAt=.8
    receive(c) eq(c.owners.right,"weapons") eq(s.interact.left.useAt,.8)
    advance(c,.1) hook.Run("Tick") eq(s.interact.right.useAt,.7)
    arm(c,"nlvr_hands") eq(c.owners.right,nil) eq(s.interact.right.useAt,.7)
    arm(c,"weapon_pistol") c.registry:Stop() eq(c.owners.right,nil) eq(s.interact.right.useAt,.7)
end
function cases.crossbow_rail()
    modelFixtures["rail.mdl"]={bones={{name="ValveBiped.Bip01_R_Hand",pos=Vector()}},
        attachments={{name="muzzle",pos=Vector(20,0,0),ang=Angle(-90,0,0)}}}
    local c=core() ply.active=weapon("weapon_crossbow","rail.mdl") c.frame()
    local a=c.Weapon.Active
    vec(a.model:GetAngles():Forward(),Vector(1,0,0)) vec(a.aimAng:Forward(),Vector(1,0,0))
    vec(c.Weapon.Muzzle(),c.Hand.right.shown.pos+Vector(20,0,0))
    arm(c,"weapon_crowbar") eq(c.Weapon.Active.geometry.fore,nil)
end
function cases.tool_screen_lifetime()
    local c=core() local w=weapon("gmod_tool") local count=0
    local original=function() count=count+1 end w.RenderScreen=original ply.active=w c.frame()
    w.RenderScreen() eq(count,0)
    arm(c,"weapon_pistol") eq(w.RenderScreen,original) w.RenderScreen() eq(count,1)
    ply.active=w c.frame() local foreign=function() end w.RenderScreen=foreign
    c.registry:Stop() eq(w.RenderScreen,foreign)
end
function cases.geometry_ack()
    local c=core() c.noAck=true c.frame() c.Input.main.trigger=true
    local command=S.Command() c.move(command) eq(command:KeyDown(IN_ATTACK),false)
    local first=c.sent[64]
    advance(nil,.11) c.move(command) assert(c.sent[64]~=first)
    local ack=S.Wire() ack.WriteString("wrong_class") ack.WriteUInt(1,16) ack.Rewind() net=ack c.handlers[66]()
    c.move(command) eq(command:KeyDown(IN_ATTACK),false)
    c.noAck=false advance(nil,.11) c.move(command) eq(command:KeyDown(IN_ATTACK),true)
end
function cases.relocating_filter()
    local c=core(true) arm(c,"weapon_crossbow") local bolt=entity("crossbow_bolt",Vector(16,-6,48),ply)
    trace=function(t)
        if t.filter(bolt) then return {StartSolid=true,Hit=true,HitPos=t.start,HitNormal=Vector(0,0,1)} end
        return {Hit=false,HitPos=t.endpos}
    end
    hook.Run("OnEntityCreated",bolt) advance(c,.015) hook.Run("Tick")
    vec(bolt.pos,Vector(20,-6,48))
end
function cases.owned_turret_unchanged()
    local c=core(true) receive(c)
    local turret=entity("prop_turret",Vector(),ply) local b=S.Bullet{Dir=Vector(0,1,0)}
    eq(hook.Run("EntityFireBullets",turret,b),nil) vec(b.Dir,Vector(0,1,0)) eq(b.Tracer,1)
end
function cases.custom_empty()
    local c=core() local e=ply:GetActiveWeapon() e.scripted=true
    e.DrawWorldModel=function() end c.frame()
    local model=c.Weapon.Active.model local raw=rawget(model:GetTable(),"DrawModel")
    hook.Run("PreDrawTranslucentRenderables",false,false)
    eq(model.draws,1) eq(c.Weapon.Active.customFailed,true) eq(rawget(model:GetTable(),"DrawModel"),raw)
end
function cases.camera_visibility()
    local value="0xaaa, 0xbbb" local writes=0
    RemixConfig={GetConfigVariable=function() return value end,SetConfigVariable=function(_,v) value=v writes=writes+1 end}
    local c=core() ply.active=weapon("gmod_camera","models/maxofs2d/camera.mdl") c.frame()
    eq(value,"0xaaa, 0xbbb, -0x35d7392325ed05a9")
    arm(c,"weapon_pistol") eq(value,"0xaaa, 0xbbb")
    ply.active=weapon("gmod_camera","models/maxofs2d/camera.mdl") c.frame()
    value=value..", 0xccc"
    arm(c,"weapon_pistol") eq(value,"0xaaa, 0xbbb, 0xccc")
    value="-0x35D7392325ED05A9, 0xddd" local before=writes
    ply.active=weapon("gmod_camera","models/maxofs2d/camera.mdl") c.frame() c.registry:Stop()
    eq(value,"-0x35D7392325ED05A9, 0xddd") eq(writes,before)
end
function cases.camera_module_failure()
    local value="0xaaa"
    RemixConfig={GetConfigVariable=function() return value end,SetConfigVariable=function(_,v) value=v end}
    local c=core() ply.active=weapon("gmod_camera","models/maxofs2d/camera.mdl") c.frame()
    local model=c.Weapon.Active.model
    c.registry:Call(c.registry.entries[1],function() error("Q camera module crash") end)
    eq(value,"0xaaa") eq(IsValid(model),false)
    c.registry:Stop() eq(value,"0xaaa")
    eq(#errors,1) assert(errors[1]:find("Q camera module crash",1,true)) errors[1]=nil
end
function cases.q4_rendered_muzzle()
    local M=include("nlvr/modules/cl_weapons_model.lua")
    for _,side in ipairs({"left","right"}) do
        modelFixtures["q4_muzzle.mdl"]={bones={{name="ValveBiped.Bip01_R_Hand",pos=Vector(1,2,3),ang=Angle(2,178,177)}},
            attachments={{name="muzzle",pos=Vector(-28,3,8),ang=Angle(0,180,0)}}}
        local m=ClientsideModel("q4_muzzle.mdl",0)
        local f={pos=Vector(1,0,0),ang=Angle(),grip=Vector(2,-1,.5),calibrated=true}
        local g=M.Measure(m,"weapon_physgun",f,side)
        local a={model=m,geometry=g}
        local p,r=Vector(22,35,50),Angle(-45,25,0)
        M.Pose(a,p,r,40,0)
        vec(m:GetAttachment(m:LookupAttachment("muzzle")).Pos,LocalToWorld(g.muzzle*40,Angle(),p,r),.4)
        m:Remove()
    end
end
function cases.q4_physgun_attachment()
    local path="models/weapons/w_physics.mdl"
    modelFixtures[path]={bones={{name="ValveBiped.Bip01_R_Hand",pos=Vector()}},
        attachments={{name="core",pos=Vector(22,1,1),ang=Angle()}}}
    local M=include("nlvr/modules/cl_weapons_model.lua")
    local m=ClientsideModel(path,0)
    local g=M.Measure(m,"weapon_physgun")
    local a={model=m,geometry=g}
    M.Pose(a,Vector(20,10,40),Angle(-45,20,0),40,0)
    vec(m:GetAttachment(1).Pos,LocalToWorld(g.muzzle*40,Angle(),Vector(20,10,40),Angle(-45,20,0)),.4)
end
function cases.q4r_muzzle_world_model()
    local M=include("nlvr/modules/cl_weapons_model.lua")
    local path="models/reskinned_physgun.mdl"
    modelFixtures[path]={bones={{name="ValveBiped.Bip01_R_Hand",pos=Vector()}},
        attachments={{name="unrelated",pos=Vector(2,10,0),ang=Angle()}}}
    local m=ClientsideModel(path,0)
    local g=M.Measure(m,"weapon_physgun")
    assert(not g.attachment or g.attachment<=0,"class selected unrelated model attachment")
end
local function ownershipDeath(tickDeath)
    for _,left in ipairs({false,true}) do
        ply.alive=true
        local c=core(true) receive(c,nil,{left=left})
        local hand=left and "left" or "right"
        eq(c.owners[hand],"weapons")
        if tickDeath then ply.alive=false hook.Run("Tick") else c.Emit("OnDeath",ply,c.Players[ply]) end
        assert(c.owners[hand]==nil,tickDeath and "dead tick retained ownership" or "death retained ownership")
        c.registry:Stop()
    end
end
function cases.q4r_ownership_death() ownershipDeath(false) end
function cases.q4r_ownership_dead_tick() ownershipDeath(true) end
function cases.q4_stock_grips()
    local data=assert(loadfile(profileFixture))()
    local M=include("nlvr/modules/cl_weapons_model.lua")
    local Witness=assert(loadfile(root.."/companion/tests/vr_mesh_witness.lua"))()
    local class={w_crowbar="weapon_crowbar",w_stunbaton="weapon_stunstick",w_physics="weapon_physgun",w_rocket_launcher="weapon_rpg",w_irifle="weapon_ar2",w_grenade="weapon_frag",w_bugbait="weapon_bugbait",w_toolgun="gmod_tool",camera="gmod_camera",w_medkit="weapon_medkit"}
    local function parse(v) local n={} for p in v:gmatch("[-%d%.eE]+") do n[#n+1]=tonumber(p) end return n end
    util.GetModelMeshes=function(path)
        local triangles={} for _,v in ipairs(data.models[path].vertices) do triangles[#triangles+1]={pos=Vector(unpack(v))} end
        return {{triangles=triangles}},{}
    end
    for path,row in pairs(data.models) do if scenario~="q4_real_melee" or row.spec.kind=="shaft" then for _,side in ipairs({"left","right"}) do
        local name=path:match("([^/]+)%.mdl$") local cls=class[name] or "weapon_"..name:gsub("^w_","")
        modelFixtures[path]={bones={{name="ValveBiped.Bip01_R_Hand",pos=Vector(unpack(parse(row.bone_pose.pos))),ang=Angle(unpack(parse(row.bone_pose.ang)))}}}
        if next(row.attachments) then
            local attachments={}
            local fallback=0
            for name,record in pairs(row.attachments) do
                local p=record.pose
                fallback=fallback+1
                attachments[record.id or fallback]={name=name,pos=Vector(unpack(parse(p.Pos))),ang=Angle(unpack(parse(p.Ang)))}
            end
            modelFixtures[path].attachments=attachments
        end
        local m=ClientsideModel(path,0)
        function m:GetModelBounds() return Vector(unpack(row.bounds[1])),Vector(unpack(row.bounds[2])) end
        local source=data.hands[side]
        assert(not source.frame.grip and not row.spec.grip_roi,"witness imported a product grip target/box")
        local frame={pos=Vector(unpack(source.frame.pos)),ang=Angle(unpack(source.frame.ang)),calibrated=true}
        frame.grip=Witness.Circle(Vector(unpack(source.bones.Finger2)),Vector(unpack(source.bones.Finger21)),Vector(unpack(source.bones.Finger22)))
        local a={model=m,geometry=M.Measure(m,cls,frame,side)}
        print(string.format("AXIS %s %s %s %.8f %.8f %.8f",cls,side,a.geometry.barrelSource or "unknown",a.geometry.barrel.x,a.geometry.barrel.y,a.geometry.barrel.z))
        local pos,ang=Vector(20,12,40),Angle(25,35,0)
        M.Pose(a,pos,ang,40,0)
        local inverse,inverseAng=WorldToLocal(Vector(),Angle(),frame.pos,frame.ang)
        local wrist,wristAng=LocalToWorld(inverse,inverseAng,pos,ang)
        local hand={bones={}}
        for suffix,p in pairs(source.bones) do hand.bones[suffix]={pos=LocalToWorld(Vector(unpack(p)),Angle(),wrist,wristAng)} end
        local snapshot=Witness.Snapshot(m)
        local actual=Witness.Grip(snapshot,hand,row.spec) local grasp=Witness.Expected(hand,row.spec)
        assert(actual and (actual-grasp):Length()<.2,path.." "..side.." misses independently fitted mesh grip (5 mm)")
        local valid,boneError=Witness.BoneEnvelope(snapshot,hand,row.spec)
        if row.spec.kind~="shaft" then assert(valid,path.." "..side.." misses independent bone/handle envelope") end
        assert((a.grip-Witness.Grasp(hand)):Length()<.2,"measured handle placement misses drawn fingers")
        print(string.format("HOLD %s %s grasp_mm=%.5f bone_mm=%.5f",name,side,(actual-grasp):Length()*25,(boneError or (snapshot.bone and (Witness.World(snapshot,snapshot.bone)-hand.bones.Hand.pos):Length()/snapshot.scale) or 0)*25))
        local axis=row.spec.barrel_fit and row.spec.barrel_fit.axis or row.spec.gun_axis
        if axis then
            local direction=Witness.Barrel(snapshot,row.spec)
            assert(direction,"native witness barrel absent")
            local forward=math.deg(math.acos(math.Clamp(direction:Dot(ang:Forward()),-1,1)))
            local up=math.deg(math.acos(math.Clamp(m:GetAngles():Up():Dot(ang:Up()),-1,1)))
            assert(forward<.1 and up<2,path.." actual barrel/up orientation")
        end
        if row.spec.barrel_caps then
            local axis=Witness.Barrel(snapshot,row.spec)
            local error=axis and math.deg(math.acos(math.Clamp(axis:Dot(ang:Forward()),-1,1)))
            print("SMG_AXIS "..side.." error_degrees="..tostring(error))
            assert(error and error<.1,"real SMG mesh barrel skew exceeds 0.1 degrees")
        end
        if path=="models/weapons/w_physics.mdl" then
            local nativeEmitter=m:GetAttachment(m:LookupAttachment("core"))
            local exposed=LocalToWorld(a.geometry.muzzle*40,Angle(),pos,ang)
            assert((nativeEmitter.Pos-exposed):Length()<.4,"muzzle differs from add-on beam draw; independent model core")
        end
        local mounted=m:GetBoneMatrix(0):GetTranslation()
        if row.spec.kind=="shaft" then assert((mounted-hand.bones.Hand.pos):Length()<4.8,path.." "..side.." exceeds 12 cm wrist envelope") end
        if row.spec.kind=="shaft" then
            local strike=Witness.StrikeAxis(snapshot,row.spec)
            local realEnd=Witness.End(snapshot,strike)
            local tip=assert(a.geometry.meleeTip,"real melee extent missing")
            local serverEnd=LocalToWorld(tip*40,Angle(),pos,ang)
            assert((serverEnd-realEnd):Length()<1.2,"server tip differs from real drawn end over 3 cm")
            if scenario=="q4_real_melee" then
                local c=core(true) arm(c,cls) local state=c.Players[ply]
                local pose=state.hands[side] pose.pos,pose.ang=pos,ang
                state.interact[side].phys.pos=pos
                receive(c,cls,{left=side=="left",offset=a.geometry.muzzle,meleeTip=tip})
                hook.Run("Tick")
                local travel=ang:Forward()*12
                M.Pose(a,pos+travel,ang,40,0)
                local drawn=Witness.Snapshot(m) local endPoint=Witness.End(drawn,Witness.StrikeAxis(drawn,row.spec))
                local target=entity("npc_citizen",endPoint)
                trace=function(t)
                    if t.mins and (t.endpos-endPoint):Length()<1.2 then return {Hit=true,Entity=target,HitPos=endPoint,HitNormal=-ang:Forward()} end
                    return {Hit=false,HitPos=t.endpos}
                end
                advance(c,.04) pose.pos=pos+travel pose.vel=travel/.04
                state.interact[side].phys.pos=pos+travel
                hook.Run("Tick")
                local actual=state.weapon.tip and state.weapon.tip.pos
                assert(actual and (actual-endPoint):Length()<1.2,"server sweep endpoint misses real hook by over 3 cm")
                assert(target.health<100,"hook-only swing did no damage")
                print(string.format("MELEE_GEO %s %s end_error_m=%.7f forward_m=%.5f damage=%.2f",cls,side,(actual-endPoint):Length()/40,(endPoint-(pos+travel)):Dot(ang:Forward())/40,100-target.health))
                trace=nil c.registry:Stop()
            end
        end
        m:Remove()
    end end end
end
function cases.q4_real_melee() cases.q4_stock_grips() end
function cases.camera_two_writers()
    local M=include("nlvr/modules/cl_weapons_model.lua")
    local value="0xaaa"
    RemixConfig={GetConfigVariable=function() return value end,SetConfigVariable=function(_,v) value=v end}
    local a={class="gmod_camera",path="models/maxofs2d/camera.mdl"}
    M.Prepare(a)
    value=value..", 0xccc" -- another writer appends while our camera token is leased
    M.Restore(a) eq(value,"0xaaa, 0xccc")
    value="0xaaa" M.Prepare(a)
    value="-0x35d7392325ed05a9, 0xccc"
    M.Restore(a) eq(value,"0xccc")
    value="0xaaa" M.Prepare(a) value=value..", -0x35d7392325ed05a9"
    M.Restore(a) eq(value,"0xaaa, -0x35d7392325ed05a9","removed another writer's duplicate token")
    value="0xaaa" M.Prepare(a) M.Restore(a) eq(value,"0xaaa")
    value=" -0x35d7392325ed05a9, 0xccc" M.Prepare(a) M.Restore(a)
    eq(value," -0x35d7392325ed05a9, 0xccc") -- pre-existing token belongs to another writer
    value="0xccc" M.Prepare(a) M.Restore(a) eq(value,"0xccc")
end
function cases.camera_screen_cleanup()
    local M=include("nlvr/modules/cl_weapons_model.lua")
    local value="0xaaa"
    RemixConfig={GetConfigVariable=function() return value end,SetConfigVariable=function(_,v) value=v end}
    local a={class="gmod_camera",path="models/maxofs2d/camera.mdl",ent=weapon("gmod_tool")}
    M.Prepare(a)
    -- Cleanup is composable even if an older/debug caller retained a resource lease.
    a.cameraOverride.refs=2
    local original,replacement=function() end,function() end
    a.screen={raw=original,replacement=replacement} a.ent.RenderScreen=replacement
    M.Restore(a) eq(a.ent.RenderScreen,original)
end
-- Review regressions deliberately drive the real module, rather than duplicating its maths.
local function meleeFixture()
    local c=core(true) arm(c,"weapon_crowbar") local s=c.Players[ply]
    local target=entity("npc_citizen")
    trace=function(t)
        if t.mins then return {Hit=true,HitPos=t.endpos,HitNormal=Vector(-1,0,0),Entity=target,SurfaceProps=7,HitBox=9,HitBoxBone=2} end
        return {Hit=false,HitPos=t.endpos}
    end
    hook.Run("Tick") return c,s,target
end
for name,delta in pairs({melee_walk=1.3,melee_sprint=4.8,melee_tip_jump=12}) do
    cases[name]=function()
        local c,s,target=meleeFixture()
        advance(c,.02) s.interact.right.phys.pos=s.interact.right.phys.pos+Vector(delta,0,0)
        hook.Run("Tick") eq(target.health,100)
    end
end
function cases.melee_snap()
    local c,s,target=meleeFixture()
    advance(c,.015) s.hands.right.ang=Angle(0,30,0) hook.Run("Tick") eq(target.health,100)
end
function cases.melee_teleport()
    local c,s,target=meleeFixture()
    advance(c,.015) s.interact.right.proxy=entity("new_hand") s.interact.right.phys=physical(Vector(60,-6,48))
    s.hands.right.vel=Vector(100,0,0) -- an old tracking velocity must not sweep the teleport path
    hook.Run("Tick") eq(target.health,100)
end
function cases.melee_tracked_velocity()
    local c,s,target=meleeFixture()
    advance(c,.02) s.hands.right.vel=Vector(80,0,0)
    -- Physics trails tracking; an actual outside sweep is still required.
    s.interact.right.phys.pos=s.interact.right.phys.pos+Vector(1,0,0)
    hook.Run("Tick") assert(target.health<100) near(target.damage.Damage,11)
end
function cases.melee_angular_velocity()
    local c,s,target=meleeFixture()
    advance(c,.02) s.hands.right.angvel=Vector(0,0,4)
    s.hands.right.ang=Angle(0,math.deg(.08),0)
    hook.Run("Tick") assert(target.health<100)
    near(target.damage.Damage,include("nlvr/modules/sv_interact_math.lua").Damage(4*.56*40,40))
end
function cases.melee_impact_fields()
    local c,s,target=meleeFixture()
    local previous=s.weapon.tip.pos
    advance(c,.02) s.hands.right.vel=Vector(150,0,0) s.interact.right.phys.pos=s.interact.right.phys.pos+Vector(3,0,0)
    hook.Run("Tick") assert(target.health<100)
    local effect=effects[#effects] eq(effect.name,"Impact")
    vec(effect.data.Start,previous) eq(effect.data.Entity,target) eq(effect.data.SurfaceProp,7)
    eq(effect.data.HitBox,2) eq(effect.data.DamageType,DMG_CLUB)
end
function cases.bullet_followup()
    local c=core(true) arm(c,"weapon_review_swep")
    local first=S.Bullet() hook.Run("EntityFireBullets",ply,first) vec(first.Src,c.Weapon(ply).muzzle.pos)
    local exit,dir=Vector(200,35,48),Vector(0,1,0)
    local callback=function() return "penetration" end
    local second=S.Bullet{Src=exit,Dir=dir,Callback=callback}
    eq(hook.Run("EntityFireBullets",ply,second),nil)
    vec(second.Src,exit) vec(second.Dir,dir) eq(second.Callback,callback) eq(second.Tracer,1)
end
function cases.bullet_missing_geometry()
    local c=core(true) receive(c) c.Players[ply].weapon=nil
    local b=S.Bullet{Src=Vector(200,35,48),Dir=Vector(0,1,0)}
    eq(hook.Run("EntityFireBullets",ply,b),nil) vec(b.Src,Vector(200,35,48)) vec(b.Dir,Vector(0,1,0))
    eq(hook.Run("EntityFireBullets",ply,S.Bullet()),false) -- only an unsafe initial VR shot is vetoed
end
function cases.grenade_spin_frame()
    local c=core(true) arm(c,"weapon_frag") local s=c.Players[ply]
    s.hands.right.ang=Angle(20,75,30)
    s.history.right={{time=clock-.01,pose=pose()}}
    local sample=s.history.right[1].pose sample.vel=Vector(80,0,0) sample.angvel=Vector(.7,1.1,2.2)
    local ent=entity("npc_grenade_frag",Vector(),ply) ent.phys=physical() ent.phys.velocity=Vector(100,0,0)
    hook.Run("OnEntityCreated",ent) hook.Run("Tick")
    local worldSpin=LocalToWorld(ent.phys:GetAngleVelocity()*(math.pi/180),Angle(),Vector(),ent.phys:GetAngles())
    vec(worldSpin,sample.angvel)
end
function cases.projectile_same_tick()
    local c=core(true) arm(c,"weapon_crossbow") local ent=entity("crossbow_bolt",ply:EyePos())
    hook.Run("OnEntityCreated",ent) ent.owner=ply ent.velocity=Vector(0,3500,0)
    hook.Run("PlayerPostThink",ply)
    vec(ent.pos,c.Weapon(ply).muzzle.pos) eq(c.Players[ply].weapon.lastProjectile.ticks,0)
    eq(ent:IsEffectActive(EF_NOINTERP),true)
    -- Native collision would hit this eye-line obstacle before the following Tick.
    local eyeObstacle=Vector(0,20,64)
    assert(math.abs(ent.pos.y-eyeObstacle.y)>10)
end
function cases.foregrip_burst()
    local c=core() arm(c,"weapon_smg1") c.Input.main.trigger=true c.move(S.Command())
    local initial=c.sent[64] c.noAck=true
    local g=c.Weapon.Active.geometry
    c.Hand.left.target.pos=LocalToWorld(g.fore*40,Angle(),c.Hand.right.shown.pos,Angle())
    for _,grip in ipairs({true,false,true,false}) do
        c.Input.off.grip=grip advance(nil,.02) c.frame() local cmd=S.Command() c.move(cmd)
        eq(cmd:KeyDown(IN_ATTACK),true) eq(c.sent[64],initial)
    end
end
function cases.pitch_keeps_firing()
    local c=core() c.frame() c.Input.main.trigger=true c.move(S.Command()) c.noAck=true
    c.Settings.gun_angle=20 local cmd=S.Command() c.move(cmd) eq(cmd:KeyDown(IN_ATTACK),true)
end
function cases.exit_keeps_active()
    local c=core(true) local s=c.Players[ply] c.Emit("OnStart",ply,s)
    arm(c,"weapon_smg1") c.Emit("OnStop",ply,s) eq(ply:GetActiveWeapon():GetClass(),"weapon_smg1")
end
function cases.exit_hands_fallback()
    local c=core(true) local s=c.Players[ply] c.Emit("OnStart",ply,s)
    local best=arm(c,"weapon_smg1") function best:GetWeight() return 20 end
    ply:StripWeapon("weapon_pistol") ply:SelectWeapon("nlvr_hands")
    c.Emit("OnStop",ply,s) eq(ply:GetActiveWeapon(),best)
end
function cases.exit_unarmed_fallback()
    ply.active=nil local c=core(true) local s=c.Players[ply] c.Emit("OnStart",ply,s)
    c.Emit("OnStop",ply,s) eq(ply:GetActiveWeapon():GetClass(),"weapon_pistol")
end
for _,order in ipairs({"first","last"}) do
    cases["bullet_hooks_"..order]=function()
        local c=core(true) receive(c) local expected=c.Weapon(ply).muzzle.pos local observed
        local originalIDs={} for id in pairs(hooks.EntityFireBullets or {}) do originalIDs[#originalIDs+1]=id end
        hook.Add("EntityFireBullets","review_portal",function(_,b)
            observed=b.Src b.Src=b.Src+Vector(200,0,0) b.Dir=Vector(0,1,0) return true
        end)
        hook.order=order=="first" and originalIDs or {"review_portal"}
        if order=="first" then hook.order[#hook.order+1]="review_portal" end
        local b=S.Bullet() eq(hook.Call("EntityFireBullets",{EntityFireBullets=function() return true end},ply,b),true)
        assert(observed,"W stopped a later hook") vec(observed,expected) vec(b.Src,expected+Vector(200,0,0)) vec(b.Dir,Vector(0,1,0))
    end
end
function cases.server_tracer_broadcast()
    local c=core(true) receive(c) local b=S.Bullet() hook.Run("EntityFireBullets",ply,b)
    b.Callback(ply,{StartPos=b.Src,HitPos=Vector(200,-6,48)},{})
    local e=effects[1] assert(e,"no server tracer for other players") eq(e.name,"Tracer")
    vec(e.data.Start,b.Src) vec(e.data.Origin,Vector(200,-6,48)) eq(e.recipients,true)
    local msg=c.sent[65] msg.Rewind() msg.ReadString() msg.ReadVector()
    for i=1,3 do msg.ReadFloat() end msg.ReadVector() eq(msg.ReadBool(),false)
end
function cases.client_predicted_tracer()
    local c=core() c.frame() local b=S.Bullet() eq(hook.Run("EntityFireBullets",ply,b),true) eq(b.Tracer,0)
    local pass=S.Bullet{Src=Vector(200,0,0)} hook.Run("EntityFireBullets",ply,pass) eq(pass.Tracer,1)
    local other=S.Player() local ordinary=S.Bullet() hook.Run("EntityFireBullets",other,ordinary) eq(ordinary.Tracer,1)
end
function cases.flash_explicit_origin()
    local c=core() c.frame()
    for _,class in ipairs({"weapon_pistol","weapon_357","weapon_ar2","weapon_rpg","weapon_smg1","weapon_shotgun"}) do
        arm(c,class)
        local wire=S.Wire() wire.WriteString(class) wire.WriteVector(Vector(20,-6,48))
        wire.WriteFloat(0) wire.WriteFloat(1) wire.WriteFloat(0) wire.WriteVector(Vector(20,200,48))
        wire.WriteBool(false) wire.WriteBool(true) wire.Rewind() net=wire c.handlers[65]()
        local e=effects[#effects] eq(e.name,"MuzzleEffect") vec(e.data.Origin,Vector(20,-6,48))
        vec(e.data.Angles:Forward(),Vector(0,1,0)) assert(e.data.Scale>0)
    end
end
function cases.exit_hands_previous()
    local c=core(true) local s=c.Players[ply] c.Emit("OnStart",ply,s)
    local other=arm(c,"weapon_smg1") function other:GetWeight() return 20 end
    ply:SelectWeapon("nlvr_hands") c.Emit("OnStop",ply,s) eq(ply:GetActiveWeapon():GetClass(),"weapon_pistol")
end
function cases.bullet_dispatch_cleanup()
    local before=hook.Call local c=core(true) receive(c) local owned=hooks.EntityFireBullets
    local later={} hooks.EntityFireBullets=later
    c.registry:Stop() eq(hook.Call,before) eq(hooks.EntityFireBullets,later)
    local b=S.Bullet() eq(hook.Run("EntityFireBullets",ply,b),nil) vec(b.Src,ply:GetShootPos()) eq(b.Tracer,1)
end
function cases.bullet_dispatch_cancel()
    local before=hook.Call local c=core(true) receive(c)
    hook.Add("EntityFireBullets","review_veto",function() return false end)
    eq(hook.Run("EntityFireBullets",ply,S.Bullet()),false)
    c.registry:Stop() eq(hook.Call,before)
end
function cases.cached_engine_dispatch()
    local engineCall=hook.Call
    local gmCalls=0 local gm={EntityFireBullets=function() gmCalls=gmCalls+1 return true end}
    local c=core(true,gm) receive(c)
    local b=S.Bullet() eq(engineCall("EntityFireBullets",gm,ply,b),true)
    vec(b.Src,c.Weapon(ply).muzzle.pos) eq(gmCalls,1)
end
function cases.projectile_after_postthink()
    local c=core(true) arm(c,"weapon_crossbow") hook.Run("PlayerPostThink",ply)
    local ent=entity("crossbow_bolt",ply:EyePos()) ent.velocity=Vector()
    hook.Run("OnEntityCreated",ent) ent.owner=ply ent.velocity=Vector(0,3500,0)
    hook.Run("EntityEmitSound",{Entity=ent})
    vec(ent.pos,c.Weapon(ply).muzzle.pos) eq(c.Players[ply].weapon.lastProjectile.ticks,0)
end
function cases.grenade_native_initializer()
    local c=core(true) arm(c,"weapon_frag") local s=c.Players[ply]
    local sample=pose() sample.vel=Vector(80,0,0)
    s.history.right={{time=clock-.01,pose=sample}}
    local ent=entity("npc_grenade_frag",ply:EyePos(),ply) ent.phys=physical(ply:EyePos()) ent.phys.velocity=Vector()
    hook.Run("OnEntityCreated",ent) hook.Run("EntityEmitSound",{Entity=ent})
    vec(ent.pos,s.interact.right.phys.pos) eq(ent.phys:IsMotionEnabled(),false)
    ent.phys.velocity=Vector(900,0,0) -- native initialization continues after its spawn sound
    advance(c,1/66) hook.Run("Tick")
    eq(ent.phys:IsMotionEnabled(),true) vec(ent.phys.velocity,Vector(80,0,0)) vec(ent.pos,s.interact.right.phys.pos)
    eq(s.weapon.lastProjectile.ticks,0) eq(s.weapon.lastProjectile.finalizedTicks,1)
end
function cases.model_decals_scope() cases.model_decals_untouched() end

function cases.grenade_initializing_exit()
    local c=core(true) arm(c,"weapon_frag") local s=c.Players[ply]
    local sample=pose() sample.vel=Vector(80,0,0) s.history.right={{time=clock-.01,pose=sample}}
    local ent=entity("npc_grenade_frag",ply:EyePos(),ply) ent.phys=physical() ent.phys.velocity=Vector()
    hook.Run("OnEntityCreated",ent) hook.Run("EntityEmitSound",{Entity=ent}) eq(ent.phys:IsMotionEnabled(),false)
    ent.phys.velocity=Vector(900,0,0) c.registry:Stop()
    eq(ent.phys:IsMotionEnabled(),true) vec(ent.phys.velocity,Vector(80,0,0))
end
function cases.bugbait_without_vphysics()
    local c=core(true) arm(c,"weapon_bugbait") local s=c.Players[ply]
    local sample=pose() sample.vel=Vector(80,0,0) s.history.right={{time=clock-.01,pose=sample}}
    local ent=entity("npc_grenade_bugbait",ply:EyePos(),ply)
    hook.Run("OnEntityCreated",ent) advance(c,.015) hook.Run("Tick")
    vec(ent.pos,s.interact.right.phys.pos) vec(ent.velocity,Vector(80,0,0))
end
function cases.bullet_hook_added_during_vr()
    local c=core(true) receive(c) local captured=hooks.EntityFireBullets local calls=0
    hook.Add("EntityFireBullets","new_hook",function() calls=calls+1 end)
    hook.Run("EntityFireBullets",ply,S.Bullet()) eq(calls,1)
    c.registry:Stop() hook.Run("EntityFireBullets",ply,S.Bullet()) eq(calls,2)
    assert(rawget(captured,"new_hook")) -- a retained table keeps the original/new callbacks
end
function cases.bugbait_first_visible()
    local c=core(true) arm(c,"weapon_bugbait") local s=c.Players[ply]
    local sample=pose() sample.vel=Vector(80,0,0) s.history.right={{time=clock-.01,pose=sample}}
    local ent=entity("npc_grenade_bugbait",ply:EyePos())
    hook.Run("OnEntityCreated",ent) eq(ent:GetNoDraw(),true)
    ent.owner=ply advance(c,.015) hook.Run("Tick")
    eq(ent:GetNoDraw(),false) vec(ent.pos,s.interact.right.phys.pos)
    local next=entity("npc_grenade_bugbait") hook.Run("OnEntityCreated",next)
    c.registry:Stop() eq(next:GetNoDraw(),false)
end
function cases.impact_reaches_surface()
    local c,s,target=meleeFixture()
    trace=function(t)
        if t.mins then return {Hit=true,HitPos=Vector(36.8,-6,48),HitNormal=Vector(-1,0,0),Entity=target,SurfaceProps=7,HitBoxBone=2} end
        if t.endpos.x>38 then return {Hit=true,StartPos=t.start,HitPos=Vector(38,-6,48),HitNormal=Vector(-1,0,0),Entity=target,SurfaceProps=7,HitBoxBone=2} end
        return {Hit=false,HitPos=t.endpos}
    end
    advance(c,.02) s.hands.right.vel=Vector(150,0,0) s.interact.right.phys.pos=s.interact.right.phys.pos+Vector(3,0,0)
    hook.Run("Tick") local impact=effects[#effects]
    assert(impact.data.Origin.x>38,"Impact ray must reach beyond the hull centre to the actual surface")
end
function cases.projectile_nointerp_owned()
    local c=core(true) arm(c,"weapon_crossbow") local bolt=entity("crossbow_bolt",Vector(),ply)
    bolt:AddEffects(EF_NOINTERP) hook.Run("OnEntityCreated",bolt) hook.Run("PlayerPostThink",ply)
    c.registry:Stop() eq(bolt:IsEffectActive(EF_NOINTERP),true)
end
function cases.gamemode_nil_applies()
    local gmCalls=0 local gm={EntityFireBullets=function() gmCalls=gmCalls+1 end}
    local c=core(true,gm) receive(c)
    local seen=0 hook.Add("EntityFireBullets","later",function(_,b) seen=seen+1 if library~="unknown" then vec(b.Src,c.Weapon(ply).muzzle.pos) end end)
    local b=S.Bullet() eq(hook.Call("EntityFireBullets",gm,ply,b),true)
    vec(b.Src,c.Weapon(ply).muzzle.pos) eq(b.Tracer,0) assert(b.Callback) eq(seen,1) eq(gmCalls,1)
    hook.Add("EntityFireBullets","veto",function() return false end)
    eq(hook.Call("EntityFireBullets",gm,ply,S.Bullet()),false) eq(gmCalls,1)
end
function cases.hook_library_dispatch()
    local c=core(true) receive(c) local seen=0
    hook.Add("EntityFireBullets","observer",function(_,b) seen=seen+1 if library~="unknown" then vec(b.Src,c.Weapon(ply).muzzle.pos) end end,HOOK_HIGH)
    local b=S.Bullet() hook.Run("EntityFireBullets",ply,b)
    vec(b.Src,c.Weapon(ply).muzzle.pos) eq(b.Tracer,0) eq(seen,1)
    c.Players[ply].weapon=nil eq(hook.Run("EntityFireBullets",ply,S.Bullet()),false)
end
local function movingSwing(delta)
    local c,s,target=meleeFixture()
    advance(c,.02) ply.pos=delta
    s.interact.right.phys.pos=s.interact.right.phys.pos+delta+Vector(3,0,0)
    s.hands.right.vel=Vector(150,0,0)
    hook.Run("Tick") assert(target.damage,"swing was discarded with player/platform movement")
    near(target.damage.Damage,32)
end
function cases.swing_walking() movingSwing(Vector(4,0,0)) end
function cases.swing_sprinting() movingSwing(Vector(8,0,0)) end
function cases.swing_platform() movingSwing(Vector(0,6,0)) end
function cases.still_hand_walking()
    local c,s,target=meleeFixture()
    advance(c,.02) ply.pos=Vector(4,0,0) s.interact.right.phys.pos=s.interact.right.phys.pos+ply.pos
    hook.Run("Tick") eq(target.health,100)
end
function cases.tracked_tip_jump()
    local c,s,target=meleeFixture()
    advance(c,.02) s.hands.right.vel=Vector(150,0,0)
    s.interact.right.phys.pos=s.interact.right.phys.pos+Vector(12,0,0)
    hook.Run("Tick") eq(target.health,100)
end
function cases.body_teleport_same_proxy()
    local c,s,target=meleeFixture()
    advance(c,.02) ply.pos=Vector(40,0,0) s.hands.right.vel=Vector(150,0,0)
    s.interact.right.phys.pos=s.interact.right.phys.pos+ply.pos+Vector(3,0,0)
    hook.Run("Tick") eq(target.health,100)
end
local function unavailableFore(kind)
    local c=core(true) arm(c,"weapon_smg1") local s=c.Players[ply]
    s.hands.left.buttons=1 s.interact.left.phys.pos=Vector(21.2,-5,47)
    receive(c,nil,{two=true})
    if kind=="holding_api" then c.Holding=function() return entity("held") end
    elseif kind=="grip" then s.interact.left.grip={ent=entity("held")}
    elseif kind=="climb" then s.interact.left.climb=Vector(21,-5,47)
    else s.interact.left.blocked=true end
    local g=c.Weapon(ply) eq(g.twoHanded,false) vec(g.muzzle.ang:Forward(),Vector(1,0,0))
end
function cases.foregrip_held() unavailableFore("grip") end
function cases.foregrip_climbing() unavailableFore("climb") end
function cases.foregrip_blocked() unavailableFore("blocked") end
function cases.foregrip_holding_api() unavailableFore("holding_api") end
function cases.model_decals_untouched()
    local writes=0 local cv={GetBool=function() return false end,GetString=function() return "0" end}
    GetConVar=function(name) if name=="r_drawmodeldecals" then return cv end end
    RunConsoleCommand=function() writes=writes+1 end
    local c=core() eq(writes,0) c.registry:Stop() eq(writes,0)
end
function cases.priority_observers()
    local c=core(true) receive(c) local order={}
    for n=-2,2 do
        local priority=n
        hook.Add("EntityFireBullets","priority_"..n,function(_,b)
            vec(b.Src,c.Weapon(ply).muzzle.pos) order[#order+1]=priority
        end,n)
    end
    hook.Run("EntityFireBullets",ply,S.Bullet()) eq(#order,5)
    if library=="ulib" then for i=1,5 do eq(order[i],i-3) end end
    c.registry:Stop()
    if library=="ulib" then for n=-2,2 do assert(levels.EntityFireBullets[n]["priority_"..n]) end end
end
function cases.gamemode_nil_client()
    local gmCalls=0 local gm={EntityFireBullets=function() gmCalls=gmCalls+1 end}
    local c=core(false,gm) c.frame()
    local b=S.Bullet() eq(hook.Call("EntityFireBullets",gm,ply,b),true) eq(b.Tracer,0) eq(gmCalls,1)
    local writer=function() return false end gm.EntityFireBullets=writer
    c.registry:Stop() eq(gm.EntityFireBullets,writer)
end
local function roomSwing(room,artificial)
    local c,s,target=meleeFixture()
    s.move={applied_total=Vector(),follow_epoch=0}
    hook.Run("Tick")
    advance(c,.02)
    s.move.applied_total=room ply.pos=room+artificial
    -- The controller's tracked velocity already includes the real physical lunge.
    s.hands.right.vel=Vector(250,0,0)
    s.interact.right.phys.pos=s.interact.right.phys.pos+Vector(5,0,0)+artificial
    hook.Run("Tick") assert(target.damage,"room-follow was subtracted twice") near(target.damage.Damage,62)
end
function cases.room_lunge() roomSwing(Vector(6,0,0),Vector()) end
function cases.room_walk_swing() roomSwing(Vector(3,0,0),Vector(4,0,0)) end
function cases.walk_crossing_proxy_lag()
    local c,s,target=meleeFixture()
    local face=36
    trace=function(t)
        if t.mins and t.start.x<face and t.endpos.x>=face then
            return {Hit=true,HitPos=Vector(face,-6,48),HitNormal=Vector(-1,0,0),Entity=target,SurfaceProps=7,HitBoxBone=2}
        end
        return {Hit=false,HitPos=t.endpos}
    end
    advance(c,.02) ply.pos=Vector(4,0,0)
    s.hands.right.vel=Vector(150,0,0)
    -- Physical proxy is one movement frame behind the body on this crossing tick.
    s.interact.right.phys.pos=s.interact.right.phys.pos+Vector(3,0,0)
    hook.Run("Tick") assert(target.damage,"outside crossing tick was rejected")
    assert(effects[#effects].data.Start.x<face)
end
function cases.walk_thin_door()
    local c,s,target=meleeFixture()
    local face=35
    trace=function(t)
        if t.mins and t.start.x<face and t.endpos.x>=face then
            return {Hit=true,HitPos=Vector(face,-6,48),HitNormal=Vector(-1,0,0),Entity=target,SurfaceProps=7,HitBoxBone=2}
        end
        return {Hit=false,HitPos=t.endpos}
    end
    advance(c,.02) ply.pos=Vector(4,0,0) s.hands.right.vel=Vector(150,0,0)
    s.interact.right.phys.pos=s.interact.right.phys.pos+Vector(7,0,0)
    hook.Run("Tick") assert(target.damage,"translated sweep start skipped the thin door")
    assert(effects[#effects].data.Start.x<face)
end
local function copiedDispatch(server)
    local original=hook.Call local depth=0
    hook.Call=function(event,gm,...)
        if event=="EntityFireBullets" then
            depth=depth+1 assert(depth<8,"re-entry into copied dispatcher")
            local a,b=original(event,gm,...) depth=depth-1 return a,b
        end
        return original(event,gm,...)
    end
    local c=core(server) if server then receive(c) else c.frame() end
    local copy={} for id,fn in pairs(hook.GetTable().EntityFireBullets) do copy[id]=fn end
    hook.GetTable().EntityFireBullets=copy
    local calls=0 hook.Add("EntityFireBullets","after_copy",function() calls=calls+1 end)
    hook.Run("EntityFireBullets",ply,S.Bullet()) eq(calls,1)
end
function cases.dispatch_copied_table() copiedDispatch(true) end
function cases.dispatch_copied_client() copiedDispatch(false) end
assert(cases[scenario],scenario)() checkErrors() print("PASS "..scenario)
