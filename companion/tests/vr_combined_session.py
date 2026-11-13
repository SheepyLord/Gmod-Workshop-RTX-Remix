"""Q's combined V2/V3 fixture on the production VR driver; no weakened renderer checks."""
from __future__ import annotations
import argparse
import copy
import json
from pathlib import Path
import subprocess
import shutil
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path[:0] = [str(ROOT / "tools"), str(Path(__file__).parent)]
import vr_session as driver
import poc_session as poc
import vr_interact_poc as physical
import vr_interact_analyse as physical_check
import vr_move_session as movement
import vr_move_check as movement_check
import vr_move_latency_check as latency_check
import vr_move_motion_check as motion_check
import vr_ui_poc as menus
import vr_fixture_frames as controller_frames

P_END, H_END, L_END, REVIEW_START, END = 56, 64, 98, 129, 177
MOVE_SCALE, UI_RATE, PHYSICS_SCALE = .4, 2.75, .5


def timeline():
    steps = []
    # Half-duration physical slots. Throw displacement/rotation also halve, preserving
    # their actual derivatives; all other actual velocities remain recorded by P.
    for original in physical.timeline(112)["steps"]:
        if original["time"] >= 112:
            continue
        s = copy.deepcopy(original)
        slot, local = divmod(s["time"], 8)
        s["time"] = s['time'] * PHYSICS_SCALE
        if slot==10 and abs(local-3.15)<.00001:
            # A real 4 m/s punch for 200 ms lets the physical proxy reach the NPC hull.
            # It still saturates the unchanged 25-damage curve; never assign the result.
            s['time']=(slot*8+3.4)*PHYSICS_SCALE
        if slot == 1:
            s['right']['pos'][0] = .3 + (s['right']['pos'][0]-.3)*PHYSICS_SCALE
            s['right']['ang'][1] *= PHYSICS_SCALE
        if slot==4 and 3<=local<4.5:
            s['actions']['left_stick']=[0,.35]
        steps.append(s)
    import math
    for index, depth in enumerate((.2, .3, .5)):
        for offset in (0, 1.8):
            side = .06 if depth < .4 else .14
            forward = math.sqrt(depth*depth-side*side)
            steps.append({"time": P_END + index * 2 + offset,
                          "hmd": {"pos": [0, 0, 1.6], "ang": [0, 0, 0]},
                          **{hand: {"pos": [forward, sign * side, 1.6],
                                    "ang": [-35, 0, 0]} for hand, sign in (("left", 1), ("right", -1))},
                          "actions": {"left_skeleton": {"curls": [0]*5, "splay": [.4]*4},
                                      "right_skeleton": {"curls": [0]*5, "splay": [.4]*4}}})
    for t,closed in ((62,False),(62.65,False),(62.7,True),(63.8,True)):
        s=copy.deepcopy(steps[-1]);s['time']=t
        for hand in ('left','right'):s['actions'][hand+'_skeleton']['splay']=[0]*4
        s['actions']['left_skeleton']['curls']=[1,.8,.6,.4,.2] if closed else [0]*5
        s['actions']['right_skeleton']['curls']=[.2,.4,.6,.8,1] if closed else [0]*5
        steps.append(s)
    for original in movement.timeline("combined")["steps"]:
        if original["time"] > 84.9:
            continue
        s = copy.deepcopy(original)
        s["time"] = H_END + s["time"] * MOVE_SCALE
        steps.append(s)
    height_at=L_END+78/UI_RATE
    for t in (L_END, height_at, height_at+.2, END + 5):
        steps.append({"time": t, "hmd": {"pos": [0, 0, 1.6], "ang": [0, 0, 0]},
                      "left": {"pos": [.25, .3, 1.2], "ang": [0, 0, -90]},
                      "right": {"pos": [.05, -.25, 1.2], "ang": [0, 0, 0]}, "actions": {}})
        if t >= height_at+.2:
            steps[-1]['hmd']['pos'][2] = 1.8
    return controller_frames.natural_timeline({"version": 1, "steps": steps,
            "events": [{"time": L_END + 18/UI_RATE, "type": "keyboard_done", "text": "barrel"}]})


def checked_replace(text, before, after, count=1):
    if text.count(before) != count:
        raise ValueError("Fixture contract changed: " + before[:100])
    return text.replace(before, after)


def moving_base(base):
    # Remove only the driver's static keyboard suppression: the real production
    # movers must reach Source. The fixture owns a pre-mover clearing physical input.
    start = base.index('if not CONFIG.look then\n    hook.Add("CreateMove",ID,')
    end = base.index('\nif CONFIG.flat then', start)
    base = base[:start] + '\n'.join((
        'if not CONFIG.look then',
        '    hook.Add("CreateMove",ID,function(command)',
        '        command:SetMouseX(0) command:SetMouseY(0)',
        '        if not NLVR then',
        '            command:SetViewAngles(angles)',
        '            command:ClearMovement() command:ClearButtons()',
        '        end',
        '    end,HOOK_MONITOR_HIGH or -2)',
        'end')) + base[end:]
    for label in ("yaw-plus20", "yaw-minus20", "lean-left"):
        base = base.replace('capture("'+label+'")', 'do end')
    base = checked_replace(base,'now - began >= 4 and not captures.flat_before','now - began >= 2 and not captures.flat_before')
    base = checked_replace(base,'now - began >= 7 and before','now - began >= 4 and before')
    base = checked_replace(base,'now - phaseAt >= 2 then','now - phaseAt >= 0.3 then')
    base = checked_replace(base,'now - phaseAt >= 5 then shot("flat-after")','now - phaseAt >= 2 then shot("flat-after")')
    return base


