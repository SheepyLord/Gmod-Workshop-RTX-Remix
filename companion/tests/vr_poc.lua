-- TEST_SOURCES is assembled from the shipping page/add-on and stand-in by vr_poc.py.
assert(TEST_SOURCES, "Run through companion/tests/vr_poc.py")
local function compiled(source, name, environment)
    local fn = CompileString(source, name, false)
    assert(type(fn) == "function", tostring(fn))
    if environment then setfenv(fn, environment) end
    return fn()
end
local api, mock = compiled(TEST_SOURCES.standin, "lua/nlvr/tests/standin.lua")()
local ID, OWNER = "vr_e_review_probe", "nativeloader_vr_view"
local mode = game.SinglePlayer() and "single-player" or "listen-host"
local result = {mode = mode, mock = true, snapshots = {}, camera_samples = {}, engine_probes = {}, order = {},
    max_camera_error = 0, max_render_error = 0, max_getpos_delta = 0, max_pose_age = 0,
    render_checks = 0, repeated_checks = 0, foreign_calls = 0, hud_frames = 0, hud_while_running = 0,
    viewmodel_while_running = 0, hands_while_running = 0, viewmodel_frames = {}, hand_frames = {}}
local phase, priorViews, baseline, instrumented, yaw, movementUntil = "baseline", nil, nil, nil, nil, 0
local firstSettings, functions = {}, {Call = hook.Call, Run = hook.Run, Add = hook.Add, Remove = hook.Remove,
    GetTable = hook.GetTable, Create = vgui.Create, require = require}
for _, name in ipairs({"fps_max", "cl_drawhud", "r_drawviewmodel", "rtx_pseudoplayer", "rtx_pseudoweapon"}) do
    firstSettings[name] = GetConVar(name):GetString()
