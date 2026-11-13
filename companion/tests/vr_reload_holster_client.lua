-- Private before/after holster witness. The package's production modules run unchanged.
local saved, captures, selected = {}, {}, {}
local prepared, seen, finished, offAt, flatMove, lastPhase, requestAt, counterAt
lastPhase, requestAt, counterAt = -1, -10, -10
for _, name in ipairs({"physical_reload", "ammo_counter", "foregrip", "scale", "height", "seated", "dominant", "gun_angle"}) do
    saved[name] = GetConVar("nl_vr_" .. name):GetString()
end
local function out(kind, data) data.kind = kind print("NLVR_K " .. util.TableToJSON(data)) end
hook.Add("PreRender", "nlvr_k_holster", function()
    if not prepared and SysTime() - began >= 5 then
        prepared = true
        for k,v in pairs({physical_reload=1,ammo_counter=1,foregrip=0,scale=40,height=0,seated=0,dominant=0,gun_angle=0}) do RunConsoleCommand("nl_vr_"..k,tostring(v)) end
    end
    if NLVR and nlvr and nlvr.TestState() then
        seen = true
        flatMove = flatMove or hook.GetTable().CreateMove and hook.GetTable().CreateMove[ID]
        hook.Remove("CreateMove", ID)
        local s = nlvr.TestState() local phase = math.floor(s.time / 15)
        local class = CONFIG.reload_classes[phase+1] local t = s.time % 15
        if class and (phase ~= lastPhase or NLVR_K_ACK ~= phase and s.time-requestAt>.25) then
            lastPhase,requestAt = phase,s.time
            RunConsoleCommand("nlvr_k_phase",tostring(phase),class,tostring(t),tostring(SysTime()))
        end
        if class then
            for _,v in ipairs({{3,"nlvr_hands"},{7.5,class}}) do
                local key = phase..":"..v[1]
                if t>=v[1] and not selected[key] then selected[key]=true RunConsoleCommand("nlvr_k_select",v[2]) end
            end
        end
        local o = NLVR.Overlay.Objects.ammo
        local a = NLVR.Weapon and NLVR.Weapon.Active
        if o and a and s.time-counterAt>=.25 then
            counterAt=s.time
            out("counter",{class=a.class,time=s.time,visible=nlvr.OverlayVisible(o.handle),native=nlvr.OverlayInfo(o.handle)})
        end
        if o and class then for _,v in ipairs({{8,"returned"},{9.8,"held"},{10.7,"well"},{13.8,"after"}}) do
            local label=class.."-holster-"..v[2]
            if t>=v[1] and not captures[label] and nlvr.Capture(label,15) then
                captures[label]=true out("capture",{class=class,label=label,ammo_handle=o.handle,time=s.time})
            end
        end end
    elseif seen and not finished then
        offAt=offAt or RealTime()
        if RealTime()-offAt>1 then
            finished=true
            if flatMove then hook.Add("CreateMove",ID,flatMove) end
            for k,v in pairs(saved) do RunConsoleCommand("nl_vr_"..k,v) end
            timer.Simple(.2,function()
                local differences={}
                for k,v in pairs(saved) do if GetConVar("nl_vr_"..k):GetString()~=v then differences[k]=true end end
                out("settings-restored",{differences=differences})
            end)
            RunConsoleCommand("nlvr_k_done") NLVR_K_ACK=nil hook.Remove("PreRender","nlvr_k_holster")
        end
    end
end)
