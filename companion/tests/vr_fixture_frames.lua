-- Test-only desired-palm <-> raw-pose transforms. No identity controller substitution.
local F={}
function F.New(profiles)
    local P={}
    for side,data in pairs(profiles) do
        local a=data.aim.ang
        local _,inverse=WorldToLocal(Vector(),Angle(),Vector(),Angle(a[1],a[2],a[3]))
        P[side]={data=data,palm=Vector(unpack(data.hand.pos)),aim=Angle(unpack(a)),inverse=inverse}
    end
    local self={}
    function self.Encode(pose,side)
        local p=P[side]
        local _,ang=LocalToWorld(Vector(),p.inverse,Vector(),pose.ang)
        local offset=LocalToWorld(p.palm,Angle(),Vector(),ang)
        pose.pos,pose.ang=pose.pos-offset,ang
        return pose
    end
    function self.Decode(pose,side)
        local p=P[side]
        local pos=LocalToWorld(p.palm,Angle(),pose.pos,pose.ang)
        local _,ang=LocalToWorld(Vector(),p.aim,Vector(),pose.ang)
        pose.pos,pose.ang=pos,ang
        return pose
    end
    function self.Aim(pose,side,target)
        local p=P[side]
        -- A natural palm and SteamVR's laser tip have different origins. Converge
        -- the scripted pose on the actual tip, without moving the requested palm.
        for i=1,6 do
            self.Encode(pose,side)
            local tip=LocalToWorld(Vector(unpack(p.data.aim.pos)),Angle(),pose.pos,pose.ang)
            self.Decode(pose,side)
            pose.ang=(target-tip):Angle()
        end
        return self.Encode(pose,side)
    end
    function self.Components(frame)
        frame.controllers_live=frame.controllers
        local out={}
        for side,p in pairs(P) do
            local live=frame.controllers and frame.controllers[side]
            if live and live.valid then out[side]=live
            else
                local data={valid=true,skeleton=false,revision=1,device=4294967295,model=p.data.model,
                    source="recorded_index_controllers_absent",detail="scripted test; physical controllers off"}
                for _,key in ipairs({"aim","hand","wrist"}) do
                    local part=p.data[key]
                    data[key]={valid=true,pos=Vector(unpack(part.pos)),ang=Angle(unpack(part.ang))}
                end
                out[side]=data
            end
        end
        frame.controllers=out
    end
    return self
end
return F