def client_fixture(base):
    finger_witness=Path(__file__).with_name('vr_finger_witness.lua').read_text(encoding='utf-8')
    base = moving_base(base)
    # Functional assertions run with Source physics, not GPU screenshot I/O. Keep
    # native sequence/pacing and raw time in evidence; the temporal case is untouched.
    clock = Path(__file__).with_name('vr_combined_clock.lua').read_text(encoding='utf-8')
    steps = timeline()['steps']
    clock_setup = '''if CONFIG.simulate then
        qFunctionalClock=QFunctionalClock.New{Native=native,Steps=util.JSONToTable([==[%s]==]),BeginAt=%s,
            EngineTime=function() return engine.TickCount()*engine.TickInterval() end,
            WallTime=SysTime,Paused=function() return gui.IsGameUIVisible() end}
    end
    ''' % (json.dumps(steps, separators=(',', ':')), 0)
    base = checked_replace(base, 'originalBegin, originalCamera, originalCreate = native.BeginFrame, native.SetFrameCamera, native.OverlayCreate',
                           clock_setup+'originalBegin, originalCamera, originalCreate = native.BeginFrame, native.SetFrameCamera, native.OverlayCreate')
    base = checked_replace(base, 'local t = now - activeAt',
                           'local t = qFunctionalClock and native.TestState().time or now - activeAt')
    base = checked_replace(base, 'native.BeginFrame, native.SetFrameCamera, native.OverlayCreate, native.Capture = originalBegin, originalCamera, originalCreate, originalCapture',
                           'native.BeginFrame, native.SetFrameCamera, native.OverlayCreate, native.Capture = originalBegin, originalCamera, originalCreate, originalCapture\n'
                           '        if qFunctionalClock then emit("Q-functional-clock",qFunctionalClock.Stats()) qFunctionalClock.Stop() end')
    base='local QFunctionalClock=(function()\n'+clock+'\nend)()\nlocal qFunctionalClock\n'+base
    base='local QFingerWitness=(function()\n'+finger_witness+'\nend)()\n'+base
    base = checked_replace(base, 'else RunConsoleCommand("nl_vr_exit") phase_to("stopping") end',
                           'else assert(qWristExit(), "Review wrist Exit button missing") phase_to("stopping") end')
    base = 'local qWristExit\n' + base
    base='''local qHandModels,qOriginalModel={},ClientsideModel
local function qModel(path,...)
 local entity=qOriginalModel(path,...)
 if type(path)=="string" and path:find("c_arms",1,true) then qHandModels[#qHandModels+1]=entity end
 return entity
end
ClientsideModel=qModel
'''+base
    feature = Path(__file__).with_name("vr_combined_probe.lua").read_text(encoding="utf-8")
    move = Path(__file__).with_name("vr_move_probe.lua").read_text(encoding="utf-8")
    move = checked_replace(move, 'if phase ~= "active" then return end',
                           f'if phase ~= "active" or not nlvr.TestState() or nlvr.TestState().time < {H_END} or nlvr.TestState().time >= {L_END} then return end')
    move = checked_replace(move, 'local t = state and state.time or 0',
                           f'local t = ((state and state.time or 0) - {H_END}) / {MOVE_SCALE}')
    ui = Path(__file__).with_name("vr_ui_poc.lua").read_text(encoding="utf-8")
    ui = checked_replace(ui, 'hook.Add("PreRender", ID, function()',
                         'hook.Add("PreRender", ID, function()\n'
                         f'    if NLVR and (not nlvr.TestState() or nlvr.TestState().time < {L_END}) then return end')
    ui = checked_replace(ui, 't = time and time.time or t', f't = time and (time.time - {L_END}) * {UI_RATE} or t')
    ui = checked_replace(ui, 'once(34, "property-result",', 'once(35.5, "property-result",')
    ui = checked_replace(ui, 'testedSlider=slider', '''testedSlider=slider
        local qThink=IsValid(slider) and slider.Think
        if qThink then
            local count=0
            slider.Think=function(self,...)
                count=count+1
                local result=qThink(self,...)
                if t>=52 and t<54 then
                    local x,y=self:CursorPos()
                    self.qDragWitness={thinks=count,cursor={x,y},desktop={input.GetCursorPos()},gui={gui.MousePos()},
                        down=input.IsMouseDown(MOUSE_LEFT),value=GetConVar("nl_vr_snap_angle"):GetFloat(),menu=gui.IsGameUIVisible()}
                end
                return result
            end
        end''')
    ui = checked_replace(ui, 'value=GetConVar("nl_vr_snap_angle"):GetFloat(),uv=uv})',
                         'value=GetConVar("nl_vr_snap_angle"):GetFloat(),uv=uv,witness=IsValid(testedSlider) and testedSlider.qDragWitness})')
    typing=Path(__file__).with_name('vr_fixture_typing.lua').read_text(encoding='utf-8')
    ui = 'local QTyping=(function()\n'+typing+'\nend)()\nlocal qTyping,qTypingLast\nlocal qOldShow,qOldHide,qOldWindow,qOldProperty\n' + ui
    ui = checked_replace(ui, 'oldFrame, oldActions = native.BeginFrame, native.Actions', '''oldFrame, oldActions = native.BeginFrame, native.Actions
        qOldShow,qOldHide,qOldWindow=native.ShowKeyboard,native.HideKeyboard,native.WindowInput
        qOldProperty=properties.OnScreenClick
        properties.OnScreenClick=function(origin,direction)
            local trace=util.TraceLine{start=origin,endpos=origin+direction*32768,filter=LocalPlayer()}
            emit("property-ray-target",{entity=IsValid(trace.Entity) and trace.Entity:EntIndex(),class=IsValid(trace.Entity) and trace.Entity:GetClass(),
                fixture=IsValid(trace.Entity) and trace.Entity:GetNWBool("nlvr_ui_target"),origin=origin,direction=direction})
            return qOldProperty(origin,direction)
        end
        native.ShowKeyboard=function(...)
            local ok,detail=qOldShow(...)
            emit("keyboard-platform",{ok=ok,detail=detail,forced_fallback=CONFIG.simulate})
            if CONFIG.simulate then if ok then qOldHide() end return nil,"Simulated failure to exercise fallback" end
            return ok,detail
        end
        native.WindowInput=function(kind,...)
            local button,down=...
            local beforeMenu=gui.IsGameUIVisible()
            local ok,detail=qOldWindow(kind,...)
            if kind=="button" and t>=44 and t<47 then
                emit(down and "resume-native-down" or "resume-native-up",{menu_before=beforeMenu,posted=ok,detail=detail,info=native.Info().window_input})
            end
            return ok,detail
        end''')
    ui = checked_replace(ui, 'native.BeginFrame, native.Actions = oldFrame, oldActions',
                         'native.BeginFrame, native.Actions, native.ShowKeyboard, native.WindowInput = oldFrame, oldActions, qOldShow, qOldWindow\n            properties.OnScreenClick=qOldProperty')
    ui = checked_replace(ui, 'return oldMousePress(code)', '''if t>=31 and t<34 then
                local p=vgui.GetHoveredPanel()
                emit("property-native-press",{code=code,hover_name=IsValid(p) and p:GetName(),hover_text=IsValid(p) and p.GetText and p:GetText(),
                    cursor={input.GetCursorPos()},gui_cursor={gui.MousePos()}})
            end
            return oldMousePress(code)''')
    ui = checked_replace(ui, 'local point = tracking_point(f)', '''-- Target selection precedes this frame's production input sample, even after a model-load stall.
                if t>=27 and t<30.7 then
                    if not IsValid(propertyTarget) then for _,e in ipairs(ents.FindByClass("prop_physics")) do
                        if e:GetNWBool("nlvr_ui_target") then propertyTarget=e break end
                    end end
                    target,uv="entity",nil
                elseif t>=30.7 and t<34 then
                    local menu=tree(root("context"),function(p) return p:GetName()=="DMenu" end)
                    local option=tree(menu,function(p) return p.GetText and (p:GetText():lower()=="remove" or p:GetText():lower()=="#remove") end)
                    if IsValid(option) then target,uv="context",locate("context",option) end
                elseif t>=44 and t<47 then target,uv="flat",{140/ScrW(),(ScrH()>=1440 and 249 or 228)/ScrH()} end
                if t>=15 and t<19.5 then
                    qTyping=qTyping or QTyping.New()
                    local o=NLVR.Overlay.Objects.keyboard
                    local function keyUV(value)
                        if not o then return end
                        for _,key in ipairs(include("nlvr/modules/cl_ui_keyboard.lua").Layout(o.width,o.height)) do
                            if key.value==value then return {(key.x+key.w/2)/o.width,(key.y+key.h/2)/o.height} end
                        end
                    end
                    local wanted=keyUV(qTyping.Key()) local laser=NLVR.Debug.ui.laser
                    local over=wanted and laser and laser.panel=="keyboard" and
                        math.abs(laser.u-wanted[1])<.02 and math.abs(laser.v-wanted[2])<.02
                    qTyping.Update(FrameNumber(),IsValid(focusField) and focusField:GetText(),
                        o and o:IsVisible() and NLVR.Debug.ui.keyboard=="fallback",over)
                    wanted=keyUV(qTyping.Key())
                    if wanted then target,uv="keyboard",wanted end
                    local state=qTyping.State() local stamp=state.index..state.phase
                    if stamp~=qTypingLast then
                        qTypingLast=stamp emit("Q-controller-typing",state)
                    end
                end
                local point = tracking_point(f)''')
    ui = checked_replace(ui, 'f.right.pos = Vector(0.05, -0.25, 1.2)\n                f.right.ang = (point - f.right.pos):Angle()\n                f.right.valid = true',
                         'local hand = t >= 64 and f.left or f.right\n'
                         '                hand.pos = Vector(0.05, t >= 64 and 0.25 or -0.25, 1.2)\n'
                         '                hand.ang = (point - hand.pos):Angle()\n                hand.valid = true\n'
                         '                QFrames.Aim(hand,t>=64 and "left" or "right",point)')
    ui = checked_replace(ui, 'return a\n        end', '''if t>=15 and t<19.5 then
                a.right_trigger.state=qTyping and qTyping.Down() or false
            end
            if t >= 64 then
                a.left_b = {active=true,state=false}
                a.right_b = {active=true,state=down(66)}
                a.right_trigger = {active=true,state=false}
                a.left_trigger = {active=true,state=down(70)}
                a.right_stick = {active=true,x=0,y=t>=75 and t<77 and 0.5 or 0}
            end
            return a
        end''')
    ui += '''
local mirrorFeet
hook.Add("PreRender","q_mirror_acceptance",function()
 if not NLVR then if active then hook.Remove("PreRender","q_mirror_acceptance") end return end
 once(64,"mirror-mode",function() RunConsoleCommand("nl_vr_dominant","1") end)
 once(67,"mirror-wrist",function() capture("left-wrist") end)
 once(68,"mirror-aim",function() select("wrist_menu",button("wrist_menu","Spawn menu")) end)
 once(72,"mirror-menu",function()
  capture("left-spawn")
  emit("mirrored-menu",{main=NLVR.Input.mainHand,off=NLVR.Input.offHand,spawn_open=root("spawn")~=nil,debug=NLVR.Debug.ui})
 end)
 once(73,"mirror-ground",function()
  for _,p in ipairs(NLVR.Debug.ui.panels) do NLVR.Emit("ui_toggle",p.key) end
  target=nil RunConsoleCommand("nlvr_L_stage","reset") NativeLoaderVR.Recenter()
 end)
 once(74.5,"mirror-before",function() mirrorFeet=LocalPlayer():GetPos() end)
 once(78.5,"mirror-after",function()
  local delta=LocalPlayer():GetPos()-mirrorFeet
  emit("mirrored-movement",{main=NLVR.Input.mainHand,off=NLVR.Input.offHand,units={delta.x,delta.y,delta.z},metres=delta:Length()/NLVR.Space.scale})
 end)
 once(79,"mirror-restore",function() RunConsoleCommand("nl_vr_dominant",savedSettings.nl_vr_dominant or "0") end)
 once(80,"changed-calibration",function() NLVR.Emit("height_calibrate") end)
 once(81,"calibration-notice",function()
  emit("calibration-notice",{calibration=NLVR.Move.calibration,active_scale=NLVR.Space.scale,
      scale_cv=GetConVar("nl_vr_scale"):GetFloat(),status=NativeLoaderVR.StatusText()})
 end)
end)
'''
    review = Path(__file__).with_name('vr_combined_review.lua').read_text(encoding='utf-8')
    review=checked_replace(review,'f.hmd.valid,f.left.valid,f.right.valid=true,true,not (t>=20.4 and t<20.65)',
        'f.hmd.valid,f.left.valid,f.right.valid=true,true,not (t>=20.4 and t<20.65)\n'
        '            QFrames.Encode(f.left,"left") QFrames.Encode(f.right,"right")')
    return base + '\nlocal L_CASE = "combined"\n' + move + '\ndo\n' + feature + '\nend\ndo\n' + ui + '\nend\n' + review


