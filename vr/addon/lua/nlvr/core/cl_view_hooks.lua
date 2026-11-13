-- Exclusive camera ownership for stock hooks and ULib's separate priority registry.
local View={}
function View.Take(ctx,callback)
    local lib=hook
    local add,remove,call,get=lib.Add,lib.Remove,lib.Call,lib.GetTable
    local run=lib.Run
    local getULib=lib.GetULibTable
    local busy=false
    ctx.hook("CalcView",function(...)
        if busy then return false end
        busy=true local ok,value=pcall(callback,...) busy=false
        if not ok then error(value,0) end
        return value
    end)
    local plain=get()
    local actual=type(getULib)=="function" and getULib() or nil
    local heldLevels=type(actual)=="table" and actual.CalcView
    if type(heldLevels)~="table" then heldLevels=nil end
    if heldLevels then for n=-2,2 do if type(heldLevels[n])~="table" then heldLevels=nil break end end end
    do
        local event,id="nlvr.core.view_registry_probe","nlvr.core.probe"
        local first,second={},{}
        add(event,id,function() return first end)
        local registry=get() local saved=registry[event]
        local savedLevels=heldLevels and actual[event]
        registry[event]={[id]=function() return second end}
        if heldLevels then
            local probe={} for n=-2,2 do probe[n]={} end
            probe[-1][id]={fn=function() return second end,isstring=true}
            actual[event]=probe
        end
        local leaked=false
        local gm={[event]=function() leaked=true return first end}
        local ok,value=pcall(call,event,gm)
        if heldLevels then actual[event]=savedLevels end
        registry[event]=saved remove(event,id)
        if not ok or value~=second or leaked then return nil,"Unsupported CalcView hook library; VR camera cannot be isolated" end
    end
    local fallback="nlvr."..ctx.name
    local held=plain.CalcView or {}
    local dispatch=held[fallback]
    if type(dispatch)~="function" and heldLevels then
        for n=-2,2 do local entry=heldLevels[n][fallback] if entry then dispatch=entry.fn end end
    end
    if type(dispatch)~="function" then return nil,"CalcView callback registration unavailable" end
    local id="nlvr.core.view.dispatch"
    local owned=setmetatable({},{__index=held,__newindex=function(_,key,value) held[key]=value end})
    rawset(owned,id,dispatch)
    local ownedLevels,levelTables,ownedEntry
    if heldLevels then
        ownedLevels={} levelTables={}
        for n=-2,2 do
            local list=heldLevels[n]
            ownedLevels[n]=setmetatable({},{__index=list,__newindex=function(_,key,value) list[key]=value end})
            levelTables[n]=ownedLevels[n]
        end
        ownedEntry={fn=dispatch,isstring=true}
        rawset(ownedLevels[-1],id,ownedEntry)
        actual.CalcView=ownedLevels
    end
    plain.CalcView=owned
    local stopped=false
    local self={}
    function self.Check()
        if stopped or hook~=lib or lib.Add~=add or lib.Remove~=remove or lib.Call~=call or lib.Run~=run or lib.GetTable~=get or lib.GetULibTable~=getULib then return false end
        if rawget(owned,id)~=dispatch then return false end
        if ownedLevels then
            if getULib()~=actual or actual.CalcView~=ownedLevels then return false end
            for n=-2,2 do if rawget(ownedLevels,n)~=levelTables[n] then return false end end
            return rawget(levelTables[-1],id)==ownedEntry and ownedEntry.fn==dispatch and ownedEntry.isstring==true
        end
        return get()==plain and plain.CalcView==owned
    end
    function self.Stop()
        if stopped then return end stopped=true
        held[fallback]=nil rawset(owned,id,nil)
        if ownedLevels then
            for n=-2,2 do
                heldLevels[n][fallback]=nil rawset(ownedLevels[n],id,nil)
                for key,entry in pairs(heldLevels[n]) do rawset(ownedLevels[n],key,entry) end
            end
            if actual.CalcView==ownedLevels then actual.CalcView=heldLevels end
        end
        for key,fn in pairs(held) do rawset(owned,key,fn) end
        if plain.CalcView==owned then plain.CalcView=held end
    end
    return self
end
return View