end
local function vec(v) return {x = v.x, y = v.y, z = v.z} end
local function ang(a) return {p = a.p, y = a.y, r = a.r} end
local function blob(name, data)
    local encoded = util.Base64Encode(data):gsub("%s", "")
    local total = math.ceil(#encoded / 1200)
    for i = 1, total do
        MsgN("NLVR_E_BLOB " .. name .. " " .. i .. "/" .. total .. " " .. encoded:sub((i-1)*1200+1, i*1200))
    end
end
local function mark(event)
    if #result.order < 48 then result.order[#result.order+1] = {event = event, frame = FrameNumber()} end
end
local function hook_list()
    local list = {}
    for event, entries in pairs(hook.GetTable()) do
        for id, fn in pairs(entries) do
            local info = type(fn) == "function" and debug.getinfo(fn, "S") or {}
            list[#list+1] = {event = event, id = tostring(id), source = info.source, line = info.linedefined}
        end
    end
    table.sort(list, function(a,b) return a.event .. a.id < b.event .. b.id end)
    return list
end
local function snapshot(label)
    local item = {label = label, state = NativeLoaderVR and NativeLoaderVR.state, settings = {}, proxies = {},
        hooks = hook_list(), addon_hooks = {}, timers = {}, functions_unchanged = {},
        calcview_restored = hook.GetTable().CalcView == priorViews}
    for name, original in pairs(firstSettings) do
        local value = GetConVar(name):GetString()
        -- poc_session restores the user's shared config before its genuine quit. Compare shutdown
        -- against the value immediately before addon cleanup, not the earlier launch fixture.
        local expected = label == "shutdown" and mock.lastCleanup and mock.lastCleanup.before[name] or original
        item.settings[name] = {before = expected, fixture = original, now = value, unchanged = value == expected}
    end
    item.functions_unchanged = {Call = hook.Call == functions.Call, Run = hook.Run == functions.Run,
        Add = hook.Add == functions.Add, Remove = hook.Remove == functions.Remove, GetTable = hook.GetTable == functions.GetTable,
        Create = vgui.Create == functions.Create, require = require == functions.require}
    for _, entry in ipairs(item.hooks) do if entry.id == OWNER then item.addon_hooks[#item.addon_hooks+1] = entry end end
    item.timer_inventory = type(timer.GetTable) == "function" and "GetTable" or "owned-name Exists"
    if type(timer.GetTable) == "function" then
        for name in pairs(timer.GetTable()) do
            if name == "nativeloader_vr_session" or name:find("nlvr",1,true) then item.timers[#item.timers+1] = name end
        end
    elseif timer.Exists("nativeloader_vr_session") then item.timers[1] = "nativeloader_vr_session" end
    for _, class in ipairs({"rtx_pseudoplayer", "rtx_pseudoweapon"}) do
        local function entry(entity, root)
            local think = rawget(entity:GetTable(), "Think")
            item.proxies[#item.proxies+1] = {class = entity:GetClass(), index = entity:EntIndex(),
                hidden = entity:GetNoDraw(), root = root, think = tostring(think)}
            for _, child in ipairs(entity:GetChildren()) do entry(child, false) end
        end
        for _, entity in ipairs(ents.FindByClass(class)) do
            entry(entity, true)
        end
    end
    result.snapshots[#result.snapshots+1] = item
    MsgN("NLVR_E_SNAPSHOT " .. label .. " hooks=" .. #item.addon_hooks .. " timers=" .. #item.timers)
    return item
end
local function clean(item)
    assert(#item.addon_hooks == 0 and #item.timers == 0, "session callbacks left behind")
    assert(item.calcview_restored, "CalcView table identity not restored")
    for name, equal in pairs(item.functions_unchanged) do assert(equal, "global function replaced: " .. name) end
    for name, value in pairs(item.settings) do assert(value.unchanged, "setting changed: " .. name) end
    for _, before in ipairs(baseline.proxies) do
        local found = false
        for _, after in ipairs(item.proxies) do
            if after.class == before.class and after.index == before.index then
                assert(after.hidden == before.hidden, "proxy not restored") found = true
                if before.root then assert(after.think == before.think, "proxy Think not restored") end
            end
        end
        -- Other add-ons may remove proxies during real shutdown.
        if item.label ~= "shutdown" then assert(found, "baseline proxy disappeared") end
    end
end
local function fail(message)
    result.failure = tostring(message)
    MsgN("NLVR_E_FAILURE " .. result.failure)
    if NativeLoaderVR then NativeLoaderVR.Stop() end
    blob("failure.json", util.TableToJSON(result, false))
    MsgN("NL_SHOT_DONE")
end
local function after(seconds, fn)
    timer.Simple(seconds, function() local ok, err = pcall(fn) if not ok then fail(err) end end)
end
local function shot(label) after(1.0, function() MsgN("NL_SHOT " .. label) end) end

-- Isolated page environment supplies only the mock require/include; no global function is replaced.
local originalInclude, originalRequire = include, require
local environment = setmetatable({nlvr = api}, {__index = _G, __newindex = _G})
rawset(environment, "require", function(name) if name == "nlvr" then return api end return originalRequire(name) end)
rawset(environment, "include", function(path)
    if path == "nlvr/client.lua" then
        local session = compiled(TEST_SOURCES.addon, "lua/nlvr/client.lua", environment)
        local stop = session.Stop
        session.Stop = function()
            local cleanup = {before = {}, after = {}}
            for name in pairs(firstSettings) do cleanup.before[name] = GetConVar(name):GetString() end
            stop()
            for name, value in pairs(cleanup.before) do
                cleanup.after[name] = GetConVar(name):GetString()
                assert(cleanup.after[name] == value, "addon cleanup changed " .. name)
            end
            mock.lastCleanup = cleanup
        end
        return session
    end
    return originalInclude(path)
end)
compiled(TEST_SOURCES.page, "lua/autorun/client/nativeloader_vr.lua", environment)
GetConVar("nl_vr_scale"):SetString("40")
GetConVar("nl_vr_fov"):SetString("140")

hook.Add("CalcView", ID .. "_competing", function()
    if NativeLoaderVR.state == "running" then
        result.foreign_calls = result.foreign_calls + 1
        return {origin = Vector(9999,9999,9999), angles = Angle(), fov = 60}
    end
end)
priorViews = hook.GetTable().CalcView
hook.Add("PreRender", ID, function() mark("PreRender") end)
local function owning_view() return NativeLoaderVR.state=="running" and hook.GetTable().CalcView~=priorViews end
hook.Add("HUDPaint", ID, function()
    result.hud_frames = result.hud_frames + 1
    if owning_view() then result.hud_while_running=result.hud_while_running+1 end
end)
hook.Add("PostDrawViewModel", ID, function()
    result.viewmodel_frames[phase] = (result.viewmodel_frames[phase] or 0) + 1
    if owning_view() then result.viewmodel_while_running=result.viewmodel_while_running+1 end
end)
hook.Add("PostDrawPlayerHands", ID, function()
    result.hand_frames[phase] = (result.hand_frames[phase] or 0) + 1
    if owning_view() then result.hands_while_running=result.hands_while_running+1 end
end)
hook.Add("CreateMove", ID, function(command)
    local pistol=LocalPlayer():GetWeapon("weapon_pistol")
    if IsValid(pistol) and LocalPlayer():GetActiveWeapon()~=pistol then input.SelectWeapon(pistol) end
    if SysTime() < movementUntil then command:SetForwardMove(110) end
end)
local function instrument()
    local entries = hook.GetTable().CalcView
    if instrumented == entries then return end
    instrumented, yaw = entries, nil
    local realView = assert(rawget(entries, OWNER))
    entries[OWNER] = function(player, origin, angles, fov, near, far)
        mark("CalcView")
        mock.input = {origin = Vector(origin.x,origin.y,origin.z), angles = Angle(angles.p,angles.y,angles.r),
            raw = player:GetPos(), offset = player:GetCurrentViewOffset()}
        local count = #mock.cameras
        local view = realView(player, origin, angles, fov, near, far)
        if #mock.cameras > count then
            local repeated = realView(player, origin+Vector(1000,2000,3000), angles, fov, near, far)
            assert(repeated == view and #mock.cameras == count+1, "sequence pushed more than once")
            result.repeated_checks = result.repeated_checks + 1
        end
        return view
    end
    hook.Add("CalcView", ID .. "_late", function()
        result.foreign_calls = result.foreign_calls + 1 return {origin=Vector(8888,8888,8888)}
    end)
    hook.Remove("CalcView", ID .. "_late")
end
mock.onCamera = function(sequence, origin, angles)
    local input, pose = mock.input, mock.frames[sequence]
    if not input then return end
    if not yaw then yaw = input.angles.y - pose.ang.y end
    local anchor = input.origin - input.offset
    local s, c = math.sin(math.rad(yaw)), math.cos(math.rad(yaw))
    local expected = anchor + Vector(40*(c*pose.pos.x-s*pose.pos.y),40*(s*pose.pos.x+c*pose.pos.y),40*pose.pos.z)
    local errorDistance = (origin-expected):Length()
    result.max_camera_error = math.max(result.max_camera_error, errorDistance)
    result.max_getpos_delta = math.max(result.max_getpos_delta, (anchor-input.raw):Length())
    result.max_pose_age = math.max(result.max_pose_age, FrameNumber()-pose.frame)
    if #result.camera_samples < 1500 then
        result.camera_samples[#result.camera_samples+1] = {phase=phase, sequence=sequence, frame=FrameNumber(),
            input=vec(input.origin), offset=vec(input.offset), getpos=vec(input.raw), anchor=vec(anchor),
            expected=vec(expected), camera=vec(origin), angles=ang(angles), pose=pose, error=errorDistance}
    end
end
local captureRequested, captured = false, false
hook.Add("PostRender", ID, function()
    if mock.lastCamera and mock.lastCamera.frame==FrameNumber() and NativeLoaderVR.state == "running" then
        local view=render.GetViewSetup()
        if view and view.origin then
            local point=mock.lastCamera.origin
            result.max_render_error=math.max(result.max_render_error,(view.origin-Vector(point.x,point.y,point.z)):Length())
            result.render_checks=result.render_checks+1
        end
    end
    if not captureRequested or captured then return end
    captured = true
    local ok, err = pcall(function()
        local target=GetRenderTargetEx("nlvr_wrist_v1_769x257",769,257,RT_SIZE_LITERAL,MATERIAL_RT_DEPTH_NONE,0,0,IMAGE_FORMAT_RGBA8888)
        render.PushRenderTarget(target)
        local success, png=pcall(render.Capture,{format="png",x=0,y=0,w=769,h=257,alpha=false})
        render.PopRenderTarget()
        assert(success and type(png)=="string" and png:sub(1,4)=="\137PNG", "wrist capture failed: "..tostring(png))
        local player=LocalPlayer() local weapon=player:GetActiveWeapon()
        result.wrist={width=target:Width(),height=target:Height(),health=player:Health(),armour=player:Armor(),
            clip=weapon:Clip1(),reserve=player:GetAmmoCount(weapon:GetPrimaryAmmoType()),bytes=#png}
        result.guard=NativeLoaderRenderGuard and {blocked=NativeLoaderRenderGuard.blocked,
            allocations=NativeLoaderRenderGuard.allocations_by_source,bytes=NativeLoaderRenderGuard.allocation_bytes_by_source}
        blob("wrist.png",png)
    end)
    if not ok then fail(err) end
end)
local function start(nextPhase, ready)
    phase, instrumented, mock.input, yaw = nextPhase, nil, nil, nil
    assert(NativeLoaderVR.Start(), "mock Start refused")
    local deadline=SysTime()+10
    timer.Create(ID .. "_start",0.05,0,function()
        if NativeLoaderVR.state=="failed" then timer.Remove(ID .. "_start") fail(NativeLoaderVR.detail) return end
        if NativeLoaderVR.state=="running" then
            timer.Remove(ID .. "_start")
            local ok,err=pcall(function()
                instrument()
                local active=snapshot("active-"..nextPhase)
                for _, proxy in ipairs(active.proxies) do assert(proxy.hidden,"proxy/child is visible during VR") end
                ready()
            end)
            if not ok then fail(err) end
        elseif SysTime()>deadline then timer.Remove(ID .. "_start") fail("mock start timeout") end
    end)
end
local function wait_off(label, ready)
    local deadline=SysTime()+5
    timer.Create(ID .. "_off",0.05,0,function()
        if NativeLoaderVR.state=="off" then
            timer.Remove(ID .. "_off")
            local ok,err=pcall(function() clean(snapshot(label)) ready() end)
            if not ok then fail(err) end
        elseif SysTime()>deadline then timer.Remove(ID .. "_off") fail("mock stop timeout") end
    end)
end
mock.onStop=function()
    if phase~="shutdown" or not result.shutdown_armed then return end
    local item=snapshot("shutdown") clean(item)
    result.calls=mock.calls result.cameras=mock.cameras result.frames=mock.frames
    result.duplicate_pushes=mock.duplicatePushes result.overlay_count=table.Count(mock.overlays)
    result.success=not result.failure and result.foreign_calls==0 and result.max_camera_error<0.001
        and result.max_render_error<0.001 and result.repeated_checks>0 and captured and result.duplicate_pushes==0
        and result.max_pose_age==0
        and result.viewmodel_while_running==0 and result.hands_while_running==0 and result.hud_while_running>0
        and (result.viewmodel_frames.baseline or 0)>0 and (result.viewmodel_frames["manual-stop"] or 0)>0
    MsgN("NLVR_E_FINAL "..util.TableToJSON({mode=mode,success=result.success,cameras=#mock.cameras,
        camera_error=result.max_camera_error,render_error=result.max_render_error,pose_age=result.max_pose_age,
        foreign_calls=result.foreign_calls,duplicate_pushes=result.duplicate_pushes},false))
    blob("result.json",util.TableToJSON(result,false))
end
concommand.Add("nl_shot_taken",function(_,_,args)
    local number=tonumber(args[1])
    local ok,err=pcall(function()
        if number==1 then
            start("neutral",function() captureRequested=true shot("head-neutral") end)
        elseif number==2 then
            mock.pose={pos=Vector(0,0.25,1.6),ang=Angle(0,40,0)} phase="look"
            movementUntil=SysTime()+0.8
            shot("head-look-moving")
        elseif number==3 then
            mock.pose={pos=Vector(0.35,-0.2,1.8),ang=Angle(-10,-35,8)} phase="lean"
            shot("head-lean")
        elseif number==4 then
            phase="manual-stop" RunConsoleCommand("nl_vr_exit")
            wait_off("manual-stop",function() shot("flat-after-stop") end)
        elseif number==5 then
            start("quit",function()
                after(0.6,function() mock.events={{type="quit"}} wait_off("steamvr-quit",function() shot("flat-after-quit") end) end)
            end)
        elseif number==6 then
            start("shutdown",function() result.shutdown_armed=true shot("active-before-shutdown") end)
        elseif number==7 then
            MsgN("NLVR_E_BEFORE_SHUTDOWN "..util.TableToJSON({cameras=#mock.cameras,camera_error=result.max_camera_error,
                render_error=result.max_render_error,pose_age=result.max_pose_age,foreign_calls=result.foreign_calls},false))
            result.calls=mock.calls result.cameras=mock.cameras result.frames=mock.frames
            blob("before-shutdown.json",util.TableToJSON(result,false))
            MsgN("NL_SHOT_DONE")
        end
    end)
    if not ok then fail(err) end
end)

-- Native API probes: setters are attempted only to observe GMod's documented restriction. Allowed client
-- commands are changed back before the add-on runs. fps_max is attempted once and is never bypassed.
local probes={{"fps_max","61"},{"cl_drawhud",firstSettings.cl_drawhud=="0" and "1" or "0"},
    {"r_drawviewmodel",firstSettings.r_drawviewmodel=="0" and "1" or "0"}}
local function probe(index)
    if not probes[index] then
        baseline=snapshot("before-start")
        assert(#baseline.proxies>=2,"real body/weapon proxies must exist for this test")
        shot("flat-before") return
    end
    local name,value=unpack(probes[index]) local convar=GetConVar(name)
    local row={name=name,before=convar:GetString(),requested=value}
    row.setter_ok,row.setter_error=pcall(convar.SetString,convar,value)
    row.after_setter=convar:GetString()
    RunConsoleCommand(name,value)
    after(0.2,function()
        row.after_command=convar:GetString()
        if row.after_command~=row.before then RunConsoleCommand(name,row.before) end
        after(0.2,function()
            row.after_restore=convar:GetString()
            assert(row.after_restore==row.before,"probe did not restore "..name)
            result.engine_probes[#result.engine_probes+1]=row
            MsgN("NLVR_E_CONVAR "..util.TableToJSON(row,false))
            probe(index+1)
        end)
    end)
end
for _, panel in ipairs(vgui.GetWorldPanel():GetChildren()) do
    if IsValid(panel) and panel.GetTitle and tostring(panel:GetTitle()):lower():find("loader update",1,true) then panel:Remove() end
end
probe(1)