def allmotion_fixture(base):
    base = moving_base(base)
    move = Path(__file__).with_name("vr_move_probe.lua").read_text(encoding="utf-8")
    latency = Path(__file__).with_name("vr_move_latency_probe.lua").read_text(encoding="utf-8")
    motor = Path(__file__).with_name("vr_move_motion_probe.lua").read_text(encoding="utf-8")
    return (base+'\nlocal L_CASE = "combined"\n'+move+'\nlocal L_LATENCY_FROM, L_LATENCY_OFFSET = 84.5, 82\n'+
            latency+'\nlocal M_FROM, M_OFFSET, M_HAS_BASE_PROBE = 106, 105, true\n'+motor)


def temporal_timeline():
    rows=[s for s in movement.timeline('latency')['steps'] if s['time']<=24.9]
    for i in range(251):
        t=i/10;actions={}
        if 5<=t<7 or 9<=t<11 or 13<=t<15:actions['left_stick']=[0,1]
        if 9<=t<11:actions['left_stick_click']=True
        if 13<=t<15:actions['left_trigger_value']=1
        rows.append({'time':25+t,'hmd':{'pos':[0,4,1.6],'ang':[0,0,0]},
                     'left':{'pos':[.25,4.25,1.2],'ang':[0,0,0]},'right':{'pos':[.25,3.75,1.2],'ang':[0,0,0]},'actions':actions})
    return {'version':1,'steps':rows}


