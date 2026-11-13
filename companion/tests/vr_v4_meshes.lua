-- Test-only model geometry export: actual posed vertices, independent of VR targets.
local qMeshExported=false
hook.Add("PreRender","q4_mesh_export",function()
    if qMeshExported or not NLVR then return end qMeshExported=true
    for _,name in ipairs({"w_pistol","w_smg1","w_irifle","w_shotgun","w_crossbow","w_annabelle","w_crowbar","w_stunbaton","w_357","w_rocket_launcher","w_grenade","w_bugbait","w_physics","w_toolgun","w_medkit","camera"}) do
        local path=name=="camera" and "models/maxofs2d/camera.mdl" or "models/weapons/"..name..".mdl"
        local m=ClientsideModel(path,RENDERGROUP_OPAQUE)
        assert(IsValid(m),path)
        m:SetNoDraw(true) m:SetPos(Vector()) m:SetAngles(Angle()) m:SetSequence(0) m:SetCycle(0) m:SetupBones()
        local lo,hi=m:GetModelBounds()
        local data={name=name,path=path,bones={},attachments={},lo=lo,hi=hi,vertices={}}
        for i=0,m:GetBoneCount()-1 do
            local bone=m:GetBoneName(i) local matrix=m:GetBoneMatrix(i)
            if matrix then data.bones[bone]={pos=matrix:GetTranslation(),ang=matrix:GetAngles()} end
        end
        for _,a in ipairs(m:GetAttachments() or {}) do data.attachments[a.name]={id=a.id,pose=m:GetAttachment(a.id)} end
        local meshes,bind=util.GetModelMeshes(path,0)
        local unique={}
        for _,part in ipairs(meshes or {}) do for _,v in ipairs(part.triangles or part.verticies or {}) do
            local p,total=Vector(),0
            for _,weight in ipairs(v.weights or {}) do
                local matrix=m:GetBoneMatrix(weight.bone)
                if matrix and bind[weight.bone] then p=p+(matrix*(bind[weight.bone].matrix*v.pos))*weight.weight total=total+weight.weight end
            end
            if total==0 then p=v.pos end
            local key=string.format("%.5f,%.5f,%.5f",p.x,p.y,p.z)
            if not unique[key] then unique[key]=true data.vertices[#data.vertices+1]={p.x,p.y,p.z} end
        end end
        local encoded=util.Base64Encode(util.TableToJSON(data)):gsub("%s","")
        local count=math.ceil(#encoded/1600)
        for i=1,count do print("NLVR_QMODEL "..name.." "..i.."/"..count.." "..encoded:sub((i-1)*1600+1,i*1600)) end
        m:Remove()
    end
end)
