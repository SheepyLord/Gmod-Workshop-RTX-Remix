local root, scenario, fixturePath, baselinePath = ...
local S=assert(loadfile(root.."/companion/tests/vr_stubs.lua"))() S.Math()
bit=require("bit") math.Clamp=function(x,a,b) return math.max(a,math.min(b,x)) end
local V=getmetatable(Vector())
function V:Angle() return Angle(math.deg(math.atan2(-self.z,math.sqrt(self.x^2+self.y^2))),math.deg(math.atan2(self.y,self.x)),0) end
function V:AngleEx(up) local a=self:Angle() a.r=math.deg(math.atan2(up:Dot(a:Right()),up:Dot(a:Up()))) return a end
function include(p) return assert(loadfile(baselinePath and p=="nlvr/core/cl_hand_model.lua" and baselinePath or root.."/vr/addon/lua/"..p))() end
local function close(a,b) assert(math.abs(a-b)<.00001,tostring(a).." ~= "..tostring(b)) end
local function vec(a,b) close((a-b):Length(),0) end
local messages={} MsgN=function(s) messages[#messages+1]=s end
LocalPlayer=function() return {GetPos=function() return Vector(20,30,40) end} end
table.RemoveByValue=function() end
local C=include("nlvr/core/cl_core.lua").New({},function(e) error(e) end,40)
local fixtures={ -- SteamVR render-model component_local, as named in native tests/test_frames.cpp.
    index_left={{.006,-.015,.02},{-40,-5,0},{-.015,-.015,.13}},
    index_right={{-.006,-.015,.02},{-40,5,0},{.015,-.015,.13}},
    quest2={{-.0167,-.0252,.0247},{-37.4,0,0},{.0113,-.0018,.1019}},
    rifts={{-.0063,-.0252,.0347},{-39.4,0,0},{.0113,-.0018,.1019}},
    cv1={{-.0063,-.0252,.0347},{-39.4,0,0},{.0113,-.0018,.1019}},
    vive={{0,-.01,-.007},{1.282,0,0},{-.02,-.0285,.097}}}
local function source(t) return Vector(-t[3],-t[1],t[2]) end
local function profile(name)
    local f=fixtures[name]
    local a=Angle(-f[2][1],f[2][2],0)
    local wrist=source(f[3])
    return {valid=true,revision=1,model=name,source="recorded_components",
        aim={pos=source(f[1]),ang=a},hand={pos=wrist+a:Forward()*.06,ang=a},wrist={pos=wrist,ang=a}}
end
local function setup(data, rawAngle)
    C.Frame={controllers={left=data,right=data}}
    C.Space.yaw=33
    for _,side in ipairs({"left","right"}) do
        local raw={valid=true,pos=Vector(.4,side=="left" and .2 or -.2,1.3),ang=rawAngle,vel=Vector(),angvel=Vector()}
        local p,a=C.ToWorld(raw.pos,raw.ang)
        C.Pose[side]={valid=true,pos=p,ang=a,vel=Vector(),angvel=Vector(),raw=raw}
    end
    C.Frames.Apply()
end
if fixtures[scenario] then
    local f=profile(scenario)
    local _,natural=WorldToLocal(Vector(),Angle(),Vector(),f.aim.ang)
    setup(f,natural)
    for _,side in ipairs({"left","right"}) do
        local p,d=C.Ray(side)
        close(d.z,0) close(d:Dot(Angle(0,33,0):Forward()),1)
        local pose=C.Pose[side]
        assert(p:DistToSqr(pose.device.pos)>.01)
        vec(pose.raw.pos,Vector(.4,side=="left" and .2 or -.2,1.3))
        close(pose.ang.p,0) close(pose.ang.r,0)
    end
    assert(#messages==2)
    setup(f,natural) assert(#messages==2) -- no per-frame controller spam
elseif scenario=="raw_fallback" then
    setup({valid=false,revision=9,detail="unknown controller",source="raw"},Angle(-20,10,30))
    for _,s in ipairs({"left","right"}) do local p,d=C.Ray(s) vec(p,C.Pose[s].device.pos) vec(d,C.Pose[s].device.ang:Forward()) end
elseif scenario=="invalid_pose" then
    setup(profile("index_right"),Angle()) C.Pose.right.valid=false assert(C.Ray("right")==nil)
elseif scenario=="offset_velocity" then
    local f=profile("index_right") setup(f,Angle())
    C.Pose.right={valid=true,pos=Vector(),ang=Angle(),vel=Vector(1,0,0),angvel=Vector(0,0,2)}
    C.Frames.Apply()
    close(C.Pose.right.vel.x,1-2*f.hand.pos.y*40) close(C.Pose.right.vel.y,2*f.hand.pos.x*40)
elseif scenario=="hands_geometry" then
    local F=include("nlvr/core/cl_hand_model.lua")
    for _,side in ipairs({"left","right"}) do
        local sign=side=="right" and 1 or -1
        -- The phalanx is already flexed in sequence zero; the palm axis must ignore that flexion.
        local pos={Vector(),Vector(3,sign*1.5,0),Vector(3.3,sign*.5,0),Vector(3.2,-sign*.5,0),Vector(2.9,-sign*1.5,0),Vector(4.3,sign*1.5,-1)}
        local ent={GetBoneMatrix=function(_,id) return {GetTranslation=function() return pos[id+1] end,GetAngles=function() return Angle() end} end}
        local bones={wrist=0,fingers={{},{1},{2,5},{3},{4}}}
        local frame=assert(F.Measure(ent,bones))
        local shown={pos=Vector(20,30,40),ang=Angle()}
        local wp,wa=F.Wrist(frame,shown,40)
        vec(LocalToWorld(frame.pos,Angle(),wp,wa),shown.pos)
        local finger=LocalToWorld(Vector(1,0,0),Angle(),Vector(),wa)
        local thumb=LocalToWorld(Vector(0,sign,0),Angle(),Vector(),wa)
        local palm=LocalToWorld(Vector(0,0,-1),Angle(),Vector(),wa)
        vec(finger,Vector(1,0,0)) vec(thumb,Vector(0,0,1)) vec(palm,Vector(0,sign,0))
    end
elseif scenario=="curl_axes" then
    local P=include("nlvr/core/cl_hand_model.lua")
    for _,side in ipairs({"left","right"}) do
        local boneAngle=Angle(13,37,83)
        local bones={wrist=0,fingers={{},{1,2,3},{},{},{}}}
        local manipulated={}
        local ent={GetBoneMatrix=function(_,id) return {GetAngles=function() return id==0 and Angle() or boneAngle end} end,
            ManipulateBoneAngles=function(_,id,ang) manipulated[id]=ang end}
        bones.curlAxes=P.CurlAxes(ent,bones,{ang=Angle()},side)
        P.Apply(ent,bones,{0,1,0,0,0},{0,0,0,0},side)
        for id=1,3 do
            local _,world=LocalToWorld(Vector(),manipulated[id],Vector(),boneAngle)
            local before=boneAngle:Forward()
            local angle=math.rad(({75,95,70})[id])*(side=="right" and 1 or -1)
            local expected=Vector(math.cos(angle)*before.x-math.sin(angle)*before.y,math.sin(angle)*before.x+math.cos(angle)*before.y,before.z)
            vec(world:Forward(),expected)
        end
    end
elseif scenario=="grasp_circle" then
    local F=include("nlvr/core/cl_hand_model.lua")
    vec(F.Circle(Vector(0,0,0),Vector(1,1,0),Vector(2,0,0)),Vector(1,0,0))
    vec(F.Circle(Vector(0,0,0),Vector(.001,.001,0),Vector(.002,0,0)),Vector(.001,0,0))
    local p,a=Vector(12,-3,9),Angle(37,81,-22)
    local points={}
    for i,v in ipairs({Vector(0,0,0),Vector(1,1,0),Vector(2,0,0)}) do points[i]=LocalToWorld(v,Angle(),p,a) end
    vec(F.Circle(unpack(points)),LocalToWorld(Vector(1,0,0),Angle(),p,a))
    assert(F.Circle(Vector(),Vector(1,0,0),Vector(2,0,0))==nil)
    local poses={}
    local ent={ManipulateBoneAngles=function(_,id,ang) poses[id]=ang end,InvalidateBoneCache=function() end,SetupBones=function() end,
        GetBoneMatrix=function(_,id)
            return {GetTranslation=function() return id==0 and Vector() or ({Vector(),Vector(1,1,0),Vector(2,0,0)})[id] end,
                GetAngles=function() return Angle() end}
        end}
    local b={wrist=0,fingers={{},{},{1,2,3},{},{}}}
    vec(F.Grip(ent,b,{pos=Vector(1,0,0),ang=Angle()},"right"),Vector(1,0,0))
    for _,ang in pairs(poses) do close(math.abs(ang.p)+math.abs(ang.y)+math.abs(ang.r),0) end
elseif scenario=="handle_axis_fit" then
    local F=include("nlvr/core/cl_hand_model.lua")
    local Frames=include("nlvr/core/cl_frames.lua")
    for _,side in ipairs({"left","right"}) do
        local data=profile("index_"..side) data.model="valve_controller_knu_1_0_"..side
        local raw=Frames.Handle(data)
        local _,target=WorldToLocal(Vector(),raw.ang,Vector(),data.aim.ang)
        local base={pos=Vector(2,0,0),ang=Angle(),grip=Vector(3,1,0),tube={pos=Vector(3,1,0),axis=Vector(0,0,1)}}
        local fitted=F.Fit(base,data)
        local wp,wa=F.Wrist(fitted,{pos=Vector(),ang=Angle()},40)
        vec(LocalToWorld(base.tube.pos,Angle(),wp,wa),Vector())
        local axis=LocalToWorld(base.tube.axis,Angle(),Vector(),wa)
        close(math.abs(axis:Dot(target:Forward())),1)
    end
elseif scenario=="skeletal_reference_frame" then
    local F=include("nlvr/core/cl_hand_model.lua")
    local Frames=include("nlvr/core/cl_frames.lua")
    local data=profile("index_right") data.model="valve_controller_knu_1_0_right"
    local b={} for i=1,31 do b[i]={-.1,0,0,0,0,0} end
    b[2]={-.17,-.03,.04,0,0,0}
    for n,id in ipairs({8,13,18,23}) do b[id]={-.09,-.03,-.025+(n-1)*.015,0,0,0} end
    b[14]={-.085,.005,-.01,0,0,0} b[15]={-.11,.01,.005,0,0,0}
    local sample={valid=true,source="recorded_grip_limit",bones=b}
    local frame={pos=Vector(2,0,0),ang=Angle(),anatomy=Angle(),grip=Vector(3,1,0)}
    local result=F.ReferenceFrame(frame,sample,data)
    local handle=Frames.Handle(data)
    local p,a=F.Wrist(result,{pos=handle.pos*40,ang=data.aim.ang},40)
    vec(p,(Vector(-.17,-.03,.04)+F.ModelConstraint(sample,data))*40)
    local grip=LocalToWorld(result.grip,Angle(),p,a)
    vec(grip,(F.Circle(Vector(unpack(b[13])),Vector(unpack(b[14])),Vector(unpack(b[15])))+F.ModelConstraint(sample,data))*40)
elseif scenario=="constraint_sweep" then
    local F=include("nlvr/core/cl_hand_model.lua") local saved=assert(loadfile(fixturePath))()
    for _,side in ipairs({"left","right"}) do
        local data=profile("index_"..side) data.model="valve_controller_knu_1_0_"..side
        local expected=F.ModelConstraint(saved[side].grip_limit,data)
        for _,kind in ipairs({"open","grip_limit","fist","with_controller"}) do
            vec(F.ModelConstraint(saved[side][kind],data),expected)
        end
        data.model="quest2" vec(F.ModelConstraint(saved[side].grip_limit,data),Vector())
    end
elseif scenario=="bounded_reference" then
    local F=include("nlvr/core/cl_hand_model.lua") local saved=assert(loadfile(fixturePath))()
    for _,side in ipairs({"left","right"}) do
        local data=profile("index_"..side) data.model="valve_controller_knu_1_0_"..side
        local base={pos=Vector(2,0,0),ang=Angle(),anatomy=Angle(),grip=Vector(3.3,0,0)}
        for _,kind in ipairs({"open","grip_limit","fist","with_controller"}) do
            local f=F.ReferenceFrame(base,saved[side][kind],data)
            assert((f.grip-f.pos):Length()<=4,"unbounded live finger circle entered grasp frame")
        end
    end
elseif scenario=="partial_components" then
    local F=include("nlvr/core/cl_hand_model.lua") local Frames=include("nlvr/core/cl_frames.lua")
    local data=profile("index_right") data.model="valve_controller_knu_1_0_right" data.valid=false
    local base={pos=Vector(2,0,0),ang=Angle(),tube={pos=Vector(3,1,0),axis=Vector(0,0,1)}}
    assert(F.Fit(base,data)==base,"invalid components must preserve raw hand fit")
    assert(not Frames.Handle(data),"model name alone must not activate Index correction")
    data.aim.valid=true
    local _,natural=WorldToLocal(Vector(),Angle(),Vector(),data.aim.ang)
    setup(data,natural) local _,dir=C.Ray("right") close(dir.z,0)
elseif scenario=="recorded_reader" then
    local saved=assert(loadfile(fixturePath))() local now=0
    local read,stats=assert(loadfile(root.."/companion/tests/vr_frames_recorded.lua"))()({frames_source_poses=saved,frames_plan={{start=0,duration=20}}},{TestState=function() return {time=now} end})
    for _,side in ipairs({"left","right"}) do
        local buffer={} local first
        for n,time in ipairs({.5,5.5,10.5,15.5}) do
            now=time local out=read(side,"with_controller",buffer)
            assert(out==buffer and out.valid and out.pose_from==({"open","grip_limit","fist","with_controller"})[n])
            local p=Vector(unpack(out.bones[15]))
            if first then assert((p-first):Length()>.001,"reader froze the input pose") else first=p end
        end
        local arrays=stats().bone_arrays local bone=buffer.bones[15]
        now=8 read(side,"with_controller",buffer) assert(buffer.bones[15]==bone and stats().bone_arrays==arrays)
    end
elseif scenario=="sample_storage" then
    local F=include("nlvr/core/cl_hand_model.lua") local saved=assert(loadfile(fixturePath))()
    local out={} assert(F.StoreSample(out,saved.right.open)) local bones,one=out.bones,out.bones[1]
    assert(not F.StoreSample(out,saved.right.open)) assert(F.StoreSample(out,saved.right.fist))
    assert(out.bones==bones and out.bones[1]==one) local revision=out.revision
    assert(not F.StoreSample(out,{valid=false})) assert(out.valid and out.revision==revision)
elseif scenario=="roll_sweep" or scenario=="wrist_sweep" then
    assert(loadfile(root.."/companion/tests/vr_frames_matrix.lua"))()()
    local F=include("nlvr/core/cl_hand_model.lua") local Frames=include("nlvr/core/cl_frames.lua")
    local saved=assert(loadfile(fixturePath))()
    local function direction(m,c) local v=Vector(m[1][c],m[2][c],m[3][c]);return v/v:Length() end
    local maximum,maxWrist,maxPalm,travel=0,0,0,0
    for _,side in ipairs({"left","right"}) do
        local data=profile("index_"..side) data.model="valve_controller_knu_1_0_"..side
        local matrices={[0]=Matrix()} local bones={wrist=0,fingers={},curlAxes={}} local tips={}
        for finger=1,5 do bones.fingers[finger]={}
            for joint=1,3 do local id=(finger-1)*3+joint
                matrices[id]=Matrix();matrices[id]:SetTranslation(Vector(joint,(finger-3)*.6,0))
                bones.fingers[finger][joint]=id bones.curlAxes[id]={curl=Vector(0,0,finger~=1 and side=="left" and -1 or 1)}
            end
            tips[finger]={bone=bones.fingers[finger][3],pos=Vector(1,0,0)}
        end
        local frame=F.ReferenceFrame({pos=Vector(2,0,0),ang=Angle(),anatomy=Angle(),grip=Vector(3.3,0,0)},saved[side].grip_limit,data)
        local handle=Frames.Handle(data) local previous,firstWrist,firstPalm,firstTip
        local sequence={"open","grip_limit","fist","with_controller","open"}
        for n=1,#sequence-1 do for step=0,24 do
            local sample={valid=true,source="with_controller",bones={}}
            local a,b=saved[side][sequence[n]],saved[side][sequence[n+1]]
            for i=1,31 do local p={} for j=1,6 do p[j]=a.bones[i][j]+(b.bones[i][j]-a.bones[i][j])*step/24 end sample.bones[i]=p end
            local out=assert(F.SkeletalMatrices(matrices,bones,tips,sample,{pos=handle.pos*40,ang=data.aim.ang},data,40,frame,side))
            local wp=out[0]:GetTranslation()
            local pp=(wp+(out[4]:GetTranslation()+out[7]:GetTranslation()+out[10]:GetTranslation()+out[13]:GetTranslation())/4)/2
            local tip=out[6]*Vector(1,0,0)
            firstWrist,firstPalm,firstTip=firstWrist or wp,firstPalm or pp,firstTip or tip
            maxWrist=math.max(maxWrist,(wp-firstWrist):Length()/40)
            maxPalm=math.max(maxPalm,(pp-firstPalm):Length()/40)
            travel=math.max(travel,(tip-firstTip):Length()/40)
            if scenario=="wrist_sweep" then assert(maxWrist<.005 and maxPalm<.005,"wrist/palm slid with curl "..maxWrist.." / "..maxPalm) end
            if previous then for id,m in pairs(out) do if id~=0 then
                local f,u=direction(m,1),direction(m,3) local prior=direction(previous[id],3)
                prior=prior-f*prior:Dot(f)
                if prior:Length()>.001 then
                    local angle=math.deg(math.acos(math.Clamp((prior/prior:Length()):Dot(u),-1,1)))
                    maximum=math.max(maximum,angle)
                    assert(scenario=="wrist_sweep" or angle<30,"finger roll discontinuity "..side.." bone "..id.." = "..angle)
                end
            end end end
            previous=out
        end end
    end
    assert(travel>.02,"sweep must articulate the fingers")
    print(string.format("roll %.6f wrist_mm %.6f palm_mm %.6f finger_travel_mm %.6f",maximum,maxWrist*1000,maxPalm*1000,travel*1000))
elseif scenario=="skeletal_matrices" or scenario=="draw_target_pool" then
    local M={} M.__index=M
    function Matrix()
        local m=setmetatable({},M)
        for i=1,4 do m[i]={} for j=1,4 do m[i][j]=i==j and 1 or 0 end end return m
    end
    function M:SetTranslation(v) self[1][4],self[2][4],self[3][4]=v.x,v.y,v.z end
    function M:GetTranslation() return Vector(self[1][4],self[2][4],self[3][4]) end
    function M:SetAngles(a) local axes={a:Forward(),-a:Right(),a:Up()} for j,v in ipairs(axes) do self[1][j],self[2][j],self[3][j]=v.x,v.y,v.z end end
    function M:GetAngles() return Angle() end -- original test bones are independently authored at identity.
    function M:Scale(v) for i=1,3 do self[i][1],self[i][2],self[i][3]=self[i][1]*v.x,self[i][2]*v.y,self[i][3]*v.z end end
    function M:GetInverse()
        local m=Matrix() for i=1,3 do for j=1,3 do m[i][j]=self[j][i] end end
        for i=1,3 do m[i][4]=0 for j=1,3 do m[i][4]=m[i][4]-m[i][j]*self[j][4] end end return m
    end
    M.__mul=function(a,b)
        if getmetatable(b)==getmetatable(Vector()) then return Vector(a[1][1]*b.x+a[1][2]*b.y+a[1][3]*b.z+a[1][4],a[2][1]*b.x+a[2][2]*b.y+a[2][3]*b.z+a[2][4],a[3][1]*b.x+a[3][2]*b.y+a[3][3]*b.z+a[3][4]) end
        local c=Matrix() for i=1,4 do for j=1,4 do c[i][j]=0 for k=1,4 do c[i][j]=c[i][j]+a[i][k]*b[k][j] end end end return c
    end
    local F=include("nlvr/core/cl_hand_model.lua") local Frames=include("nlvr/core/cl_frames.lua")
    local data=profile("index_right") data.model="valve_controller_knu_1_0_right"
    local b={} for i=1,31 do b[i]={-.1,0,0,0,0,0} end
    b[2]={-.16,-.04,.04,0,0,0}
    for n,id in ipairs({8,13,18,23}) do b[id]={-.08,-.04,-.02+(n-1)*.015,0,0,0} end
    b[9]={-.06,-.01,-.02,0,0,0};b[10]={-.075,.01,-.02,0,0,0};b[11]={-.09,-.005,-.02,0,0,0}
    local matrices={} for i=0,3 do matrices[i]=Matrix() matrices[i]:SetTranslation(Vector(i,0,0)) end
    local bones={wrist=0,fingers={{},{1,2,3},{},{},{}}}
    local handle=Frames.Handle(data)
    local out=F.SkeletalMatrices(matrices,bones,{[2]={bone=3,pos=Vector(1,0,0)}},{valid=true,bones=b},
        {pos=handle.pos*40,ang=data.aim.ang},data,40,{anatomy=Angle()},"right")
    vec(out[1]:GetTranslation(),(Vector(unpack(b[8]))+F.ModelConstraint({valid=true,bones=b},data))*40)
    vec(out[2]:GetTranslation(),(Vector(unpack(b[9]))+F.ModelConstraint({valid=true,bones=b},data))*40)
    vec(out[3]:GetTranslation(),(Vector(unpack(b[10]))+F.ModelConstraint({valid=true,bones=b},data))*40)
    vec(out[3]*Vector(1,0,0),(Vector(unpack(b[11]))+F.ModelConstraint({valid=true,bones=b},data))*40)
    if scenario=="draw_target_pool" then
        local cache={}
        F.SkeletalMatrices(matrices,bones,{[2]={bone=3,pos=Vector(1,0,0)}},{valid=true,bones=b},
            {pos=handle.pos*40,ang=data.aim.ang},data,40,{anatomy=Angle()},"right",cache)
        assert(cache.targets and cache.targets[1],"draw target pool absent")
        local first=cache.targets[1].pos
        F.SkeletalMatrices(matrices,bones,{[2]={bone=3,pos=Vector(1,0,0)}},{valid=true,bones=b},
            {pos=handle.pos*40,ang=data.aim.ang},data,40,{anatomy=Angle()},"right",cache)
        assert(cache.targets[1].pos==first and not cache.targets[1].ang,"draw targets allocate pose userdata")
    end
else error(scenario) end
print("PASS "..scenario)