def temporal_fixture(base):
    latency=Path(__file__).with_name('vr_move_latency_probe.lua').read_text(encoding='utf-8')
    motor=Path(__file__).with_name('vr_move_motion_probe.lua').read_text(encoding='utf-8')
    return moving_base(base)+'\n'+latency+'\nlocal M_FROM,M_OFFSET,M_FLIGHT_AT=26,25,12.2\n'+motor


def server_fixture():
    source = Path(__file__).with_name("vr_interact_poc.lua").read_text(encoding="utf-8")
    # The arena deliberately floats 24 units above BSP for no-clip prop cases.
    # A walking heavy hold must start on real ground, not fall during its grab.
    source = checked_replace(source, 'local oldFeet=ply:GetPos()', '''local oldFeet=ply:GetPos()
    local phaseFeet=base
    if phase==4 then
        local floor=util.TraceLine{start=base+Vector(0,0,64),endpos=base-Vector(0,0,128),mask=MASK_SOLID_BRUSHONLY}
        assert(floor.HitWorld and floor.HitNormal.z>.99,"Heavy walking fixture needs flat ground")
        phaseFeet=floor.HitPos+Vector(0,0,1)
        out("heavy-ground",{ground=floor.HitPos,feet=phaseFeet})
    end''')
    source=checked_replace(source,'pos=base+state.hands.right.pos-oldFeet','pos=phaseFeet+state.hands.right.pos-oldFeet')
    source=checked_replace(source,'pos=base+state.hands.left.pos-oldFeet','pos=phaseFeet+state.hands.left.pos-oldFeet')
    source=checked_replace(source,'ply:SetGravity(1) ply:SetPos(base)','ply:SetGravity(1) ply:SetPos(phaseFeet)')
    source=checked_replace(source,'if CurTime()-last<0.25 then return end last=CurTime()',
                           'if CurTime()-last<((phase==4 or phase==10) and .03 or .25) then return end last=CurTime()')
    source=checked_replace(source,'haptic_counts=pulseCounts,',
                           'haptic_counts=pulseCounts,ground=ply:OnGround(),sync_age=CurTime()-(state.lastSync or 0),'
                           'tracked=state.hands.right.valid,grip_goal=r.grip and r.grip.goal,')
    source=checked_replace(source,'''local delta=right.pos+forward*4.5-nearest.point
            for _,body in ipairs(bodies) do
                body.phys:SetPos(body.pos+delta) body.phys:SetAngles(body.ang)
                body.phys:SetVelocity(Vector()) body.phys:AddAngleVelocity(-body.phys:GetAngleVelocity())
            end''','''local delta=right.pos+forward*4.5-nearest.point
            ent:SetPos(ent:GetPos()+delta)
            for _,body in ipairs(bodies) do
                body.phys:SetPos(body.pos+delta) body.phys:SetAngles(body.ang)
                body.phys:SetVelocity(Vector()) body.phys:AddAngleVelocity(-body.phys:GetAngleVelocity()) body.phys:Wake()
            end''')
    source = checked_replace(source, 'local t=CurTime()-began',
                             f'local elapsed=CurTime()-began local t=elapsed/{PHYSICS_SCALE}')
    source = checked_replace(source, 'local record={time=t,', 'local record={elapsed_seconds=elapsed,time=t,')
    source=checked_replace(source,'if IsValid(e) and diagnostics then','''if phase==10 and IsValid(fixtures.deathrag) and diagnostics then
        local rag=fixtures.deathrag local near=diagnostics.Closest(rag,r.phys and r.phys:GetPos() or state.hands.right.pos)
        local point=IsValid(r.phys) and r.phys:GetPos() or state.hands.right.pos
        local box=Vector(state.scale*.16,state.scale*.16,state.scale*.16) local inBox=false
        for _,candidate in ipairs(ents.FindInBox(point-box,point+box)) do if candidate==rag then inBox=true end end
        record.deathrag_diagnostic={entity=rag:EntIndex(),position=rag:GetPos(),in_box=inBox,
            distance=near and near.distance,bone=near and near.bone,allowed=diagnostics.Allowed(ply,rag),buttons=state.hands.right.buttons}
    end
    if IsValid(e) and diagnostics then''')
    source = checked_replace(source,'if phase==7 and t>2.5 and not fixtures.kit then',
                             'if phase==7 and t>2.5 and not fixtures.kit and IsValid(fixtures.main) and fixtures.main:GetOn() then')
    source = checked_replace(source,'if phase==7 and t>4 and not fixtures.battery then',
                             'if phase==7 and t>4 and fixtures.kit and ply:Health()>50 and not fixtures.battery then')
    source = checked_replace(source,'if phase==7 and t>5.1 and not fixtures.ammo then',
                             'if phase==7 and t>5.1 and fixtures.battery and ply:Armor()>10 and not fixtures.ammo then')
    source = checked_replace(source, 'local d=state.interact', '''local d=state.interact
    if phase==4 and d.right.grip and not fixtures.walkingHeld then
        fixtures.walkingHeld=true ply:SetMoveType(MOVETYPE_WALK) ply:SetGravity(0)
    end''')
    source += '''
concommand.Add("nlvr_q_stage",function(p,_,a)
    if not IsValid(p) then p=Entity(1) end
    if not IsValid(p) or not (game.SinglePlayer() or p:IsListenServerHost()) then return end
    if p:HasWeapon("nlvr_hands") then p:SelectWeapon("nlvr_hands") end
    clear() phase=-1
    if not p:Alive() then p:Spawn() end
    p:SetMoveType(MOVETYPE_NOCLIP) p:SetPos(Vector(823,-657,-143)) p:SetEyeAngles(Angle())
    p:SetVelocity(-p:GetVelocity())
    if a[1]=="ui" then
        local e=spawn("prop_physics","models/props_c17/oildrum001.mdl",Vector(967,-817,-60))
        e:SetCreator(p)
        e:GetPhysicsObject():EnableMotion(false) e:SetNWBool("nlvr_ui_target",true)
    end
end)
'''
    # Keep the fixture locals independent; both command sets are legitimate admin Lua.
    move = Path(__file__).with_name("vr_move_server_probe.lua").read_text(encoding="utf-8")
    move = checked_replace(move, 'Entity(1):ConCommand("nlvr_L_stage start")', '')
    warm='''for _,model in ipairs({"models/hunter/blocks/cube2x2x1.mdl","models/hunter/blocks/cube4x4x025.mdl",\n"models/maxofs2d/button_05.mdl","models/props_c17/door01_left.mdl","models/props_junk/wood_crate001a.mdl",\n"models/props_junk/watermelon01.mdl","models/props_junk/PopCan01a.mdl","models/props_debris/wood_board04a.mdl",\n"models/Humans/Group01/male_07.mdl"}) do util.PrecacheModel(model) end\n'''
    review=Path(__file__).with_name('vr_combined_review_server.lua').read_text(encoding='utf-8')
    return warm+'do\n' + source + '\nend\ndo\n' + move + '\nend\ndo\n'+review+'\nend\n'


