-- One composition point for predicted raw device, pointing and anatomical hand frames.
local Frames = {}
-- Measured from the central body.obj handle cross-sections z=.085..145 m,
-- excluding the ring (strap side beyond |x|=.025). The diagnostic remeasures
-- the installed meshes and keeps their hashes/section residuals.
function Frames.Handle(data)
    if not data or not data.valid or not data.aim or data.aim.valid==false or not data.hand or data.hand.valid==false then return end
    local model=(data.model or ""):lower()
    if not model:find("valve_controller_knu_1_0_",1,true) then return end
    local left=model:find("_left",1,true)~=nil
    local axis=Vector(left and .025061475 or -.025061060,-.280183,.959619)
    local pos=Vector(-.115,left and .000745696 or -.000745717,left and -.014331943 or -.013421153)
    local sourceAxis=Vector(-axis.z,-axis.x,axis.y)
    return {valid=true,pos=pos,ang=sourceAxis:Angle(),axis=sourceAxis,source="index_body_handle_sections",correction=left and Vector(-.0005066,-.0115679,.0027699) or Vector(-.0007515,.0115742,.0036092)}
end
function Frames.New(core)
    local self, logged = {}, {}
    local function cross(a, b) return Vector(a.y*b.z-a.z*b.y, a.z*b.x-a.x*b.z, a.x*b.y-a.y*b.x) end
    local function compose(raw, localPose)
        local pos, ang = LocalToWorld(localPose.pos * core.Space.scale, localPose.ang, raw.pos, raw.ang)
        return {valid = raw.valid, pos = pos, ang = ang, angvel = raw.angvel,
            vel = raw.vel + cross(raw.angvel, pos - raw.pos)}
    end
    function self.Apply()
        core.Debug.frames = {}
        for _, hand in ipairs({"left", "right"}) do
            local pose = core.Pose[hand]
            local data = core.Frame and core.Frame.controllers and core.Frame.controllers[hand]
            -- Keep .raw as the native tracking pose for existing consumers; .device is world space.
            local device = {valid=pose.valid, pos=pose.pos, ang=pose.ang, vel=pose.vel, angvel=pose.angvel}
            pose.device = device
            if data and data.valid then
                local handle=Frames.Handle(data)
                local localHand=handle and {pos=handle.pos,ang=data.aim.ang} or data.hand
                local palm = compose(device, localHand)
                pose.aim, pose.wrist = compose(device, data.aim), compose(device, data.wrist)
                pose.handle=handle and compose(device,handle) or nil
                pose.pos, pose.ang, pose.vel = palm.pos, palm.ang, palm.vel
            else
                pose.aim=data and data.aim and data.aim.valid and compose(device,data.aim) or device
                if data and data.aim and data.aim.valid then pose.ang=pose.aim.ang end
                pose.wrist=data and data.wrist and data.wrist.valid and compose(device,data.wrist) or device
                pose.handle=nil
            end
            if data and data.revision ~= logged[hand] then
                logged[hand] = data.revision
                MsgN("[nativeloader] VR " .. hand .. " frames: " .. (data.model or "unknown") .. " / " .. (data.source or "raw") ..
                    ((data.detail or "") ~= "" and (" (" .. data.detail .. ")") or ""))
            end
            core.Debug.frames[hand] = {source=data and data.source or "raw", model=data and data.model or "",
                revision=data and data.revision or 0, valid=data and data.valid or false, skeleton=data and data.skeleton or false,
                raw=device, aim=pose.aim, hand={pos=pose.pos,ang=pose.ang}, wrist=pose.wrist,
                local_aim=data and data.aim, local_hand=data and data.hand, local_wrist=data and data.wrist,
                skeleton_finger=data and data.skeleton_finger, skeleton_normal=data and data.skeleton_normal}
            core.Debug.frames[hand].handle=pose.handle
        end
    end
    return self
end
return Frames
