-- Private stationary same-game control. Whole frame intervals stay inside stable mode blocks.
local id="nlvr_q_cachecpu"
local rows={cached={frames=0,cpu_ms=0,cycles=0,calls=0,passes=0},uncached={frames=0,cpu_ms=0,cycles=0,calls=0,passes=0}}
local blocks={{5,11,"uncached"},{12,18,"cached"},{19,25,"cached"},{26,32,"uncached"}}
local core,oldRefresh,previous,done
local function time() local s=nlvr.TestState() return s and s.time or -1 end
local function block(t,margin)
    for index,b in ipairs(blocks) do if t>=b[1]+margin and t<b[2]-margin then return index,b[3] end end
end
hook.Add("PreRender",id,function()
    if not NLVR or core then return end
    core=NLVR oldRefresh=core.Refresh
    RunConsoleCommand("nlvr_cachecpu_begin")
    core.Refresh=function(...)
        local t=time() local _,mode=block(t,0)
        if mode=="uncached" then core.HandRevision=(core.HandRevision or 0)+1 end
        local _,measured=block(t,.25)
        local hand=core.Hand.left
        local result=oldRefresh(...)
        if measured then
            local r=rows[measured] r.calls=r.calls+1
            if core.Hand.left~=hand then r.passes=r.passes+1 end
        end
        return result
    end
    local ctx
    for _,entry in ipairs(core.Registry.entries) do if entry.module.name=="core" then ctx=entry.ctx end end
    ctx.cleanup(function()
        core.Refresh=oldRefresh
        emit("Q-cachecpu",{rows=rows,blocks=blocks,edge_exclusion_seconds=.25,
            scope="Whole game-thread CPU/cycles between adjacent PostRender frames inside one stable control block; two blocks per mode, balanced order"})
        done=true hook.Remove("PreRender",id) hook.Remove("PostRender",id)
    end)
end)
local healthBegin,healthEnd
hook.Add("PostRender",id,function()
    if not core or NLVR~=core or done then return end
    local t=time() local number=FrameNumber()
    if previous and previous.frame==number then return end
    local cpu,cycles=nlvrqinspect.Clock()
    local index,mode=block(t,.25)
    if index and previous and previous.frame+1==number and previous.block==index then
        local r=rows[mode] r.frames=r.frames+1 r.cpu_ms=r.cpu_ms+cpu-previous.cpu r.cycles=r.cycles+cycles-previous.cycles
    end
    previous={frame=number,cpu=cpu,cycles=cycles,block=index}
    if t>=4 and not healthBegin then healthBegin=true RunConsoleCommand("nlvr_cachecpu_health","begin") end
    if t>=32.2 and not healthEnd then healthEnd=true RunConsoleCommand("nlvr_cachecpu_health","end") end
end)