def rotation_amount(before,after):
    import math
    def quat(angles):
        p,y,r=[math.radians(float(v))/2 for v in angles]
        sp,cp,sy,cy,sr,cr=math.sin(p),math.cos(p),math.sin(y),math.cos(y),math.sin(r),math.cos(r)
        return (cr*cp*cy+sr*sp*sy,sr*cp*cy-cr*sp*sy,cr*sp*cy+sr*cp*sy,cr*cp*sy-sr*sp*cy)
    a,b=quat(before),quat(after)
    cosine=min(1.,abs(sum(x*y for x,y in zip(a,b))))
    return math.degrees(2*math.acos(cosine))


def tracked_curls_check(row):
    import math
    try:
        for side,wanted in (('left',[1,.8,.6,.4,.2]),('right',[.2,.4,.6,.8,1])):
            h=row[side];values=h['curls'];w=h['rendered']
            if h.get('grip') is not False or len(values)!=5 or not all(abs(a-b)<.05 for a,b in zip(values,wanted)):return False
            if len(h.get('splay',[]))!=4 or not all(math.isfinite(x) and abs(x)<.05 for x in h['splay']):return False
            if w.get('method')!='engine_bone_parent_rotations' or not w['reference_model'] or w['reference_model']!=w['current_model'] or w['current_frame']<=w['reference_frame']:return False
            if len(w['reference'])!=5 or len(w['current'])!=5:return False
            for i,(a,b,curl) in enumerate(zip(w['reference'],w['current'],wanted)):
                if len(a)!=3 or len(b)!=3 or not all(math.isfinite(x) for x in [*a,*b]):return False
                if abs(rotation_amount(a,b)-(40 if i==0 else 75)*curl)>=1:return False
        return True
    except (KeyError,TypeError,ValueError):return False


