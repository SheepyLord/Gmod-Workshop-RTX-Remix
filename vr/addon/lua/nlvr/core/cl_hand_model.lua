-- C's anatomical model calibration; the original H pose/collision helper stays unchanged.
local Pose = include("nlvr/modules/cl_hands_pose.lua")
local Controllers = include("nlvr/core/cl_frames.lua")
local F = {}
local function unit(v) return v:Length() > 0.00001 and v / v:Length() or nil end
function F.Measure(entity, bones)
    local wrist = entity:GetBoneMatrix(bones.wrist)
    if not wrist then return end
    local knuckles = {}
    for i=2,5 do
        local id = bones.fingers[i][1]
        local matrix = id and entity:GetBoneMatrix(id)
        if not matrix then return end
        knuckles[i] = WorldToLocal(matrix:GetTranslation(), Angle(), wrist:GetTranslation(), wrist:GetAngles())
    end
    -- Metacarpals define the palm even when sequence zero already flexes the phalanges.
    -- This is the same wrist-to-mean-knuckle axis used by the native skeletal frame.
    local palm = (knuckles[2]+knuckles[3]+knuckles[4]+knuckles[5])/8
    local forward = unit(palm)
    local radial = knuckles[2] - knuckles[5]
    if not forward then return end
    local up = unit(radial - forward * forward:Dot(radial))
    if not up then return end
    -- +X along the fingers, +Z toward index/thumb. Chirality is in the mesh, never a mirror scale.
    return {pos=palm, ang=forward:AngleEx(up)}
end
function F.Wrist(frame, shown, scale)
    local pos, ang = WorldToLocal(Vector(), Angle(), frame.pos * (scale/40), frame.ang)
    return LocalToWorld(pos, ang, shown.pos, shown.ang)
end
local function fraction(v) return type(v)=="number" and v==v and math.Clamp(v,0,1) or 0 end
local function around(axis, degrees)
    local x,y,z=axis.x,axis.y,axis.z
    local c,s=math.cos(math.rad(degrees)),math.sin(math.rad(degrees))
    local t=1-c
    local xx,xy,xz=c+x*x*t,x*y*t-z*s,x*z*t+y*s
    local yx,yy,yz=y*x*t+z*s,c+y*y*t,y*z*t-x*s
    local zx,zy,zz=z*x*t-y*s,z*y*t+x*s,c+z*z*t
    return Angle(math.deg(math.atan2(-zx,math.sqrt(xx*xx+yx*yx))),math.deg(math.atan2(yx,xx)),math.deg(math.atan2(zy,zz)))
end
function F.CurlAxes(entity,bones,frame,side)
    local wrist=entity:GetBoneMatrix(bones.wrist)
    if not frame or not wrist then return end
    local _,anatomy=LocalToWorld(Vector(),frame.ang,Vector(),wrist:GetAngles())
    local axes={}
    for finger=1,5 do
        for joint=1,3 do
            local id=bones.fingers[finger][joint]
            local matrix=id and entity:GetBoneMatrix(id)
            if matrix then
                -- Flex toward the palm: right +Y / left -Y in the anatomical frame.
                -- Bone-local yaw is not that axis on c_arms; its joints have different bind bases.
                local world=finger==1 and -anatomy:Right() or anatomy:Up()*(side=="right" and 1 or -1)
                local axis=WorldToLocal(world,Angle(),Vector(),matrix:GetAngles())
                local fan=WorldToLocal(-anatomy:Right(),Angle(),Vector(),matrix:GetAngles())
                axes[id]={curl=axis/axis:Length(),spread=fan/fan:Length()}
            end
        end
    end
    return axes
