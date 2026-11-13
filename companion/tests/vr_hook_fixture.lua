-- Original engine-hook test double. Contract: TeamUlysses hook priority documentation
-- and API behaviours described in vr_hook_fixture.lua.md; no ULib code is included.
local Fixture={}
function Fixture.New(mode,compat,target)
    mode=mode or "ulib"
    compat=compat or {}
    local H,levels=target or {},{}
    HOOK_MONITOR_HIGH,HOOK_HIGH,HOOK_NORMAL,HOOK_LOW,HOOK_MONITOR_LOW=-2,-1,0,1,2
    function H.GetTable()
        if mode=="stock" then return compat end
        local copy={} for event,list in pairs(compat) do
            copy[event]={} for id,fn in pairs(list) do copy[event][id]=fn end
        end return copy
    end
    if mode=="ulib" then H.GetULibTable=function() return levels end end
    function H.Remove(event,id)
        if mode=="ulib" then
            if not levels[event] then return end
            for priority=-2,2 do levels[event][priority][id]=nil end
            -- Deliberately no nil guard: a detached/deleted backward table is a bug.
            compat[event][id]=nil
        elseif compat[event] then compat[event][id]=nil end
    end
    function H.Add(event,id,fn,priority)
        if type(event)~="string" or type(fn)~="function" then return end
        priority=priority or 0
        if type(priority)~="number" then return end
        priority=math.max(-2,math.min(2,math.floor(priority)))
        H.Remove(event,id)
        if mode=="ulib" and not levels[event] then
            levels[event]={} for i=-2,2 do levels[event][i]={} end
            compat[event]={}
        end
        compat[event]=compat[event] or {} compat[event][id]=fn
        if mode=="ulib" then levels[event][priority][id]={fn=fn,isstring=type(id)=="string"} end
    end
    local function invoke(id,fn,...)
        if type(id)=="string" then return fn(...) end
        if IsValid(id) then return fn(id,...) end
    end
    local function dispatch(event,list,entries,monitor,...)
        local visited={}
        local function one(id,value,...)
            visited[id]=true
            if type(id)~="string" and not IsValid(id) then H.Remove(event,id) return end
            local a,b,c,d,e,f=invoke(id,entries and value.fn or value,...)
            if not monitor then return a,b,c,d,e,f end
        end
        -- Offline-only adversarial ordering within one priority. Production uses pairs.
        for _,id in ipairs(H.order or {}) do
            local value=rawget(list,id)
            if value then local a,b,c,d,e,f=one(id,value,...) if a~=nil then return a,b,c,d,e,f end end
        end
        for id,value in pairs(list) do
            if not visited[id] then local a,b,c,d,e,f=one(id,value,...) if a~=nil then return a,b,c,d,e,f end end
        end
    end
    function H.Call(event,gm,...)
        if mode=="ulib" then
            for i=-2,2 do
                local a,b,c,d,e,f=dispatch(event,levels[event] and levels[event][i] or {},true,i==-2 or i==2,...)
                if a~=nil then return a,b,c,d,e,f end
            end
        else
            local a,b,c,d,e,f=dispatch(event,compat[event] or {},false,false,...)
            if a~=nil then return a,b,c,d,e,f end
        end
        if gm and gm[event] then return gm[event](gm,...) end
    end
    function H.Run(event,...)
        return H.Call(event,gmod and gmod.GetGamemode and gmod.GetGamemode() or nil,...)
    end
    if mode=="ulib" then
        local initial={} for event,list in pairs(compat) do
            initial[event]={} for id,fn in pairs(list) do initial[event][id]=fn end
        end
        for event,list in pairs(initial) do for id,fn in pairs(list) do H.Add(event,id,fn) end end
    end
    return H,compat,levels
end
return Fixture