def receipt(folder):
    summary = json.loads((folder/"summary.json").read_text(encoding="utf-8"))
    console = (folder/"poc/game/console.log").read_text(encoding="utf-8", errors="replace")
    records = [json.loads(line[7:]) for line in console.splitlines() if line.startswith("NLVR_P ")]
    driver.write_json(folder/"interaction.json", records)
    p = physical_check.analyse(records)
    driver.write_json(folder/"interaction-checks.json", p)
    # Keep all raw vectors; the shortened stick/turn intervals have shorter expected distances.
    l = movement_check.check(folder, timing_scale=MOVE_SCALE)
    driver.write_json(folder/"movement-acceptance.json", l)
    import vr_combined_review
    ui = vr_combined_review.expected_close_error(menus.feature_receipt(summary, folder),summary['records'])
    driver.write_json(folder/"ui-acceptance.json", ui)
    hands = {r['label']: r for r in summary['records'] if r.get('kind') == 'Q-hands'}
    checks = {"renderer": summary['success'], "physical": p['success'], "movement": l['success'], "menus": ui['full_acceptance']}
    review=vr_combined_review.analyse(summary['records'],records)
    driver.write_json(folder/'review-acceptance.json',review)
    checks['independent_review']=review['success']
    ui_rows = {r['name']:r for r in summary['records'] if r.get('kind') == 'ui'}
    mirror = ui_rows.get('mirrored-menu', {})
    checks['mirrored_menu'] = mirror.get('main') == 'left' and mirror.get('off') == 'right' and mirror.get('spawn_open') is True
    move = ui_rows.get('mirrored-movement', {})
    delta = move.get('units', [0,0,0])
    checks['mirrored_movement'] = (move.get('main') == 'left' and move.get('off') == 'right' and
                                    abs(delta[0]-150/UI_RATE)<25 and abs(delta[1])<10)
    notice = ui_rows.get('calibration-notice', {})
    checks['calibration_notice'] = notice.get('calibration', {}).get('restart') is True and notice.get('active_scale') == 40 and 'Height calibrated.' in notice.get('status', '')
    resume=ui_rows.get('resume-native-down',{})
    checks['guarded_resume']=resume.get('menu_before') is True and resume.get('posted') is True
    property_ray=ui_rows.get('property-ray-target',{})
    property_press=ui_rows.get('property-native-press',{})
    checks['guarded_property']=(property_ray.get('fixture') is True and property_press.get('hover_text','').lower() in ('remove','#remove'))
    curls=next((r for r in summary['records'] if r.get('kind')=='Q-tracked-curls'),{})
    checks['tracked_curls']=tracked_curls_check(curls)
    held=next((r for r in summary['records'] if r.get('kind')=='Q-held-move'),{})
    before=next((r.get('feet') for r in records if r.get('phase')==4 and r.get('kind')=='begin'),None)
    travel=max((physical_check.distance(r['feet'],before) for r in records if r.get('phase')==4 and r.get('kind')=='sample'),default=0)
    checks['held_locomotion']=(travel>2 and held.get('hand',{}).get('held',0)>0 and held.get('move',{}).get('fade',1)==0)
    for label, depth in (("near-020", .2), ("near-030", .3), ("near-050", .5)):
        h = hands.get(label, {})
        checks[label] = all(abs(h.get(side, {}).get('metres', -1)-depth) < .005 and
                            h.get(side, {}).get('finger_bones') == 15 and h.get(side, {}).get('draws', 0)>0
                            for side in ('left','right'))
    result = {'success': all(checks.values()), 'checks': checks, 'hands': hands,
              'note': 'Near distances and draws are mechanical checks; whole silhouettes require eye-image review.',
              'active_seconds': END, 'movement_time_scale': MOVE_SCALE, 'ui_time_rate': UI_RATE,
              'held_locomotion_units':travel,'held_locomotion_metres':travel/40}
    driver.write_json(folder/'combined-acceptance.json', result)
    return result


