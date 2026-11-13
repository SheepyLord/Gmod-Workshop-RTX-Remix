-- Model-local measurements and world rendering; no hooks on include.
local W = include("nlvr/modules/sh_weapons.lua")
local M = {}
local HandGeometry=include("nlvr/core/cl_hand_model.lua")
local Mesh=include("nlvr/modules/cl_weapons_mesh.lua")
function M.ModelGrip(model)
    for _,name in ipairs({"grip","handle","anim_attachment_RH"}) do
        local id=model:LookupAttachment(name)
        local a=id and id>0 and model:GetAttachment(id)
        if a then return a.Pos,"attachment:"..name end
    end
    local points={}
    for i,name in ipairs({"ValveBiped.Bip01_R_Finger2","ValveBiped.Bip01_R_Finger21","ValveBiped.Bip01_R_Finger22"}) do
        local id=model:LookupBone(name) local m=id and model:GetBoneMatrix(id)
        if m then points[i]=m:GetTranslation() end
    end
    if #points==3 then
        local p=HandGeometry.Circle(points[1],points[2],points[3])
        local wrist=model:LookupBone("ValveBiped.Bip01_R_Hand") local m=wrist and model:GetBoneMatrix(wrist)
        if p and m and (p-m:GetTranslation()):Length()<8 then return p,"model_finger_bones" end
    end
    local measured=W.GripData(model:GetModel())
    if measured then return Vector(unpack(measured)),"posed_handle_measurement" end
end
local cameraHash="0x35d7392325ed05a9"
local function cameraNegative(token) return token:lower()=="-"..cameraHash end
function M.Prepare(active)
    local ent=active.ent
    if active.class=="gmod_camera" and active.path:lower()=="models/maxofs2d/camera.mdl" and
        RemixConfig and RemixConfig.GetConfigVariable and RemixConfig.SetConfigVariable then
        -- This stock texture is ignored by the inherited classic layer. The getter
        -- exposes the user-layer delta, not the merged set: a negative hash subtracts
        -- only this camera while held. Never save config or edit its material/files.
        local option="rtx.ignoreTextures"
        local before=RemixConfig.GetConfigVariable(option)
        if type(before)=="string" then
            local present=false
            for token in before:gmatch("[^,]+") do if cameraNegative(token:match("^%s*(.-)%s*$")) then present=true end end
            if not present then
                active.cameraOverride={config=RemixConfig,option=option,before=before}
                RemixConfig.SetConfigVariable(option,(before~="" and before..", " or "").."-"..cameraHash)
                active.cameraOverride.applied=RemixConfig.GetConfigVariable(option)
            end
        end
    end
    if active.class~="gmod_tool" or type(ent.RenderScreen)~="function" then return end
    local raw=rawget(ent:GetTable(),"RenderScreen")
    local replacement=function() end
    active.screen={raw=raw,replacement=replacement}
    -- This callback paints the hidden first-person screen. T's SteamVR overlay owns
    -- tool information; a nested canvas must not recapture the world hand draws.
    ent.RenderScreen=replacement
