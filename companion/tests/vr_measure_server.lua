-- Private send observation in the server realm; no additional network messages.
require("nlvrqinspect")
local originalStart,originalUInt,originalSend=net.Start,net.WriteUInt,net.Send
local packet,tx,otherTx,began=nil,{},{},SysTime()
local registry,originalCall,totals,stack,ticks=nil,nil,{},{},0
net.Start=function(name,...) packet={name=name,kind="unknown"} return originalStart(name,...) end
net.WriteUInt=function(value,bits) if packet and packet.name=="nlvr" and packet.kind=="unknown" then packet.kind=tostring(value) end return originalUInt(value,bits) end
net.Send=function(...)
    if packet then
        local list=packet.name=="nlvr" and tx or otherTx
        local key=packet.name=="nlvr" and packet.kind or packet.name local out=list[key] or {count=0,bytes=0} list[key]=out
        out.count=out.count+1 out.bytes=out.bytes+(net.BytesWritten and net.BytesWritten() or 0)
    end
    packet=nil return originalSend(...)
end
concommand.Add("nlvr_q_net_begin",function()
    tx,otherTx,began={},{},SysTime()
    registry=assert(NLVR_SV and NLVR_SV.Registry,"server registry unavailable for CPU measurement")
    originalCall=registry.Call
    for _,entry in ipairs(registry.entries) do totals[entry.module.name]={calls=0,cpu_ms=0,cycles=0,wall_ms=0} end
    registry.Call=function(self,entry,fn,...)
        local cpu,cycles=nlvrqinspect.Clock() local wall=SysTime()
        local frame={cpu=0,cycles=0,wall=0} stack[#stack+1]=frame
        local a,b,c=originalCall(self,entry,fn,...)
        local endCpu,endCycles=nlvrqinspect.Clock()
        local dc,dy,dw=endCpu-cpu,endCycles-cycles,(SysTime()-wall)*1000
        stack[#stack]=nil
        local parent=stack[#stack]
        if parent then parent.cpu=parent.cpu+dc parent.cycles=parent.cycles+dy parent.wall=parent.wall+dw end
        local out=totals[entry.module.name]
        out.calls=out.calls+1 out.cpu_ms=out.cpu_ms+dc-frame.cpu
        out.cycles=out.cycles+dy-frame.cycles out.wall_ms=out.wall_ms+dw-frame.wall
        return a,b,c
    end
    hook.Add("Tick","nlvr_q_profile_tick",function() ticks=ticks+1 end)
end)
concommand.Add("nlvr_q_net_report",function()
    print("NLVR_Q "..util.TableToJSON({kind="Q-server-network",elapsed=SysTime()-began,messages=tx,other_lua_messages=otherTx}))
    if registry then registry.Call=originalCall end
    hook.Remove("Tick","nlvr_q_profile_tick")
    print("NLVR_Q "..util.TableToJSON({kind="Q-server-profile",elapsed=SysTime()-began,ticks=ticks,modules=totals,
        note="Exclusive server registry callback CPU; excludes receiver work outside the registry; includes clock/wrapper overhead."}))
    net.Start,net.WriteUInt,net.Send=originalStart,originalUInt,originalSend
    concommand.Remove("nlvr_q_net_report")
    concommand.Remove("nlvr_q_net_begin")
end)