end
function F.Apply(entity, bones, curls, splay, side)
    for finger = 1, 5 do
        for joint = 1, 3 do
            local id = bones.fingers[finger][joint]
            if id ~= nil then
                local axis=bones.curlAxes and bones.curlAxes[id]
                local angle=Pose.Angles(finger,joint,curls[finger],splay[math.max(1,finger-1)],side)
                if axis then
                    local maximum=(finger==1 and ({40,50,55}) or ({75,95,70}))[joint]
                    angle=around(axis.curl,maximum*fraction(curls[finger]))
                    local spread=joint==1 and (finger-3.5)*12*fraction(splay[math.max(1,finger-1)])*(1-fraction(curls[finger])) or 0
                    local ignored
                    ignored,angle=LocalToWorld(Vector(),around(axis.spread,spread),Vector(),angle)
                end
                entity:ManipulateBoneAngles(id,angle)
            end
        end
    end
end
local function cross(a,b) return Vector(a.y*b.z-a.z*b.y,a.z*b.x-a.x*b.z,a.x*b.y-a.y*b.x) end
function F.Circle(a,b,c)
    local u,v=b-a,c-a
    local n=cross(u,v)
    local square=n:Dot(n)
    if square<1e-14 or square~=square then return end
    return a+(cross(v,n)*u:Dot(u)+cross(n,u)*v:Dot(v))/(2*square)
