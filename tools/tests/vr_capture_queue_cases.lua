local root=...
local Queue=assert(loadfile(root.."/tools/vr_capture_queue.lua"))()
local frame,now,active=0,0,true
local inventory={a={created_frame=0,info={visible=true}}}
local sent,described,errors={},{},{}
local fail=false
local q=Queue.New{Frame=function() return frame end,Now=function() return now end,Running=function() return active end,
    Inventory=function() return inventory end,Describe=function(label,items) described[#described+1]={label,items} end,
    Forward=function(label) sent[#sent+1]=label if fail then return nil,"native refused" end return true end,
    Error=function(message) errors[#errors+1]=message end}
q.Request("new",15) q.Pump() assert(#sent==0)
frame,now=1,.01 q.Pump() assert(#sent==0,"unpainted source dispatched")
frame,now=2,.02 q.Pump() assert(sent[1]=="new" and described[1][2]==inventory)
q.Request("second",15) q.Request("third",15) q.Pump() assert(#sent==1)
frame,now=3,.03 q.Pump() q.Pump() assert(#sent==2,"two captures overwrite one runtime request")
frame,now=4,.04 q.Pump() assert(sent[3]=="third")
inventory={hidden={created_frame=4,info={visible=false}}}
q.Request("hidden",15) frame=5 q.Pump() assert(sent[4]=="hidden")
fail=true q.Request("refusal",15) frame=6 q.Pump() assert(#errors==1 and errors[1]:find("native refused",1,true))
inventory={new={created_frame=7,info={visible=true}}}
q.Request("timeout",15) frame,now=7,2 q.Pump() assert(#errors==2)
q.Request("stopped",15) active=false frame=8 q.Pump() q.Stop() assert(#errors==3)
assert(#sent==5)
print("PASS capture readiness, one-per-frame dispatch, retirement, refusal, timeout and stop")
