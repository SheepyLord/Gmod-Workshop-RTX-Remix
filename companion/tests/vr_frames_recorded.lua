-- Test-only SDK reader. Exercises the production read/cache path, not BeginFrame bones.
return function(config,native)
    local poses=config.frames_source_poses
    local sequence={"open","grip_limit","fist","with_controller"}
    local pools={} local stats={calls=0,bone_arrays=0,kinds={},hands={}}
    local function phase_at(time)
        for i,p in ipairs(config.frames_plan or {}) do
            if time>=p.start and time<p.start+p.duration then return p,time-p.start end
        end
        local p=config.frames_plan and config.frames_plan[#config.frames_plan]
        return p,p and p.duration or 0
    end
    local function read(side,kind,destination,time)
        stats.calls=stats.calls+1 stats.kinds[kind]=(stats.kinds[kind] or 0)+1
        stats.hands[side]=(stats.hands[side] or 0)+1
        local state=native.TestState() time=time or (state and state.time) or 0
        local plan,offset=phase_at(time)
        local quarter=(plan and plan.duration or 7)/4
        local part=math.min(3,math.floor(offset/quarter))
        local fraction=part==3 and 0 or math.max(0,(offset/quarter-part-.2)/.8)
        local from,to=kind,kind
        if kind=="with_controller" then from,to=sequence[part+1],sequence[math.min(4,part+2)] else fraction=0 end
        local a=poses[side] and poses[side][from]
        local b=poses[side] and poses[side][to]
        pools[side]=pools[side] or {}
        local out=destination or pools[side][kind] or {}
        pools[side][kind]=out
        out.valid=a and b and a.valid and b.valid or false
        out.error=out.valid and 0 or 13 out.source="recorded_"..kind out.recorded=true
        out.sample_time=time out.pose_from=from out.pose_to=to out.blend=fraction
        out.bones=out.bones or {}
        if out.valid then for i=1,31 do
            local p=out.bones[i]
            if not p then p={} out.bones[i]=p stats.bone_arrays=stats.bone_arrays+1 end
            for j=1,6 do p[j]=a.bones[i][j]+(b.bones[i][j]-a.bones[i][j])*fraction end
        end end
        return out
    end
    return read,function() return stats end
end
