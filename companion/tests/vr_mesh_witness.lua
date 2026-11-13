-- Independent diagnostic geometry. No NLVR.Weapon, product grip table or Model.Pose input.
local W={}
local cache=setmetatable({},{__mode="k"})
local function centre(points)
    if #points==0 then return end
    local lo,hi=Vector(math.huge,math.huge,math.huge),Vector(-math.huge,-math.huge,-math.huge)
    for _,p in ipairs(points) do for _,k in ipairs({"x","y","z"}) do lo[k]=math.min(lo[k],p[k]) hi[k]=math.max(hi[k],p[k]) end end
    return (lo+hi)/2
end
function W.Select(points,box)
    local out={}
    for _,p in ipairs(points) do if p.x>=box[1] and p.x<=box[2] and p.y>=box[3] and p.y<=box[4] and p.z>=box[5] and p.z<=box[6] then out[#out+1]=p end end
    return out
end
function W.Circle(a,b,c)
    local u,v=b-a,c-a local n=u:Cross(v)
    if n:LengthSqr()<1e-12 then return end
    return a+(v:Cross(n)*u:LengthSqr()+n:Cross(u)*v:LengthSqr())/(2*n:LengthSqr())
end
function W.Grasp(hand)
    local b=hand and hand.bones
    if not b or not b.Finger2 or not b.Finger21 or not b.Finger22 then return end
    return W.Circle(b.Finger2.pos,b.Finger21.pos,b.Finger22.pos)
end
function W.Snapshot(model)
    local found=cache[model]
    local ratio=model.GetModelScale and model:GetModelScale() or model.scale or 1
    if not found or found.ratio~=ratio then
        local points={}
        local parts,bind=util.GetModelMeshes(model:GetModel(),0)
        local unique={}
        for _,part in ipairs(parts or {}) do for _,vertex in ipairs(part.triangles or {}) do
            if #points>=65536 then error("mesh witness vertex bound") end
            local p,total=Vector(),0
            for _,weight in ipairs(vertex.weights or {}) do
                local matrix=model:GetBoneMatrix(weight.bone)
                if matrix and bind and bind[weight.bone] then p=p+(matrix*(bind[weight.bone].matrix*vertex.pos))*weight.weight total=total+weight.weight end
            end
            if total>0 then p=WorldToLocal(p,Angle(),model:GetPos(),model:GetAngles())/ratio else p=vertex.pos end
            local key=string.format("%.5f,%.5f,%.5f",p.x,p.y,p.z)
            if not unique[key] then unique[key]=true points[#points+1]=p end
        end end
        local id=model:LookupBone("ValveBiped.Bip01_R_Hand") local bone=id and model:GetBoneMatrix(id)
        local localBone=bone and WorldToLocal(bone:GetTranslation(),Angle(),model:GetPos(),model:GetAngles())/ratio
        found={points=points,bone=localBone,ratio=ratio,path=model:GetModel()} cache[model]=found
    end
    return {points=found.points,bone=found.bone,scale=ratio,path=found.path,pos=model:GetPos(),ang=model:GetAngles()}
end
function W.World(snapshot,p) return LocalToWorld(p*snapshot.scale,Angle(),snapshot.pos,snapshot.ang) end
function W.Grip(snapshot,hand,spec)
    local point
    if spec.kind=="shaft" then
        local centres={}
        for _,box in ipairs(spec.shaft_caps) do
            local selected=W.Select(snapshot.points,box)
            if #selected==0 then return end
            centres[#centres+1]=centre(selected)
        end
        local axis=(centres[2]-centres[1]):GetNormalized()
        local grasp=W.Grasp(hand)
        if not grasp or not snapshot.bone then return end
        local delta=WorldToLocal(grasp-hand.bones.Hand.pos,Angle(),Vector(),snapshot.ang)/snapshot.scale
        local station=snapshot.bone+delta
        point=centres[1]+axis*(station-centres[1]):Dot(axis)
    else
        local lo,hi=Vector(unpack(spec.handle_bounds[1])),Vector(unpack(spec.handle_bounds[2]))
        point=(lo+hi)/2
        if spec.handle_axis then
            local axis=Vector(unpack(spec.handle_axis))
            local grasp=W.Grasp(hand)
            if not grasp then return end
            local target=WorldToLocal(grasp,Angle(),snapshot.pos,snapshot.ang)/snapshot.scale
            local low,high=math.huge,-math.huge
            for _,p in ipairs(snapshot.points) do
                local selected=true
                for _,cut in ipairs(spec.handle_cuts) do
                    local value=({p.x,p.y,p.z})[cut[1]+1]
                    if value<=cut[2] or value>=cut[3] then selected=false break end
                end
                if selected then local d=(p-point):Dot(axis) low=math.min(low,d) high=math.max(high,d) end
            end
            point=point+axis*math.Clamp((target-point):Dot(axis),low,high)
        end
    end
    return point and W.World(snapshot,point),point
end
function W.Expected(hand,spec)
    return W.Grasp(hand)
end
function W.BoneEnvelope(snapshot,hand,spec)
    if not snapshot.bone or not spec.handle_bounds then return false end
    local bone=W.World(snapshot,snapshot.bone)
    -- Use the observed asset bone and actual drawn finger bones, never product grip data.
    local p=WorldToLocal(W.Grasp(hand),Angle(),bone,snapshot.ang)/snapshot.scale+snapshot.bone
    for i,k in ipairs({"x","y","z"}) do
        if p[k]<spec.handle_bounds[1][i]-.2 or p[k]>spec.handle_bounds[2][i]+.2 then return false end
    end
    return true,(bone-hand.bones.Hand.pos):Length()/snapshot.scale
end
function W.Barrel(snapshot,spec)
    if spec.gun_axis then
        local axis=Vector(unpack(spec.gun_axis))
        return LocalToWorld(axis,Angle(),Vector(),snapshot.ang):GetNormalized(),axis
    end
    if not spec.barrel_caps then return end
    -- Fit a plane to the forward cap. Production uses two ring bounding centres.
    local max=-math.huge for _,p in ipairs(snapshot.points) do max=math.max(max,p.x) end
    local cap={} local mean=Vector()
    for _,p in ipairs(snapshot.points) do if p.x>max-.15 then cap[#cap+1]=p mean=mean+p end end
    if #cap<3 then return end mean=mean/#cap
    local u,v,far,area=nil,nil,0,0
    for _,p in ipairs(cap) do local d=p-mean if d:LengthSqr()>far then u,far=d,d:LengthSqr() end end
    for _,p in ipairs(cap) do local d=p-mean local a=u:Cross(d):LengthSqr() if a>area then v,area=d,a end end
    if not v or area<1e-12 then return end
    local axis=u:Cross(v):GetNormalized() if axis.x<0 then axis=-axis end
    return LocalToWorld(axis,Angle(),Vector(),snapshot.ang):GetNormalized(),axis
end
function W.End(snapshot,axis)
    local far=-math.huge
    for _,p in ipairs(snapshot.points) do far=math.max(far,p:Dot(axis)) end
    local selected={}
    for _,p in ipairs(snapshot.points) do if far-p:Dot(axis)<.2 then selected[#selected+1]=p end end
    local p=centre(selected)
    return p and W.World(snapshot,p),p
end
function W.StrikeAxis(snapshot,spec)
    local cap={}
    for _,box in ipairs(spec.shaft_caps or {}) do
        local points=W.Select(snapshot.points,box)
        if #points==0 then return end
        cap[#cap+1]=centre(points)
    end
    if #cap~=2 then return end
    local axis=(cap[2]-cap[1]):GetNormalized()
    local low,high=math.huge,-math.huge
    for _,p in ipairs(snapshot.points) do local t=(p-snapshot.bone):Dot(axis) low=math.min(low,t) high=math.max(high,t) end
    return math.abs(low)>math.abs(high) and -axis or axis
end
return W
