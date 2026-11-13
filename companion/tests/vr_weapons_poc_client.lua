-- Fixture only: native timeline, ordinary console server phases, captures and plain receipts.
local phase,lastSend,captured,seen,offAt=nil,-1,{},false,nil
local recorded={}
local savedDominant=GetConVar("nl_vr_dominant"):GetString()
local savedGunAngle=GetConVar("nl_vr_gun_angle"):GetString()
local serial,seenEnt,seenRole,seenFrame,lastTwo,punchSeen=0,nil,nil,0,false,{}
local shotCaptures={}
local effectCapture={}
local ownedModels={}
local cameraUsed=false
local newProjectiles={}
local function wEmit(value)
    local text=util.TableToJSON(value)
    if #text<3000 then print("NLVR_W "..text) return end
    serial=serial+1
    local encoded=util.Base64Encode(text):gsub("%s","")
    local count=math.ceil(#encoded/1600)
    for i=1,count do print("NLVR_W_CHUNK C"..serial.." "..i.."/"..count.." "..encoded:sub((i-1)*1600+1,i*1600)) end
end
NLVR_W_ACK=nil
hook.Add("PreRender","nlvr_w_probe",function()
    if NLVR and nlvr and nlvr.TestState then
        local sample=nlvr.TestState()
        if not sample then return end
        seen=true
        -- The shared probe's flat baseline clears attack buttons. Once VR owns commands,
        -- remove that fixture hook so native weapons receive W's actual user command.
        hook.Remove("CreateMove",ID)
        if not NLVR.wInputProbe then
            NLVR.wInputProbe=true
            local entry=NLVR.Registry:Add({name="weapons_input_probe",order=43,Start=function() end,Stop=function() end})
            entry.ctx.mover(-1000,function(command) command:ClearMovement() command:ClearButtons() end)
            entry.ctx.mover(43,function(command)
                local sample=nlvr.TestState()
                if phase=="melee-walk" and sample and sample.time%4>=1 and sample.time%4<1.2 then
                    command:SetSideMove(200) -- actual predicted/host CMoveData, not pose translation
                end
            end)
            local projectile={crossbow_bolt=true,rpg_missile=true,grenade_ar2=true,prop_combine_ball=true,npc_grenade_frag=true,npc_grenade_bugbait=true}
            entry.ctx.hook("NetworkEntityCreated",function(ent)
                if projectile[ent:GetClass()] then
                    local src,ang=NLVR.Weapon.Muzzle()
                    newProjectiles[ent]={phase=phase,class=ent:GetClass()}
                    wEmit({kind="projectile-first-network",phase=phase,class=ent:GetClass(),pos=ent:GetPos(),visible=not ent:GetNoDraw(),
                        eye=LocalPlayer():EyePos(),muzzle=src,angles=ang})
                end
            end)
            entry.ctx.On("frame",function()
                for ent,info in pairs(newProjectiles) do
                    if not IsValid(ent) then newProjectiles[ent]=nil
                    elseif not ent:GetNoDraw() then
                        wEmit({kind="projectile-first-visible",phase=info.phase,class=info.class,pos=ent:GetPos()})
                        newProjectiles[ent]=nil
                    end
                end
            end)
            entry.ctx.mover(10000,function(command)
                if phase and phase:match("^fore%-") and NLVR.Input.main.trigger then
                    wEmit({kind="burst-command",phase=phase,attack=command:KeyDown(IN_ATTACK),
                        grip=NLVR.Input.off.grip,two=NLVR.Weapon.Active and NLVR.Weapon.Active.twoHanded,
                        ready=NLVR.Debug.weapons and NLVR.Debug.weapons.host_ready})
                end
            end)
            entry.ctx.On("weapon_fired",function()
                if phase and not shotCaptures[phase] and (phase:match("pistol") or phase:match("^melee")) then
                    effectCapture[phase]=FrameNumber()+1
                end
            end)
            local previousEffect=util.Effect
            local function effect(name,data,...)
                if phase and (name=="MuzzleFlash" or name=="MuzzleEffect") then
                    wEmit({kind="client-effect",phase=phase,name=name,origin=data:GetOrigin(),angles=data:GetAngles(),scale=data:GetScale()})
                end
                return previousEffect(name,data,...)
            end
            util.Effect=effect
            entry.ctx.cleanup(function() if util.Effect==effect then util.Effect=previousEffect end end)
        end
        if CONFIG.weapons_camera_debug and not NLVR.wCameraProbe then
            NLVR.wCameraProbe=true
            local entry=NLVR.Registry:Add({name="weapons_camera_probe",order=45,Start=function() end,Stop=function() end})
            local inspected=false local overrides={}
            entry.ctx.On("frame",function()
                local time=nlvr.TestState()
                if inspected or not time or time.time<1 or not RemixMaterial or not RemixConfig then return end
                inspected=true
                local hashes=RemixMaterial.GetAllTextureHashes("maxofs2d/models/camera") or {}
                local function key(h) return tostring(h):lower():gsub("^0x",""):gsub("^0+","") end
                local set={} for _,h in ipairs(hashes) do set[key(h)]=true end
                local matched={}
                for _,option in ipairs({"rtx.ignoreTextures","rtx.uiTextures","rtx.playerModelTextures","rtx.hideInstanceTextures","rtx.skyBoxTextures"}) do
                    local before=RemixConfig.GetConfigVariable(option)
                    local kept,removed={},{}
                    for value in tostring(before):gmatch("[^,]+") do
                        local token=value:match("^%s*(.-)%s*$")
                        if set[key(token)] then removed[#removed+1]=token else kept[#kept+1]=token end
                    end
                    if option=="rtx.ignoreTextures" then
                        for _,hash in ipairs(hashes) do kept[#kept+1]="-"..hash removed[#removed+1]="inherited:"..hash end
                    end
                    if #removed>0 then
                        RemixConfig.SetConfigVariable(option,table.concat(kept,", "))
                        overrides[option]={before=before,applied=RemixConfig.GetConfigVariable(option)}
                    end
                    matched[option]={removed=removed,before=before}
                end
                local flags={} for _,hash in ipairs(hashes) do flags[hash]=RemixMaterial.GetHashCategory(hash) end
                wEmit({kind="camera-hashes",hashes=hashes,matched=matched,flags=flags})
            end)
            entry.ctx.cleanup(function()
                for option,state in pairs(overrides) do if RemixConfig.GetConfigVariable(option)==state.applied then
                    RemixConfig.SetConfigVariable(option,state.before)
                    wEmit({kind="camera-ignore-restored",option=option,value=RemixConfig.GetConfigVariable(option)})
                end end
            end)
            local models={}
            local cameraMesh local variants={} local meshParts=util.GetModelMeshes("models/maxofs2d/camera.mdl",0,0)
            if meshParts and meshParts[1] then
                cameraMesh=Mesh(Material("models/debug/debugwhite")) cameraMesh:BuildFromTriangles(meshParts[1].triangles)
                entry.ctx.cleanup(function() cameraMesh:Destroy() end)
                local original=Material(meshParts[1].material)
                local texture=original:GetTexture("$basetexture")
                for i,shader in ipairs({"VertexLitGeneric","UnlitGeneric"}) do
                    local material=CreateMaterial("nlvr_w_camera_probe_"..i,shader,{["$basetexture"]=texture and texture:GetName() or "models/debug/debugwhite",["$model"]="1"})
                    if texture then material:SetTexture("$basetexture",texture) end
                    local mesh=Mesh(material) mesh:BuildFromTriangles(meshParts[1].triangles)
                    variants[i]={mesh=mesh,material=material}
                    entry.ctx.cleanup(function() mesh:Destroy() end)
                end
            end
            for i=1,2 do
                local m=ClientsideModel("models/maxofs2d/camera.mdl",RENDERGROUP_OPAQUE)
                m:SetNoDraw(true) if i==2 then m:SetMaterial("models/debug/debugwhite") end
                models[i]=m
            end
            entry.ctx.cleanup(function() for _,m in ipairs(models) do if IsValid(m) then m:Remove() end end end)
            entry.ctx.hook("PreDrawTranslucentRenderables",function(depth,sky)
                if depth or sky then return end
                local head=NLVR.Pose.head if not head or not head.valid then return end
                for i,m in ipairs(models) do
                    m:SetPos(head.pos+head.ang:Forward()*30+head.ang:Right()*(i==1 and -10 or 10)-Vector(0,0,4))
                    m:SetAngles(Angle(0,head.ang.y+180,0)) m:SetupBones() m:DrawModel()
                end
                if cameraMesh then
                    local matrix=Matrix() matrix:SetTranslation(head.pos+head.ang:Forward()*30+Vector(0,0,6))
                    matrix:SetAngles(Angle(0,head.ang.y+180,0))
                    cam.PushModelMatrix(matrix) render.SetMaterial(Material("models/debug/debugwhite")) cameraMesh:Draw() cam.PopModelMatrix()
                end
                for i,part in ipairs(variants) do
                    local matrix=Matrix() matrix:SetTranslation(head.pos+head.ang:Forward()*30+head.ang:Right()*(i==1 and -10 or 10)+Vector(0,0,6))
                    matrix:SetAngles(Angle(0,head.ang.y+180,0))
                    cam.PushModelMatrix(matrix) render.SetMaterial(part.material) part.mesh:Draw() cam.PopModelMatrix()
                end
            end)
            local material=Material("maxofs2d/models/camera")
            local m=models[1] m:SetupBones() local lo,hi=m:GetModelBounds() local bones={}
            for i=0,m:GetBoneCount()-1 do local b=m:GetBoneMatrix(i) bones[#bones+1]={name=m:GetBoneName(i),pos=b and b:GetTranslation(),scale=b and b:GetScale()} end
            local texture=material:GetTexture("$basetexture")
            wEmit({kind="camera-diagnostic",bounds={lo,hi},bones=bones,materials=m:GetMaterials(),groups=m:GetBodyGroups(),
                texture=texture and texture:GetName(),texture_error=texture and texture:IsError(),
                mesh_parts=meshParts and #meshParts,vertices=meshParts and meshParts[1] and #meshParts[1].triangles,
                shader=material:GetShader(),error=material:IsError(),kv=material:GetKeyValues()})
        end
        local current=LocalPlayer():GetActiveWeapon()
        local shown=NLVR.Hand[NLVR.Input.mainHand]
        local ready=LocalPlayer():Alive() and shown and shown.shown.valid
        if not ready then seenEnt,seenRole=nil,nil
        elseif current~=seenEnt or seenRole~=NLVR.Input.mainHand then seenEnt,seenRole,seenFrame=current,NLVR.Input.mainHand,FrameNumber() end
        local active=NLVR.Weapon and NLVR.Weapon.Active
        if active and active.cameraOverride then cameraUsed=true end
        if active and IsValid(active.model) then ownedModels[active.model]=true end
        if ready and active and active.valid and active.ent==seenEnt and not active.wProbeSwitch then
            active.wProbeSwitch=true
            wEmit({kind="switch",class=active.class,frames=FrameNumber()-seenFrame,phase=phase,time=sample.time,ready=true})
        end
        if lastTwo and active and not active.twoHanded then
            wEmit({kind="foregrip-release",class=active.class,phase=phase,ray=active.muzzle,controller=NLVR.Pose[active.hand]})
        end
        lastTwo=active and active.twoHanded or false
        local punch=LocalPlayer():GetViewPunchAngles()
        if phase and not punchSeen[phase] and math.abs(punch.p)+math.abs(punch.y)+math.abs(punch.r)>.1 then
            punchSeen[phase]=true
            wEmit({kind="punch",phase=phase,punch=punch,camera=lastCamera,head=NLVR.Pose.head,
                aim=NLVR.Debug.weapons and NLVR.Debug.weapons.aim_ang})
        end
        local wd=NLVR.Debug.weapons
        if phase and phase:match("^melee%-") and NLVR_W_ACK==phase then
            local label=sample.time%4>=3.9 and "decal-"..phase or sample.time%4>=.75 and sample.time%4<.95 and "before-"..phase
            if label and not captured[label] and nlvr.Capture(label,15) then captured[label]=true end
        end
        if phase and effectCapture[phase] and FrameNumber()>=effectCapture[phase] and not shotCaptures[phase] then
            if nlvr.Capture("effects-"..phase,15) then shotCaptures[phase]=true end
        end
        local slot=math.floor(sample.time/4)
        local nextPhase=CONFIG.weapons_phases[slot+1]
        if nextPhase and (phase~=nextPhase or NLVR_W_ACK~=nextPhase and sample.time-lastSend>.25) then
            phase,lastSend=nextPhase,sample.time
            RunConsoleCommand("nlvr_w_phase",phase)
        end
        if phase and sample.time%4>=2.65 and not captured[phase] and NLVR_W_ACK==phase then
            local label="weapon-"..phase
            local request=nlvr.Capture(label,15)
            if request then
                captured[phase]=true
                local api=NLVR.Weapon local a=api and api.Active
                local g=NLVR.Debug.weapons
                local pos,ang,origin,dir
                if api then pos,ang=api.Muzzle() origin,dir=api.Ray() end
                local m=a and a.model local grip,attachment
                if IsValid(m) then
                    m:SetupBones()
                    local id=m:LookupBone("ValveBiped.Bip01_R_Hand")
                    local matrix=id and m:GetBoneMatrix(id)
                    if matrix then grip={pos=matrix:GetTranslation(),ang=matrix:GetAngles()} end
                    id=m:LookupAttachment("muzzle") if id and id>0 then attachment=m:GetAttachment(id) end
                end
                local hand=a and NLVR.Hand[a.hand]
                wEmit({kind="client",phase=phase,time=sample.time,label=label,request=request,
                    debug=g,model_decals=GetConVar("r_drawmodeldecals"):GetString(),active=a and {class=a.class,kind=a.kind,hand=a.hand,twoHanded=a.twoHanded,valid=a.valid},
                    grip=grip,attachment=attachment,shown=hand and hand.shown,main=NLVR.Input.mainHand,
                    controller=a and NLVR.Pose[a.hand],gun_angle=GetConVar("nl_vr_gun_angle"):GetFloat(),
                    ray={pos=origin,dir=dir},muzzle={pos=pos,ang=ang},head=NLVR.Pose.head,
                    punch=LocalPlayer():GetViewPunchAngles(),hands=NLVR.Debug.hands,
                    fore_hand=a and NLVR.Hand[a.hand=="right" and "left" or "right"]})
                RunConsoleCommand("nlvr_w_measure",phase)
            end
        end
    elseif seen then
        offAt=offAt or RealTime()
        if RealTime()-offAt>1 then
            local models,live=0,0
            for model in pairs(ownedModels) do models=models+1 if IsValid(model) then live=live+1 end end
            print("NLVR_W "..util.TableToJSON({kind="client-off",global=NLVR~=nil,models_seen=models,models_live=live}))
            if cameraUsed then
                local value=RemixConfig.GetConfigVariable("rtx.ignoreTextures")
                wEmit({kind="camera-scope",cleared=not tostring(value):lower():find("-0x35d7392325ed05a9",1,true),value=value})
            end
            RunConsoleCommand("nlvr_w_done")
            RunConsoleCommand("nl_vr_dominant",savedDominant)
            RunConsoleCommand("nl_vr_gun_angle",savedGunAngle)
            local untilTime=RealTime()+1
            hook.Add("Think","nlvr_w_settings_restore",function()
                local dominant=GetConVar("nl_vr_dominant"):GetString()
                local gunAngle=GetConVar("nl_vr_gun_angle"):GetString()
                local restored=dominant==savedDominant and gunAngle==savedGunAngle
                if restored or RealTime()>=untilTime then
                    wEmit({kind="fixture-settings",restored=restored,dominant=dominant,gun_angle=gunAngle,
                        before={dominant=savedDominant,gun_angle=savedGunAngle}})
                    hook.Remove("Think","nlvr_w_settings_restore")
                end
            end)
            NLVR_W_ACK=nil hook.Remove("PreRender","nlvr_w_probe")
        end
    end
end)