def exercised_peers(records,menus=False):
    peer=next((r for r in records if r.get('kind')=='peer-final'),{})
    counts=peer.get('counts',{})
    return (peer.get('success') is True and peer.get('cycles')==2 and peer.get('exits')==2 and
        peer.get('views',0)>=2 and peer.get('bad_views',1)==0 and peer.get('hands',0)>=2 and
        (not menus or peer.get('menus',0)>=1) and counts.get('think_vr',0)>=2 and counts.get('input_vr',0)>=2 and
        counts.get('think_flat',0)>=2 and counts.get('input_flat',0)>=1 and counts.get('moving',0)>=2 and
        counts.get('view_vr',1)==0 and counts.get('view_flat',0)>=1)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--package', required=True, type=Path)
    parser.add_argument('--evidence', required=True, type=Path)
    parser.add_argument('--simulate', action='store_true')
    parser.add_argument('--case', choices=('combined', 'allmotion', 'temporal','full'), default='combined')
    parser.add_argument('--inspect-dll', type=Path, help='development-only thread clock helper; adds CPU/network observations')
    parser.add_argument('--fixes-reviewed',action='store_true',help='operator confirms Claude approved the fixed package for full acceptance')
    args = parser.parse_args(argv)
    if args.case=='full':
        import vr_full_sequence
        return vr_full_sequence.main(['--package',str(args.package),'--evidence',str(args.evidence),
            *(['--simulate'] if args.simulate else []),*(['--fixes-reviewed'] if args.fixes_reviewed else []),
            *(['--inspect-dll',str(args.inspect_dll)] if args.inspect_dll else [])])
    if args.case=='combined' and not args.fixes_reviewed:
        parser.error('full combined sequence disabled until Claude confirms the fixes-module repair; then pass --fixes-reviewed')
    original_script, original_command, lock = driver.lua_script, driver.command, driver.ExclusiveLock

    class CombinedLock(lock):
        def __init__(self, path, task, timeout=7200):
            super().__init__(path, 'VR-V2V3-Q combined acceptance', timeout)

    def script(path, config):
        config['combined']={'physical_end':P_END,'hands_end':H_END,'move_end':L_END,'physical_slot':8*PHYSICS_SCALE}
        config['q_controller_profiles']=controller_frames.profiles()
        original_script(path, config)
        factory = client_fixture if args.case == 'combined' else temporal_fixture if args.case=='temporal' else allmotion_fixture
        text = factory(path.read_text(encoding='utf-8'))
        text = controller_frames.inject(text)
        if args.inspect_dll:
            text += '\ndo\n'+Path(__file__).with_name('vr_measure_probe.lua').read_text(encoding='utf-8')+'\nend\n'
        path.write_text(text, encoding='utf-8')

    def command(arguments, evidence, label, **kwargs):
        if label == 'game':
            quit_field(evidence)
            server = server_fixture() if args.case == 'combined' else (
                Path(__file__).with_name('vr_move_server_probe.lua').read_text(encoding='utf-8')+'\n'+
                Path(__file__).with_name('vr_move_motion_server.lua').read_text(encoding='utf-8'))
            if args.inspect_dll:
                server += '\ndo\n'+Path(__file__).with_name('vr_measure_server.lua').read_text(encoding='utf-8')+'\nend\n'
            arguments = stage_fixtures(arguments, evidence, server)
            transport = evidence/'game-arguments.json'
            driver.write_json(transport, [str(v) for v in arguments[1:]])
            arguments = [Path(__file__).resolve(), '--poc-arguments', transport]
        return original_command(arguments, evidence, label, **kwargs)

    driver.lua_script, driver.command, driver.ExclusiveLock = script, command, CombinedLock
    path = driver.inside_out(args.evidence, driver.main_checkout()).with_name(args.evidence.name+'-timeline.json')
    driver.write_json(path, timeline() if args.case == 'combined' else controller_frames.natural_timeline(
        temporal_timeline() if args.case=='temporal' else movement.timeline('allmotion')))
    code = driver.main(['--package', str(args.package), '--evidence', str(args.evidence), '--seconds', str(47 if args.case=='temporal' else END if args.case == 'combined' else 127),
                        '--timeline', str(path), '--camera', '823,-657,-79,0,0,0',
                        '--minimum-free-gib',str(12 if args.case=='combined' else 8), *(['--simulate'] if args.simulate else []),
                        *(['--inspect-dll',str(args.inspect_dll)] if args.inspect_dll else [])])
    if (args.evidence/'summary.json').exists():
        # Additional canvas colour metrics are for L's semantic assertions; the production
        # driver's handle/role checker above is never replaced.
        summary = json.loads((args.evidence/'summary.json').read_text(encoding='utf-8'))
        metrics = {}
        for row in summary['records']:
            if row.get('kind') == 'capture' and row.get('ok') and row['label'].startswith('L-'):
                metrics[row['label']] = {p.name: movement.canvas_pixels(p) for p in
                                        (args.evidence/'captures'/row['label']).glob('overlay_*.png')}
        driver.write_json(args.evidence/'L-capture-metrics.json', metrics)
        if args.case == 'combined':
            result = receipt(args.evidence)
        else:
            move=movement_check.check(args.evidence) if args.case=='allmotion' else None
            if move:driver.write_json(args.evidence/'movement-acceptance.json', move)
            errors=[]
            def measured(name, function):
                try:
                    return function(args.evidence)
                except (AssertionError, KeyError, ValueError, IndexError, ZeroDivisionError) as error:
                    failure={'success':False,'error':str(error),'exception':type(error).__name__}
                    errors.append({'stage':name,**failure})
                    driver.write_json(args.evidence/(name+'-failure.json'),failure)
                    return failure
            latency = measured('latency',latency_check.analyse)
            motor = measured('motion',(lambda folder:motion_check.check(folder,(("walk",5,7,200),("sprint",9,11,400),("flight",13,15,400)),(11,12))) if args.case=='temporal' else motion_check.check)
            motor['smooth_pass'] = (len(motor.get('segments',{}))==3 and
                                    all(s['camera']['normalized_spread_percent'] <= 10 for s in motor['segments'].values())
                                    and motor['sprint_stop']['camera'] < .1)
            driver.write_json(args.evidence/'motion-analysis.json', motor)
            latency_pass = (len(latency.get('segments',{}))==3 and
                            all(s['max_error_units'] < .05 and s['step_error_max_units'] < .05 and
                                s['zero_steps_while_tracking_moves'] == 0 for s in latency['segments'].values()))
            roll=latency.get('roll',{})
            roll_pass=roll.get('camera_roll',0)>20 and roll.get('command_roll',1)==0 and roll.get('player_roll',1)==0
            # motor's own semantic receipt includes every measured interval.
            result = {'checks': {'renderer': summary['success'],
                                 'head_same_frame': latency_pass, 'head_command_roll':roll_pass, 'motor_smooth': motor.get('smooth_pass', False)},
                      'latency': latency, 'motor': motor, 'errors':errors}
            if move:result['checks']['movement']=move['success']
            result['success'] = all(result['checks'].values())
            driver.write_json(args.evidence/(args.case+'-acceptance.json'), result)
        if args.inspect_dll:
            from vr_measure import accounting,accounting_checks
            observed=accounting(summary)
            checks=accounting_checks(observed)
            driver.write_json(args.evidence/'cpu-network.json',observed)
            driver.write_json(args.evidence/'accounting-acceptance.json',{'checks':checks,'success':all(checks.values())})
            result['checks']['accounting']=all(checks.values())
            result['success']=all(result['checks'].values())
            driver.write_json(args.evidence/(args.case+'-acceptance.json'),result)
        print(json.dumps({'success':result['success'],'checks':result['checks']}, separators=(',', ':')))
        return code or (0 if result['success'] else 1)
    return code or 1