end
function M.Restore(active)
    local override=active and active.cameraOverride
    if override then
        active.cameraOverride=nil
        local current=override.config.GetConfigVariable(override.option)
        if current==override.applied then override.config.SetConfigVariable(override.option,override.before)
        elseif type(current)=="string" then
            local kept,removed,first={},false,true
            for token in current:gmatch("[^,]+") do
                if not removed and cameraNegative(token:match("^%s*(.-)%s*$")) then removed=true
                else
                    if first and removed then token=token:gsub("^%s+","") end
                    kept[#kept+1]=token first=false
                end
            end
            if removed then override.config.SetConfigVariable(override.option,table.concat(kept,",")) end
        end
    end
    if active and active.screen and IsValid(active.ent) and active.ent.RenderScreen==active.screen.replacement then
        active.ent.RenderScreen=active.screen.raw
    end
end
function M.Measure(model, class, handFrame, side, rightFrame)
    local began=SysTime and SysTime() or 0
    M.measures=(M.measures or 0)+1
    -- Remeasurement can happen after a hand-model/scale change. Read authored units,
    -- never a world-space or already-scaled bone cache from the preceding draw.
    model:SetModelScale(1,0)
    model:SetPos(Vector()) model:SetAngles(Angle()) model:InvalidateBoneCache() model:SetupBones()
    local points=Mesh.Read(model)
    local bone = model:LookupBone("ValveBiped.Bip01_R_Hand")
    local matrix = bone and model:GetBoneMatrix(bone)
    local gripPos, gripAng = matrix and matrix:GetTranslation() or Vector(), matrix and matrix:GetAngles() or Angle()
    local id = model:LookupAttachment("muzzle")
    local info = W.Data(class)
    local modelInfo = W.ModelData(model:GetModel())
    local melee=W.Kind(class)=="melee"
    local meshAxis=Mesh.Axis(model,points)
    -- w_physics names its emitter core. Only that model has the numeric fallback;
    -- the independent observer reads the asset's semantic name, not T's draw rule.
    if not id or id<=0 then id=modelInfo.attachment end
    local attachment = id and id > 0 and model:GetAttachment(id)
    -- The wrist gives the grip's position. Its rotational basis differs between
    -- c_arms and third-person weapons; copying H's -90 roll makes the gun lie sideways.
    -- Known world models are authored upright, with the per-class +/-X barrel below.
    local wrist = Angle()
    local origin, rotation = W.Place(gripPos, gripAng, Vector(), wrist)
    local correction=Angle()
    local barrel,barrelSource
    do
        local axis=Vector(info.axis or modelInfo.axis or 1,0,0)
        if melee and model.GetModelBounds then
            local mins,maxs=model:GetModelBounds()
            local size=maxs-mins
            local key=size.x>=size.y and size.x>=size.z and "x" or size.y>=size.z and "y" or "z"
            axis=Vector() axis[key]=(maxs[key]-gripPos[key])>=(gripPos[key]-mins[key]) and 1 or -1
        end
        if not next(info) and not next(modelInfo) and model.GetModelBounds then
            local lo,hi=model:GetModelBounds()
            if W.Vector(lo) and W.Vector(hi) and (hi-lo):Length()<120 then
                local size=hi-lo local key=size.x>=size.y and size.x>=size.z and "x" or size.y>=size.z and "y" or "z"
                axis=Vector() axis[key]=(hi[key]-gripPos[key])>=(gripPos[key]-lo[key]) and 1 or -1
            end
        end
        barrel=meshAxis or attachment and attachment.Ang:Forward() or axis
        barrelSource=meshAxis and "posed_mesh_ring_fit" or attachment and "model_attachment" or "authored_axis"
        -- Crossbow's attachment points up, not along its rail. Accept a muzzle's
        -- direction only when it agrees with the model's authored barrel axis.
        if not meshAxis and (next(info) or next(modelInfo)) and barrel:Dot(axis)<math.cos(math.rad(.5)) then barrel=axis barrelSource="authored_axis" end
        if not next(info) and not next(modelInfo) and barrel:Dot(axis)<math.cos(math.rad(45)) then barrel=axis barrelSource="authored_axis" end
        local ignored
        ignored,rotation=WorldToLocal(Vector(),Angle(),Vector(),W.Along(Vector(),barrel,Vector(0,0,1)))
        ignored,wrist=LocalToWorld(Vector(),gripAng,Vector(),rotation)
        origin,rotation=W.Place(gripPos,gripAng,Vector(),wrist)
    end
    local handAngle,gripOffset
    if matrix and handFrame then
        -- The world model's hand bone is a wrist, not the centre of a closed hand.
        -- Anchor its anatomical palm at the controller palm; H uses the same model-local
        -- measurement so its wrist coincides with the gun's hand bone on either hand.
        -- The shown hand is anatomical (forward fingers, up through the thumb),
        -- independently of the weapon's right-authored wrist basis.
        handAngle=Angle()
        local ownGrip=handFrame.grip or handFrame.pos
        local relative=WorldToLocal(ownGrip,Angle(),handFrame.pos,handFrame.ang)
        if not W.Vector(relative) or relative:Length()>4 then relative=Vector() ownGrip=handFrame.pos end
        gripOffset=LocalToWorld(relative,Angle(),Vector(),handAngle)
        -- Both the target and authored anchor belong to this holding hand's stable
        -- grasp. Empty opposite-hand live fingers never participate in placement.
        local localPalm=ownGrip
        do
            local _,inverse=WorldToLocal(Vector(),Angle(),Vector(),handFrame.ang)
            local _,holdingWrist=LocalToWorld(Vector(),inverse,Vector(),handAngle)
            local _,turn=WorldToLocal(Vector(),holdingWrist,Vector(),wrist)
            localPalm=LocalToWorld(localPalm,Angle(),Vector(),turn)
            correction=turn
        end
        gripPos = LocalToWorld(localPalm, Angle(), gripPos, gripAng)
        origin, rotation = W.Place(gripPos, gripAng, gripOffset or Vector(), wrist)
    end
    local actualGrip,gripSource
    if melee then actualGrip=Mesh.Grip(model,points,gripPos) gripSource=actualGrip and "posed_shaft_and_hand_reference"
    else
        actualGrip,gripSource=M.ModelGrip(model)
        if not actualGrip and matrix then gripSource="generic_authored_wrist" end
    end
    if actualGrip then
        gripPos=actualGrip
        origin,rotation=W.Place(gripPos,gripAng,gripOffset or Vector(),wrist)
    end
    local muzzle = attachment and LocalToWorld(attachment.Pos, Angle(), origin, rotation) or Vector(math.Clamp(info.length or modelInfo.length or 0.2,.02,1.5)*40,0,0)
    local meleeTip
    if melee then
        if not points then
            local lo,hi=model:GetModelBounds() points={}
            for _,x in ipairs({lo.x,hi.x}) do for _,y in ipairs({lo.y,hi.y}) do for _,z in ipairs({lo.z,hi.z}) do points[#points+1]=Vector(x,y,z) end end end
        end
        local finish=Mesh.End(points,barrel)
        if finish then meleeTip=LocalToWorld(finish,Angle(),origin,rotation)/40 end
    end
    local fore = info.fore or modelInfo.fore
    if not fore and W.Kind(class)=="swep" and not next(info) and model.GetModelBounds then
        local mins,maxs = model:GetModelBounds()
        if mins and maxs then
            local extent=(math.abs(barrel.x)*(maxs.x-mins.x)+math.abs(barrel.y)*(maxs.y-mins.y)+math.abs(barrel.z)*(maxs.z-mins.z))/40
            if extent>.45 then fore=math.Clamp(extent*.45,.18,.45) end
        end
    end
    M.measureMs=(M.measureMs or 0)+((SysTime and SysTime() or 0)-began)*1000
    return {gripSource=gripSource,barrel=barrel,barrelSource=barrelSource,gripPos=gripPos,gripAng=gripAng,wrist=wrist,correction=correction,bone=bone,muzzle=muzzle/40,
        fore=fore and Vector(fore,0,0)+(handFrame and handFrame.calibrated and Vector() or (gripOffset or Vector())/40) or nil, attachment=id, meleeTip=meleeTip,
        handAngle=handAngle, gripOffset=gripOffset}
end
function M.Pose(active, pos, ang, scale, kick)
    local model, geometry = active.model, active.geometry
    if not IsValid(model) or not geometry then return end
    local ratio = scale/40
    local _, wrist = LocalToWorld(Vector(),geometry.wrist,Vector(),W.GunAngle(ang,-(kick or 0)))
    local target=LocalToWorld((geometry.gripOffset or Vector())*ratio,Angle(),pos,W.GunAngle(ang,-(kick or 0)))
    local origin, rotation = W.Place(geometry.gripPos,geometry.gripAng,target,wrist,ratio)
    model:SetPos(origin) model:SetAngles(rotation)
    model:SetModelScale(ratio,0)
    model:InvalidateBoneCache() model:SetupBones()
    active.pos,active.ang=origin,rotation
    active.grip=target
end
function M.Draw(active)
    local model = active.model
    if not IsValid(model) then return end
    -- Run SWEP draw code only on our model receiver. Code requiring its real weapon's
    -- internals cannot safely be relocated and falls back without touching the weapon.
    local draw = active.ent.DrawWorldModel
    if active.ent:IsScripted() and type(draw)=="function" and not active.customFailed then
        local nativeDraw,raw=model.DrawModel,rawget(model:GetTable(),"DrawModel")
        local drawn=false
        local wrapped=function(self,...) drawn=true return nativeDraw(self,...) end
        model.DrawModel=wrapped
        local ok=pcall(draw,model)
        if model.DrawModel==wrapped then model.DrawModel=raw end
        if ok and drawn then active.customDraws=(active.customDraws or 0)+1 return end
        active.customFailed=true
        if drawn then return end -- an error after drawing must not draw it twice
    end
    model:DrawModel()
end
return M
