-- SPDX-License-Identifier: MIT
-- Task R's controlled geometry; appended inside the accepted session probe's lexical scope.
local case=CONFIG.v2r_case
if case=="barrel" or case==nil then return end
local scale=GetConVar("nl_vr_scale"):GetFloat()
local models={}
if rCleanupTasks then rCleanupTasks[#rCleanupTasks+1]=function()
    hook.Remove("PreRender","v2r.held_prop") hook.Remove("PreRender","v2r.window")
    -- The driver owns the game process. Leave static scene entities to its normal quit;
    -- eager removal here can race Source's queued draws immediately after VR restoration.
end end
local function box(position,metres,colour,rotation)
    local e=ClientsideModel("models/hunter/blocks/cube025x025x025.mdl",RENDERGROUP_OPAQUE)
    assert(IsValid(e),"stock cube unavailable")
    local lo,hi=e:GetModelBounds() local size=hi-lo
    local transform=Matrix() transform:Scale(Vector(metres.x*scale/size.x,metres.y*scale/size.y,metres.z*scale/size.z))
    e:EnableMatrix("RenderMultiply",transform) e:SetAngles(rotation or angles) e:SetPos(position)
    e:SetMaterial("models/debug/debugwhite") e:SetColor(colour) e:DrawShadow(false)
    models[#models+1]=e return e
end
if case=="ghost" then
    if IsValid(barrel) then barrel:SetNoDraw(true) end
    box(origin+angles:Forward()*8*scale,Vector(.05,5,4),Color(230,230,230))
    for i=-7,7 do
        box(origin+angles:Forward()*1.5*scale+angles:Right()*i*.025*scale,
            Vector(.003,.003,.35),Color(15,15,15))
    end
    for i=0,31 do
        local theta=i*math.pi*2/32
        box(origin+angles:Forward()*1.5*scale+angles:Right()*(.45+.12*math.cos(theta))*scale+Vector(0,0,.12*math.sin(theta)*scale),
            Vector(.003,.003,2*math.pi*.12/32*1.05),Color(15,15,15),Angle(0,angles.y,-i*360/32))
    end
    emit("v2r-fixture",{case=case,depth_metres=1.5,strand_width_metres=.003,wall_metres=8})
elseif case=="near" then
    if IsValid(barrel) then barrel:SetNoDraw(true) end
    local meshLo,meshHi=Vector(math.huge,math.huge,math.huge),Vector(-math.huge,-math.huge,-math.huge)
    for _,part in ipairs(util.GetModelMeshes("models/hunter/blocks/cube025x025x025.mdl",0,0) or {}) do
        for _,vertex in ipairs(part.triangles or {}) do
            local v=vertex.pos
            meshLo=Vector(math.min(meshLo.x,v.x),math.min(meshLo.y,v.y),math.min(meshLo.z,v.z))
            meshHi=Vector(math.max(meshHi.x,v.x),math.max(meshHi.y,v.y),math.max(meshHi.z,v.z))
        end
    end
    local held=box(origin+angles:Forward()*CONFIG.v2r_near*scale,Vector(.06,.08,.10),Color(190,35,35))
    local modelLo,modelHi=held:GetModelBounds()
    emit("v2r-mesh",{mesh_lo=meshLo,mesh_hi=meshHi,bounds_lo=modelLo,bounds_hi=modelHi,units_per_metre=scale})
    hook.Add("PreRender","v2r.held_prop",function()
        if not lastFrame or not lastFrame.left or not lastFrame.left.valid then return end
        local feet=origin-Vector(0,0,64)
        local p,a=LocalToWorld(lastFrame.left.pos*scale,lastFrame.left.ang,feet,Angle(0,angles.y,0))
        held:SetPos(p) held:SetAngles(a)
    end)
    emit("v2r-fixture",{case=case,depth_metres=CONFIG.v2r_near,dimensions_metres={.06,.08,.10}})
elseif case=="window" then
    local handle
    hook.Add("PreRender","v2r.window",function()
        if NativeLoaderVR.state~="running" or handle then return end
        local err
        handle,err=nlvr.OverlayCreate("v2r.window","V2 runtime window") assert(handle,err)
        local ok,message=nlvr.OverlayWindow(handle,true) assert(ok,message)
        assert(nlvr.OverlayAttach(handle,"head",Vector(0,0,-1),Angle(0,0,0),1))
        assert(nlvr.OverlayShow(handle,true))
        gui.ActivateGameUI()
        emit("v2r-window",{handle=handle})
    end)
end
