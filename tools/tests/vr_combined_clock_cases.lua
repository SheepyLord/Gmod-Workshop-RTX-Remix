local root=...
local S=assert(loadfile(root.."/companion/tests/vr_stubs.lua"))() S.Math()
local Clock=assert(loadfile(root.."/companion/tests/vr_combined_clock.lua"))()
local wall,engine,paused=64,100,false
local steps={
    {time=64,hmd={pos={0,0,1.6},ang={0,0,0}},actions={}},
    {time=64.1,hmd={pos={1,0,1.6},ang={0,0,0}},actions={right_stick={0,-1},left_trigger_value=.25,left_skeleton={curls={.25},splay={.25}}}},
    {time=64.3,hmd={pos={3,0,1.6},ang={0,0,0}},actions={left_trigger_value=.75,left_skeleton={curls={.75},splay={.75}}}},
    {time=70,hmd={pos={3,0,1.6},ang={0,0,0}},actions={}}}
for _,s in ipairs(steps) do s.left=s.hmd s.right=s.hmd end
local native={TestState=function() return {time=wall,step=1} end,
    BeginFrame=function() return {sequence=12,hmd={},left={},right={}} end,
    Actions=function() return {sentinel=true} end}
local old={native.TestState,native.BeginFrame,native.Actions}
local c=Clock.New{Native=native,Steps=steps,BeginAt=64,EngineTime=function() return engine end,
    WallTime=function() return wall end,Paused=function() return paused end}
native.BeginFrame()
wall,engine=64.15,100.15
local f=native.BeginFrame()
assert(math.abs(f.hmd.pos.x-1.5)<.00001 and math.abs(f.hmd.vel.x-10)<.00001)
assert(native.Actions().right_stick.y==-1)
assert(math.abs(native.Actions().left_trigger_value.x-.375)<.00001,"native analogue schema/interpolation")
assert(native.Actions().left_skeleton.active and math.abs(native.Actions().left_skeleton.curls[1]-.375)<.00001,"native skeleton schema/interpolation")
-- A GPU dump consumed 2.54 wall seconds while Source advanced one physics tick.
wall,engine=66.69,100.165
native.BeginFrame()
assert(native.TestState().time<64.2 and native.Actions().right_stick.y==-1,"capture skipped the toggle")
assert(native.TestState().native_time==66.69,"raw wall timeline must remain in evidence")
-- Intentional single-player menu pause still permits tracked room motion.
paused=true
native.BeginFrame()
wall=66.79
native.BeginFrame()
assert(math.abs(native.TestState().time-64.265)<.00001)
assert(c.Stats().excluded_wall_seconds>2.5)
c.Stop()
assert(native.TestState==old[1] and native.BeginFrame==old[2] and native.Actions==old[3])
-- Whole-session replay also preserves the physical throw's real derivatives.
wall,engine,paused=0,20,false
local ramp={}
for _,t in ipairs({0,.25}) do
    local p={pos={.3+3*t,0,1.2},ang={0,math.deg(1.16*t),0}}
    ramp[#ramp+1]={time=t,hmd=p,left=p,right=p,actions={right_grip=true}}
end
c=Clock.New{Native=native,Steps=ramp,BeginAt=0,EngineTime=function() return engine end,
    WallTime=function() return wall end,Paused=function() return paused end}
native.BeginFrame() wall,engine=.125,20.125
f=native.BeginFrame()
assert(math.abs(f.right.vel.x*40-120)<.00001 and math.abs(f.right.angvel.z-1.16)<.00001)
c.Stop()
print("PASS functional clock")
