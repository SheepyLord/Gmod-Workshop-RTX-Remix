local root=...
local S=assert(loadfile(root.."/companion/tests/vr_stubs.lua"))() S.Math()
for _,probe in ipairs({"latency","motion"}) do
    local events,records={},{} local calc={}
    hook={Add=function(event,id,fn) events[event]=events[event] or {} events[event][id]=fn end,
        Remove=function(event,id) if events[event] then events[event][id]=nil end end,
        GetTable=function() return {CalcView=calc} end,
        Run=function(event,...) for _,fn in pairs(events[event] or {}) do local r=fn(...) if r~=nil then return r end end end}
    FrameNumber=function() return 1 end
    CurTime=function() return 6 end SysTime=CurTime
    engine={TickCount=function() return 400 end}
    nlvr={TestState=function() return {time=6} end}
    local ply={GetPos=function() return Vector() end,EyeAngles=function() return Angle() end,
        EyePos=function() return Vector(0,0,64) end,GetMoveType=function() return 2 end}
    LocalPlayer=function() return ply end RunConsoleCommand=function() end
    local cmd={ClearMovement=function() end,ClearButtons=function() end,SetMouseX=function() end,GetViewAngles=function() return Angle() end}
    local ctx={mover=function(_,fn) fn(cmd) end,cleanup=function() end}
    NLVR={Frame={sequence=11,hmd={valid=true,pos=Vector(0,0,1.6),ang=Angle(0,0,3)}},
        Space={yaw=0,scale=40},Feet=Vector(),Debug={move={}},Registry={entries={{module={name="move"},ctx=ctx}}}}
    phase="active"
    emit=function(kind,data) records[#records+1]={kind=kind,data=data} end
    assert(loadfile(root.."/companion/tests/vr_move_"..probe.."_probe.lua"))()
    hook.Run("PreRender")
    hook.Run("RenderScene",Vector(5,6,64),Angle(0,0,3),145)
    hook.Run("RenderScene",Vector(999,999,999),Angle(),145)
    phase="flat-after" hook.Run("PreRender")
    local found
    for _,r in ipairs(records) do if r.kind=="L-"..probe then found=r.data.frames end end
    assert(found and #found==1,"probe must observe the rendered scene with an opaque CalcView registry")
    assert(found[1].camera[1]==5 and found[1].camera[2]==6 and found[1].sequence==11)
    assert(next(calc)==nil,"measurement must not mutate camera ownership")
    assert(not next(events.RenderScene or {}),"render observer must restore cleanly")
end
print("PASS rendered temporal probes")
