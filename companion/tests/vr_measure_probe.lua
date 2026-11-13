-- Development-only exclusive callback CPU attribution; all clocks are from this game thread.
require("nlvrqinspect")
local id, attached, activeAt, activeFrames = "nlvr_measure_probe", false, nil, 0
local postRenders,lastSourceFrame,firstSourceFrame=0,nil,nil
local totals, stack = {}, {}
local tx, otherTx, packet, originalStart, originalUInt, originalSend = {}, {}, nil, net.Start, net.WriteUInt, net.SendToServer
net.Start=function(name,...) packet={name=name,kind="unknown"} return originalStart(name,...) end
net.WriteUInt=function(value,bits) if packet and packet.name=="nlvr" and packet.kind=="unknown" then packet.kind=tostring(value) end return originalUInt(value,bits) end
net.SendToServer=function(...)
    if packet then
        local list=packet.name=="nlvr" and tx or otherTx
        local key=packet.name=="nlvr" and packet.kind or packet.name local r=list[key] or {count=0,bytes=0} list[key]=r
        r.count=r.count+1 r.bytes=r.bytes+(net.BytesWritten and net.BytesWritten() or 0)
    end
    packet=nil return originalSend(...)
end
local function report(label)
    emit("Q-profile",{label=label,elapsed=activeAt and SysTime()-activeAt or 0,frames=activeFrames,
        postrender_callbacks=postRenders,frame_denominator="Distinct FrameNumber at active PostRender",
        source_frame_first=firstSourceFrame,source_frame_last=lastSourceFrame,
        modules=totals,client_messages=tx,other_client_lua_messages=otherTx,clock="GetThreadTimes ms; QueryThreadCycleTime cycles; SysTime wall ms",
        cpu_note="Exclusive callback attribution. Windows CPU accounting is quantized; clock/wrapper overhead is included."})
end
hook.Add("PostRender",id,function()
    if phase=="active" then
        postRenders=postRenders+1
        local sourceFrame=FrameNumber()
        if sourceFrame~=lastSourceFrame then
            activeFrames=activeFrames+1 lastSourceFrame=sourceFrame firstSourceFrame=firstSourceFrame or sourceFrame
        end
    end
end)
hook.Add("PreRender",id,function()
    if phase=="active" and NLVR and not attached then
        attached,activeAt=true,SysTime()
        totals,tx,otherTx={},{},{}
        RunConsoleCommand("nlvr_q_net_begin")
        local registry=NLVR.Registry local original=registry.Call
        for _,entry in ipairs(registry.entries) do totals[entry.module.name]={calls=0,cpu_ms=0,cycles=0,wall_ms=0} end
        registry.Call=function(self,entry,fn,...)
            local cpu,cycles=nlvrqinspect.Clock() local wall=SysTime()
            local frame={cpu=0,cycles=0,wall=0} stack[#stack+1]=frame
            local a,b,c=original(self,entry,fn,...)
            local endCpu,endCycles=nlvrqinspect.Clock()
            local dc,dy,dw=endCpu-cpu,endCycles-cycles,(SysTime()-wall)*1000
            stack[#stack]=nil
            local parent=stack[#stack]
            if parent then parent.cpu=parent.cpu+dc parent.cycles=parent.cycles+dy parent.wall=parent.wall+dw end
            local name=entry.module.name local out=totals[name] or {calls=0,cpu_ms=0,cycles=0,wall_ms=0}
            totals[name]=out out.calls=out.calls+1
            out.cpu_ms=out.cpu_ms+dc-frame.cpu out.cycles=out.cycles+dy-frame.cycles out.wall_ms=out.wall_ms+dw-frame.wall
            return a,b,c
        end
        -- The test wrapper is removed before normal module cleanup. No profiler ships.
        hook.Add("PreRender",id.."_stop",function()
            if phase~="active" then
                registry.Call=original report("active")
                RunConsoleCommand("nlvr_q_net_report")
                hook.Remove("PreRender",id.."_stop")
            end
        end)
    elseif phase=="flat-after" and attached then
        emit("Q-off-profile",{global=NLVR~=nil,receiver=net.Receivers.nlvr~=nil,
            note="No module registry/callback exists off; off per-module callback count is exactly zero."})
        net.Start,net.WriteUInt,net.SendToServer=originalStart,originalUInt,originalSend
        hook.Remove("PreRender",id) hook.Remove("PostRender",id)
    end
end)