end
function F.Grip(entity,bones,frame,side)
    if not frame then return end
    -- The middle finger's closed joint arc locates the handle volume, rather than
    -- the palm surface or a right-hand wrist copied to the other side of a gun.
    F.Apply(entity,bones,{.65,.3,.68,.68,.68},{0,0,0,0},side)
    entity:InvalidateBoneCache() entity:SetupBones()
    local points={}
    for i=1,3 do
        local id=bones.fingers[3][i]
        local m=id and entity:GetBoneMatrix(id)
        if m then points[i]=m:GetTranslation() end
    end
    local wrist=entity:GetBoneMatrix(bones.wrist)
    local tubePoints,arcCentres={},{}
    if wrist then
        for finger=2,5 do for joint=1,2 do
            local id=bones.fingers[finger][joint]
            local m=id and entity:GetBoneMatrix(id)
            if m then tubePoints[#tubePoints+1]=WorldToLocal(m:GetTranslation(),Angle(),wrist:GetTranslation(),wrist:GetAngles()) end
        end end
        for finger=2,5 do
            local a,b,c
            local ids=bones.fingers[finger]
            if ids[1] and ids[2] and ids[3] then
                a,b,c=entity:GetBoneMatrix(ids[1]),entity:GetBoneMatrix(ids[2]),entity:GetBoneMatrix(ids[3])
            end
            local centre=a and b and c and F.Circle(a:GetTranslation(),b:GetTranslation(),c:GetTranslation())
            if centre then arcCentres[#arcCentres+1]=WorldToLocal(centre,Angle(),wrist:GetTranslation(),wrist:GetAngles()) end
        end
    end
    local centre=points[1] and points[2] and points[3] and F.Circle(points[1],points[2],points[3])
    local result=centre and wrist and WorldToLocal(centre,Angle(),wrist:GetTranslation(),wrist:GetAngles())
    if result and (result-frame.pos):Length()>8 then result=nil end
    for _,finger in ipairs(bones.fingers) do for _,id in pairs(finger) do entity:ManipulateBoneAngles(id,Angle()) end end
    entity:InvalidateBoneCache() entity:SetupBones()
    local tube=F.Line(#arcCentres==4 and arcCentres or tubePoints)
    if tube then tube.surface=F.Line(tubePoints) tube.method=#arcCentres==4 and "finger_arc_centres" or "joint_surface_fallback" end
    return result,tube
end
function F.Line(points)
    if #points<3 then return end
    local centre=Vector()
    for _,p in ipairs(points) do centre=centre+p end
    centre=centre/#points
    local covariance={{0,0,0},{0,0,0},{0,0,0}}
    for _,p in ipairs(points) do
        local d=p-centre local v={d.x,d.y,d.z}
        for i=1,3 do for j=1,3 do covariance[i][j]=covariance[i][j]+v[i]*v[j] end end
    end
    local largest=1 for i=2,3 do if covariance[i][i]>covariance[largest][largest] then largest=i end end
    local a={0,0,0} a[largest]=1
    for _=1,48 do
        local b={} local n=0
        for i=1,3 do b[i]=0 for j=1,3 do b[i]=b[i]+covariance[i][j]*a[j] end n=n+b[i]^2 end
        if n<1e-12 then return end
        for i=1,3 do a[i]=b[i]/math.sqrt(n) end
    end
    return {pos=centre,axis=Vector(a[1],a[2],a[3]),count=#points}
end
function F.Fit(frame,controller)
    if not frame or not frame.tube then return frame end
    local handle=Controllers.Handle(controller)
    if not handle then return frame end
    local _,target=WorldToLocal(Vector(),handle.ang,Vector(),controller.aim.ang)
    local z=-target:Forward() -- thumb end points toward the controller head, not its base.
    local forward=Vector(1,0,0)-z*z.x forward=forward/forward:Length()
    local targetFrame=forward:AngleEx(z)
    local axis=frame.tube.axis
    local up=frame.ang:Up()
    if axis:Dot(up)<0 then axis=-axis end
    local x=frame.ang:Forward()-axis*frame.ang:Forward():Dot(axis) x=x/x:Length()
    local sourceFrame=x:AngleEx(axis)
    local _,inverse=WorldToLocal(Vector(),Angle(),Vector(),targetFrame)
    local _,mapping=LocalToWorld(Vector(),inverse,Vector(),sourceFrame)
    local out={} for k,v in pairs(frame) do out[k]=v end
    out.palm=frame.pos out.anatomy=frame.ang out.pos=frame.tube.pos out.ang=mapping out.calibrated=true
    return out
end
function F.Tips(entity,bones,body,skin)
    if not util or not util.GetModelMeshes then return {} end
    local ok,meshes,bind=pcall(util.GetModelMeshes,entity:GetModel(),0,body or 0,skin or 0)
    if not ok or not meshes or not bind then return {} end
    local results={}
    for finger=1,5 do
        local id,prior=bones.fingers[finger][3],bones.fingers[finger][2]
        local m,p=id and entity:GetBoneMatrix(id),prior and entity:GetBoneMatrix(prior)
        if m and p and bind[id] then
            local axis=m:GetTranslation()-p:GetTranslation()
            axis=WorldToLocal(axis,Angle(),Vector(),m:GetAngles()) axis=unit(axis)
            if axis then
                local selected,maximum={},-math.huge
                for _,mesh in ipairs(meshes) do for _,v in ipairs(mesh.verticies or mesh.triangles or {}) do
                    local owned=false
                    for _,w in ipairs(v.weights or {}) do if w.bone==id and w.weight>=.5 then owned=true end end
                    if owned then
                        local localPos=bind[id].matrix*v.pos
                        local distance=localPos:Dot(axis)
                        if distance>maximum then maximum=distance end
                        selected[#selected+1]={pos=localPos,distance=distance}
                    end
                end end
                local total,count=Vector(),0
                for _,v in ipairs(selected) do if v.distance>=maximum-.04 then total=total+v.pos count=count+1 end end
                if count>0 then results[finger]={bone=id,pos=total/count,method="weighted_mesh_end",vertices=count} end
            end
        end
    end
    return results
end
function F.SkeletalMatrices(matrices,bones,tips,sample,shown,controller,scale,frame,side,cache)
    if not frame or not sample or not sample.valid or not controller or not controller.valid then return end
    local handle=Controllers.Handle(controller)
    local localHand=handle and {pos=handle.pos,ang=controller.aim.ang} or controller.hand
    local correction=F.ModelConstraint(sample,controller)
    local root=sample.bones[2]
    local wx,wy,wz=root.pos and root.pos.x or root[1],root.pos and root.pos.y or root[2],root.pos and root.pos.z or root[3]
    local ref=frame.referenceWrist
    local dx,dy,dz=correction.x-localHand.pos.x,correction.y-localHand.pos.y,correction.z-localHand.pos.z
    if ref then dx,dy,dz=dx+ref.x-wx,dy+ref.y-wy,dz+ref.z-wz end
    local lf,ll,lu=localHand.ang:Forward(),-localHand.ang:Right(),localHand.ang:Up()
    local sf,sl,su=shown.ang:Forward(),-shown.ang:Right(),shown.ang:Up()
    local r11,r12,r13=sf.x*lf.x+sl.x*ll.x+su.x*lu.x,sf.x*lf.y+sl.x*ll.y+su.x*lu.y,sf.x*lf.z+sl.x*ll.z+su.x*lu.z
    local r21,r22,r23=sf.y*lf.x+sl.y*ll.x+su.y*lu.x,sf.y*lf.y+sl.y*ll.y+su.y*lu.y,sf.y*lf.z+sl.y*ll.z+su.y*lu.z
    local r31,r32,r33=sf.z*lf.x+sl.z*ll.x+su.z*lu.x,sf.z*lf.y+sl.z*ll.y+su.z*lu.y,sf.z*lf.z+sl.z*ll.z+su.z*lu.z
    cache=cache or {} cache.targets=cache.targets or {}
    local targets=cache.targets
    for i,p in ipairs(sample.bones) do
        local x,y,z=p.pos and p.pos.x or p[1],p.pos and p.pos.y or p[2],p.pos and p.pos.z or p[3]
        x,y,z=(x+dx)*scale,(y+dy)*scale,(z+dz)*scale
        local target=targets[i]
        if not target then target={pos=Vector()} targets[i]=target end
        target.pos.x,target.pos.y,target.pos.z=shown.pos.x+r11*x+r12*y+r13*z,shown.pos.y+r21*x+r22*y+r23*z,shown.pos.z+r31*x+r32*y+r33*z
    end
    if not targets[26] then return end
    local wrist=matrices[bones.wrist]
    if not wrist then return end
    local centre=(targets[8].pos+targets[13].pos+targets[18].pos+targets[23].pos)/4
    local forward=unit(centre-targets[2].pos)
    local radial=targets[8].pos-targets[23].pos
    if not forward then return end
    local up=unit(radial-forward*forward:Dot(radial))
    if not up then return end
    local palm=forward:AngleEx(up)
    local targetNormal=-palm:Right()*(side=="right" and 1 or -1)
    local rawHinge=frame.referenceHinge
    local function worldDirection(v)
        local q=WorldToLocal(v,Angle(),Vector(),localHand.ang)
        return LocalToWorld(q,Angle(),Vector(),shown.ang)
    end
    local targetHinge=rawHinge and worldDirection(rawHinge) or up
    local _,modelAnatomy=LocalToWorld(Vector(),frame.anatomy or frame.ang,Vector(),wrist:GetAngles())
    local sourceNormal=-modelAnatomy:Right()*(side=="right" and 1 or -1)
    local ratio=scale/40
    local _,inverse=WorldToLocal(Vector(),Angle(),Vector(),frame.anatomy or frame.ang)
    local _,wristAng=LocalToWorld(Vector(),inverse,Vector(),palm)
    if frame.skeletal_source then local ignored;ignored,wristAng=F.Wrist(frame,shown,scale) end
    local out={} local w=Matrix() w:SetTranslation(targets[2].pos) w:SetAngles(wristAng) w:Scale(Vector(ratio,ratio,ratio));out[bones.wrist]=w
    for finger=1,5 do for joint=1,3 do
        local id=bones.fingers[finger][joint]
        local original=id and matrices[id]
        local sdk=(finger==1 and 2 or 7+(finger-2)*5)+(joint-1)
        if original and targets[sdk+1] and targets[sdk+2] then
            local nextId=bones.fingers[finger][joint+1]
            local nextPos=nextId and matrices[nextId] and matrices[nextId]:GetTranslation()
            local tip=tips and tips[finger]
            if joint==3 and tip then nextPos=original*tip.pos end
            if nextPos then
                local sourceAxis=WorldToLocal(nextPos-original:GetTranslation(),Angle(),Vector(),original:GetAngles())
                local oldLength=sourceAxis:Length()
                local a,b=targets[sdk+1].pos,targets[sdk+2].pos
                local targetAxis=b-a
                if oldLength>.0001 and targetAxis:Length()>.0001 then
                    local localUp=bones.curlAxes and bones.curlAxes[id] and bones.curlAxes[id].curl
                        or WorldToLocal(finger==1 and sourceNormal or modelAnatomy:Up(),Angle(),Vector(),original:GetAngles())
                    if finger~=1 and side=="left" and bones.curlAxes and bones.curlAxes[id] then localUp=-localUp end
                    local sourceFrame=Matrix() sourceFrame:SetAngles((sourceAxis/oldLength):AngleEx(localUp))
                    local targetFrame=Matrix() targetFrame:SetTranslation(a) targetFrame:SetAngles(targetAxis:AngleEx(finger==1 and (frame.referenceThumbHinge and worldDirection(frame.referenceThumbHinge) or targetNormal) or targetHinge))
                    targetFrame:Scale(Vector(targetAxis:Length()/oldLength,ratio,ratio))
                    out[id]=targetFrame*sourceFrame:GetInverse()
                end
            end
        end
    end end
    return out
end
function F.ReferenceFrame(frame,sample,controller)
    if not frame or not sample or not sample.valid or not controller or not controller.valid then return frame end
    -- A grasp calibration is a reference pose, never an observed live finger arc.
    if sample.source and not sample.source:find("grip_limit",1,true) then return frame end
    local b={}
    local correction=F.ModelConstraint(sample,controller)
    for i,p in ipairs(sample.bones) do b[i]=(p.pos or Vector(p[1],p[2],p[3]))+correction end
    if not b[26] then return frame end
    local direction=unit((b[8]+b[13]+b[18]+b[23])/4-b[2])
    local radial=b[8]-b[23]
    if not direction then return frame end
    local up=unit(radial-direction*direction:Dot(radial)) if not up then return frame end
    local palm=direction:AngleEx(up)
    local _,inverse=WorldToLocal(Vector(),Angle(),Vector(),frame.anatomy or frame.ang)
    local _,wristAng=LocalToWorld(Vector(),inverse,Vector(),palm)
    local handle=Controllers.Handle(controller)
    local localHand=handle and {pos=handle.pos,ang=controller.aim.ang} or controller.hand
    local pos,ang=WorldToLocal(localHand.pos*40,localHand.ang,b[2]*40,wristAng)
    local centre=F.Circle(b[13],b[14],b[15])
    if not centre then return frame end
    local grip=WorldToLocal(centre*40,Angle(),b[2]*40,wristAng)
    if (grip-pos):Length()>4 then grip=pos end
    local out={} for k,v in pairs(frame) do out[k]=v end
    out.pos,out.ang,out.grip,out.calibrated=pos,ang,grip,true
    out.skeletal_source=sample.source
    out.referenceCorrection=correction
    out.referenceWrist=b[2]-correction
    out.referenceHinge=up
    local thumb=unit(cross(b[4]-b[3],b[5]-b[4]))
    if thumb and thumb:Dot(-palm:Right())<0 then thumb=-thumb end
    out.referenceThumbHinge=thumb or -palm:Right()
    return out
end
function F.ModelConstraint(_,controller)
    -- Derived once from the recorded Index GripLimit and measured body handle.
    -- It is a constant rigid translation, independent of observed finger curl.
    local handle=Controllers.Handle(controller)
    return handle and handle.correction or Vector()
end
function F.StoreSample(out,sample)
    if not sample or not sample.valid or not sample.bones or #sample.bones~=31 then return false end
    local changed=not out.valid or out.source~=sample.source
    out.bones=out.bones or {}
    for i,p in ipairs(sample.bones) do
        local q=out.bones[i] or {};out.bones[i]=q
        for j=1,6 do
            local value=p[j]
            if value==nil then local v=j<=3 and p.pos or p.ang
                value=j==1 and v.x or j==2 and v.y or j==3 and v.z or j==4 and v.p or j==5 and v.y or v.r
            end
            if q[j]~=value then changed=true;q[j]=value end
        end
    end
    out.valid,out.error,out.source=true,0,sample.source
    out.sample_time=sample.sample_time
    if changed then out.revision=(out.revision or 0)+1 end
    return changed
end
return F
