-- Stock melee/SMG posed geometry; measured at the model's authored pose, never per draw.
local Mesh={}
local specs={
 ["models/weapons/w_crowbar.mdl"]={shaft={{-15.6,-15.1,-.7,1.3,-1,1},{11.5,12.1,-.7,1.3,-1,1}},strike=-1},
 ["models/weapons/w_stunbaton.mdl"]={shaft={{3.5299,4.0036,-0.6877,0.77,-0.2859,1.1376},{9.7938,10.3803,-0.6797,0.6976,-0.3814,0.9963}},strike=-1},
 ["models/weapons/w_smg1.mdl"]={barrel={{4.8,5.1,1,2,1.8,2.6},{7.5,8,1,2,1.8,2.6}}}}
local function bounds(points,box)
    local lo,hi
    for _,p in ipairs(points) do
        if not box or p.x>=box[1] and p.x<=box[2] and p.y>=box[3] and p.y<=box[4] and p.z>=box[5] and p.z<=box[6] then
            if not lo then lo,hi=Vector(p.x,p.y,p.z),Vector(p.x,p.y,p.z)
            else for _,k in ipairs({"x","y","z"}) do lo[k]=math.min(lo[k],p[k]) hi[k]=math.max(hi[k],p[k]) end end
        end
    end
    return lo,hi
end
function Mesh.Read(model)
    if not specs[(model:GetModel() or ""):lower()] or not util or not util.GetModelMeshes then return end
    local ok,parts,bind=pcall(util.GetModelMeshes,model:GetModel(),0)
    if not ok or not parts then return end
    local points={}
    for _,part in ipairs(parts) do for _,v in ipairs(part.triangles or {}) do
        if #points>=65536 then return end
        local p,total=Vector(),0
        for _,weight in ipairs(v.weights or {}) do
            local bone=model:GetBoneMatrix(weight.bone)
            if bone and bind and bind[weight.bone] then p=p+(bone*(bind[weight.bone].matrix*v.pos))*weight.weight total=total+weight.weight end
        end
        points[#points+1]=total>0 and p or v.pos
    end end
    if #points<3 then return end
    return points
end
function Mesh.Axis(model,points)
    local spec=specs[(model:GetModel() or ""):lower()]
    if not spec or not points then return end
    local caps=spec.shaft or spec.barrel
    local a,b
    for i,box in ipairs(caps) do local lo,hi=bounds(points,box) if not lo then return end
        if i==1 then a=(lo+hi)/2 else b=(lo+hi)/2 end
    end
    local axis=(b-a):GetNormalized()
    return axis*(spec.strike or 1),a,axis
end
function Mesh.Grip(model,points,reference)
    local spec=specs[(model:GetModel() or ""):lower()]
    if not spec or not spec.shaft then return end
    local _,origin,axis=Mesh.Axis(model,points)
    if not origin then return end
    return origin+axis*(reference-origin):Dot(axis)
end
function Mesh.End(points,axis)
    if not points then return end
    local far=-math.huge for _,p in ipairs(points) do far=math.max(far,p:Dot(axis)) end
    local selected={} for _,p in ipairs(points) do if far-p:Dot(axis)<.2 then selected[#selected+1]=p end end
    local lo,hi=bounds(selected)
    return lo and (lo+hi)/2
end
return Mesh
