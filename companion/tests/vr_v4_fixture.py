"""Shared natural-frame, dominant-hand and functional-clock adapters for W/K/T fixtures."""
from pathlib import Path
import copy
import hashlib
import json
import re

ROOT=Path(__file__).resolve().parents[2]
CLIENTS={'weapons':'vr_weapons_poc_client.lua','reload':'vr_reload_poc_client.lua','tools':'vr_tools_poc_client.lua'}


def mirror_layout(data):
    """Reflect hand locations and head look, but retain the declared world hand rotations."""
    result=copy.deepcopy(data)
    for step in result['steps']:
        left,right=step['left'],step['right']
        left['pos'][1]*=-1;right['pos'][1]*=-1
        step['left'],step['right']=right,left
        if 'hmd' in step:
            step['hmd']['pos'][1]*=-1
            for axis in (1,2):step['hmd']['ang'][axis]*=-1
        actions={}
        for key,value in step.get('actions',{}).items():
            if key.startswith('left_'):key='right_'+key[5:]
            elif key.startswith('right_'):key='left_'+key[6:]
            actions[key]=value
        step['actions']=actions
    return result


def canonical_calibration(records,left):
    records=copy.deepcopy(records)
    if left:
        for row in records:
            if row.get('kind')=='calibration':row['port_tracking'][1]*=-1
    return records


def input_data(data,left):
    import vr_fixture_frames as frames
    return frames.natural_timeline(mirror_layout(data) if left else data)


def configure(config,role,left,data):
    import vr_fixture_frames as frames
    config.update(q_controller_profiles=frames.profiles(),q_input_steps=data['steps'],
                  fixture_dominant=int(left),fixture_role=role,
                  fixture_layout='mirrored hand locations; declared world hand rotations retained')


def physical_fields(text):
    pattern=r'(\b(?:frame|f|actions|a|hands|history|interact|Hand|Pose|Input|shown|skeletons|frames)\.)(left|right)(?=_|\b)'
    return re.sub(pattern,lambda m:m[1]+('right' if m[2]=='left' else 'left'),text)


def server_source(text,left):return physical_fields(text) if left else text


def prepare(text,role,left):
    import vr_fixture_frames as frames
    marker=(Path(__file__).with_name(CLIENTS[role]).read_text(encoding='utf-8').splitlines())[0]
    if marker not in text and role=='reload':marker=Path(__file__).with_name('vr_reload_holster_client.lua').read_text(encoding='utf-8').splitlines()[0]
    if text.count(marker)!=1:raise ValueError('cannot locate canonical '+role+' observer')
    at=text.index(marker);before,tail=text[:at],text[at:]
    if left:tail=physical_fields(tail)
    tail=re.sub(r'((?:nl_vr_)?dominant\s*=\s*)"0"',lambda m:m[1]+'"'+str(int(left))+'"',tail)
    if role=='tools':
        side='left' if left else 'right'
        find=f'if target then frame.{side}.ang = (target - frame.{side}.pos):Angle() end'
        if tail.count(find)!=1:raise ValueError('tools target contract changed')
        tail=tail.replace(find,f'if target then frame.{side}.ang=(target-frame.{side}.pos):Angle() qNaturalTarget=target end')
        find='return frame, detail'
        if tail.count(find)!=1:raise ValueError('tools return contract changed')
        tail=tail.replace(find,f'''if timeNow>26 then
                        if qNaturalTarget then QFrames.Aim(frame.{side},"{side}",qNaturalTarget)
                        else QFrames.Encode(frame.{side},"{side}") end
                    end
                    return frame, detail''')
        find='local frame, detail = originalFrame(...)'
        if tail.count(find)!=1:raise ValueError('tools frame contract changed')
        tail=tail.replace(find,find+'\n                    local qNaturalTarget')
    text=before+tail
    clock=Path(__file__).with_name('vr_combined_clock.lua').read_text(encoding='utf-8')
    text='local QFixtureClock=(function()\n'+clock+'\nend)()\nlocal qFixtureClock\n'+text
    find='originalBegin, originalCamera, originalCreate = native.BeginFrame, native.SetFrameCamera, native.OverlayCreate'
    if text.count(find)!=1:raise ValueError('shared attach contract changed')
    text=text.replace(find,'''qFixtureClock=QFixtureClock.New{Native=native,Steps=CONFIG.q_input_steps,BeginAt=0,
EngineTime=function() return engine.TickCount()*engine.TickInterval() end,WallTime=SysTime,Paused=function() return gui.IsGameUIVisible() end}
'''+find)
    text=text.replace('local t = now - activeAt','local t = qFixtureClock and native.TestState().time or now-activeAt')
    find='native.BeginFrame, native.SetFrameCamera, native.OverlayCreate, native.Capture = originalBegin, originalCamera, originalCreate, originalCapture'
    if text.count(find)!=1:raise ValueError('shared restore contract changed')
    text=text.replace(find,find+'\n        if qFixtureClock then emit("V4-functional-clock",qFixtureClock.Stats()) qFixtureClock.Stop() end')
    text=frames.inject(text)
    text+='''
do
local prepared=false
hook.Add("Think","q_v4_fixture_prepare",function()
 if prepared or not NLVR or NativeLoaderVR.state~="running" then return end
 prepared=true
 -- The shared probe faces the requested fixture yaw (weapons and reload 180, tools 0); never zero it here.
 for _,entry in ipairs(NLVR.Registry.entries) do if entry.module.name=="move" then
  entry.ctx.mover(-30,function(cmd) cmd:ClearMovement() cmd:ClearButtons() cmd:SetMouseX(0) cmd:SetMouseY(0) end)
 end end
end)
end
'''
    return text


def preferences(role,left):
    values={'nl_vr_dominant':int(left),'nl_vr_scale':40,'nl_vr_height':0,'nl_vr_seated':0,
        'nl_vr_gun_angle':0,'nl_vr_foregrip':1,'nl_vr_physical_reload':1,'nl_vr_ammo_counter':1}
    return {key:str(value) for key,value in values.items()}


def stage(arguments,evidence,server,role,left):
    import vr_combined_session as combined
    import vr_session as driver
    server=server_source(server,left)
    arguments=combined.stage_fixtures(arguments,evidence,server)
    addon=driver.POC/'garrysmod/addons/nlvr_q_tests/lua'
    prefs=addon/'autorun/client/zz_nlvr_q_preferences.lua';prefs.parent.mkdir(parents=True,exist_ok=True)
    values=preferences(role,left)
    prefs.write_text('local values=util.JSONToTable([==['+json.dumps(values)+']==])\n'
        'for name,value in pairs(values) do if GetConVar(name) then RunConsoleCommand(name,value) end end\n',encoding='utf-8')
    autorun=addon/'autorun/nlvr_q_hook_fixture.lua'
    with autorun.open('a',encoding='utf-8') as stream:stream.write('\nif SERVER then AddCSLuaFile("autorun/client/zz_nlvr_q_preferences.lua") end\n')
    driver.write_json(evidence/'handed-fixture.json',{'role':role,'dominant':'left' if left else 'right',
        'preferences':values,'scope':'declared private PoC setup before probe baseline; snapshot restores original files',
        'probe_sha256':driver.sha256(evidence/'probe.lua'),'server_sha256':driver.sha256(evidence/'server-fixture.lua'),
        'preferences_sha256':driver.sha256(prefs),
        'adapter_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        'controller_status':'scripted natural frames; absent live components retained and labelled; no live finger claim'})
    return arguments