def quit_field(evidence):
    field = poc.game_processes(driver.FIELD)
    if field:
        root = driver.main_checkout()
        helper = root/'out/vr/v2/quit_field_game.py'
        with (evidence/'field-quit.log').open('w', encoding='utf-8') as stream:
            result = subprocess.run([sys.executable, str(helper)], cwd=root, stdout=stream, stderr=subprocess.STDOUT)
        driver.write_json(evidence/'field-quit.json', {'pids': field, 'helper': str(helper), 'exit': result.returncode,
                          'authority': 'User allowed ending the field game for GPU/SteamVR tests by normal console quit.'})
        if result.returncode or poc.game_processes(driver.FIELD):
            raise RuntimeError('Authorised field quit did not complete')


def stage_fixtures(arguments, evidence, server):
    """Stage private plain Lua inside the snapshotted add-on tree, avoiding 100 console fragments."""
    addon=(driver.POC/'garrysmod/addons/nlvr_q_tests').resolve()
    if not addon.is_relative_to(driver.POC.resolve()) or addon.exists():
        raise ValueError('test fixture destination is not a fresh owned PoC add-on')
    lua=addon/'lua/nlvr_q_tests';lua.mkdir(parents=True)
    fixture=Path(__file__).with_name('vr_hook_fixture.lua')
    shutil.copy2(fixture,lua/'hook_fixture.lua')
    shutil.copy2(Path(__file__).with_name('vr_hook_addon.lua'),lua/'hook_addon.lua')
    autorun=addon/'lua/autorun/nlvr_q_hook_fixture.lua'
    autorun.parent.mkdir(parents=True)
    autorun.write_text('if SERVER then AddCSLuaFile() AddCSLuaFile("nlvr_q_tests/hook_fixture.lua") end\n'
                       'local before=hook.GetTable() include("nlvr_q_tests/hook_fixture.lua").New("ulib",nil,hook)\n'
                       'for event,entries in pairs(before) do for id,fn in pairs(entries) do hook.Add(event,id,fn) end end\n',encoding='utf-8')
    source=evidence/'probe.lua'
    shutil.copy2(source,lua/'client.lua')
    server=server or '-- No server instrumentation for this control.\nreturn true\n'
    (lua/'server.lua').write_text(server,encoding='utf-8')
    (evidence/'server-fixture.lua').write_text(server,encoding='utf-8')
    launcher=evidence/'fixture-launch.lua'
    launcher.write_text('include("nlvr_q_tests/client.lua")',encoding='utf-8')
    kept=[]
    i=0
    while i<len(arguments):
        if arguments[i]=='--lua':i+=2
        else:kept.append(arguments[i]);i+=1
    kept+=['--console','lua_run include("nlvr_q_tests/server.lua")','--lua',launcher]
    driver.write_json(evidence/'private-fixture-staging.json',{'addon':str(addon),'client_sha256':driver.sha256(source),
                      'staged_client_sha256':driver.sha256(lua/'client.lua'),'server_sha256':driver.sha256(lua/'server.lua'),
                      'scope':'private test Lua only, inside the snapshotted add-on tree; standard rollback removes it'})
    return kept


if __name__ == '__main__':
    if len(sys.argv) == 3 and sys.argv[1] == '--poc-arguments':
        raise SystemExit(poc.main(json.loads(Path(sys.argv[2]).read_text(encoding='utf-8'))))
    raise SystemExit(main())
