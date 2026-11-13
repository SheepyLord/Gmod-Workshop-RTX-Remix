-- Read actual engine bone caches after H submitted its pose, not its commanded Euler fields.
local W={}
local function read(model,side)
    if not IsValid(model) then return end
    local prefix="ValveBiped.Bip01_"..(side=="left" and "L" or "R").."_"
    local id=model:LookupBone(prefix.."Hand") local parent=id and model:GetBoneMatrix(id)
    if not parent then return end
    local values={}
    for finger=0,4 do
        local bone=model:LookupBone(prefix.."Finger"..finger)
        local matrix=bone and model:GetBoneMatrix(bone)
        if not matrix then return end
        local _,angle=WorldToLocal(Vector(),matrix:GetAngles(),Vector(),parent:GetAngles())
        values[#values+1]={angle.p,angle.y,angle.r}
    end
    return {model=model:GetModel(),angles=values}
end
function W.New()
    local self={hands={}}
    function self.Observe(side,model,time,frame,reference)
        local pose=read(model,side) if not pose then return end
        pose.time,pose.frame=time,frame
        local hand=self.hands[side] or {} self.hands[side]=hand
        if reference then hand.reference=pose else hand.current=pose end
    end
    function self.Snapshot(side)
        local h=self.hands[side] local a,b=h and h.reference,h and h.current
        if not a or not b then return end
        return {method="engine_bone_parent_rotations",reference=a.angles,current=b.angles,
            reference_model=a.model,current_model=b.model,reference_frame=a.frame,current_frame=b.frame,
            reference_time=a.time,current_time=b.time}
    end
    return self
end
return W
