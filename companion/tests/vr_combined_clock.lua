-- Private functional replay only. Temporal acceptance always uses the native wall clock.
local Clock={}
function Clock.New(options)
    local native,steps=options.Native,options.Steps
    local oldBegin,oldActions,oldState=native.BeginFrame,native.Actions,native.TestState
    local now,lastEngine,lastWall,previousPause,stats=nil,nil,nil,false,{excluded_wall_seconds=0}
    local index=1
    local function sample(frame)
        while index<#steps and steps[index+1].time<=now do index=index+1 end
        local a,b=steps[index],steps[math.min(index+1,#steps)]
        local dt=b.time-a.time local fraction=dt>0 and math.min(1,math.max(0,(now-a.time)/dt)) or 0
        local function lerp(x,y) return x+(y-x)*fraction end
        for _,name in ipairs({"hmd","left","right"}) do
            local p,q=a[name],b[name] local angle,rate={},{}
            for axis=1,3 do
                local delta=(q.ang[axis]-p.ang[axis]+180)%360-180
                angle[axis]=p.ang[axis]+delta*fraction rate[axis]=dt>0 and math.rad(delta)/dt or 0
            end
            frame[name]={valid=true,pos=Vector(lerp(p.pos[1],q.pos[1]),lerp(p.pos[2],q.pos[2]),lerp(p.pos[3],q.pos[3])),
                ang=Angle(unpack(angle)),vel=dt>0 and Vector(q.pos[1]-p.pos[1],q.pos[2]-p.pos[2],q.pos[3]-p.pos[3])/dt or Vector(),
                angvel=Vector(rate[3],rate[1],rate[2])}
        end
        frame.devices={frame.hmd,frame.left,frame.right}
        local actions={}
        for name,value in pairs(a.actions or {}) do
            if type(value)=="boolean" then actions[name]={active=true,state=value}
            elseif type(value)=="number" then
                local nextValue=(b.actions or {})[name]
                actions[name]={active=true,x=type(nextValue)=="number" and lerp(value,nextValue) or value,y=0}
            elseif value[1] then
                local nextValue=(b.actions or {})[name] or value
                actions[name]={active=true,x=lerp(value[1],nextValue[1]),y=lerp(value[2],nextValue[2])}
            elseif value.curls or value.splay then
                local out={active=true} local nextValue=(b.actions or {})[name] or value
                for _,key in ipairs({"curls","splay"}) do
                    out[key]={}
                    for i,n in ipairs(value[key] or {}) do out[key][i]=lerp(n,(nextValue[key] or {})[i] or n) end
                end
                actions[name]=out
            else actions[name]=value end
        end
        return actions
    end
    local actions
    native.BeginFrame=function(...)
        local frame,detail=oldBegin(...)
        if not frame then return frame,detail end
        local state=oldState() local engine,wall=options.EngineTime(),options.WallTime()
        local paused=options.Paused()
        local entered=not now and state and state.time>=options.BeginAt
        if entered then now=state.time end
        if now then
            if lastEngine and not entered then
                local elapsed=math.max(0,engine-lastEngine) local wallElapsed=math.max(0,wall-lastWall)
                -- Intentional single-player menu pauses still permit room-scale movement.
                -- Disk/GPU readback stalls during live gameplay do not consume input windows.
                if paused and previousPause then elapsed=wallElapsed end
                now=now+elapsed stats.excluded_wall_seconds=stats.excluded_wall_seconds+wallElapsed-elapsed
            end
            actions=sample(frame)
        end
        lastEngine,lastWall,previousPause=engine,wall,paused
        return frame,detail
    end
    native.Actions=function(...) if now then return actions end return oldActions(...) end
    native.TestState=function(...)
        local state=oldState(...)
        if state and now then
            state.native_time=state.time state.time=now state.step=index state.ended=now>=steps[#steps].time
            state.clock="Source game time; wall time while deliberately paused"
        end
        return state
    end
    return {Stats=function() return stats end,Stop=function()
        native.BeginFrame,native.Actions,native.TestState=oldBegin,oldActions,oldState
    end}
end
return Clock
