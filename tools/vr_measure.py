"""Measure a complete VR package on the production driver with explicit timing intervals."""
from __future__ import annotations
import argparse
import copy
import json
import math
from pathlib import Path
import statistics
import struct
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path[:0] = [str(ROOT/'tools'), str(ROOT/'companion/tests')]
import vr_session as driver
import vr_combined_session as combined
import poc_session as poc
import vr_fixture_frames as frames


def weapon_witness(summary, weapon):
    """Actual sampled model/draw activity, rather than the requested loadout."""
    active=next((r['seconds'] for r in summary['records'] if r.get('kind')=='running'),None)
    rows=[r.get('framework',{}).get('debug',{}).get('weapons',{}) for r in summary['records']
          if r.get('kind')=='sample' and r.get('phase')=='active' and active is not None
          and active+10<=r['seconds']<=active+35]
    valid=len(rows)>=10 and all(r.get('class')==weapon and r.get('model') and r.get('hand') in ('left','right') for r in rows)
    drawn=valid and rows[-1].get('draws',0)>rows[0].get('draws',0)
    return {'success':bool(drawn),'requested':weapon,'samples':len(rows),
            'models':sorted({r['model'] for r in rows if r.get('model')}),
            'draws_delta':rows[-1].get('draws',0)-rows[0].get('draws',0) if rows else 0}


def steady(summary, begin=10, end=35):
    active = next((r['seconds'] for r in summary['records'] if r.get('kind') == 'running'), None)
    if active is None:
        return {'success': False, 'reason': 'no running interval'}
    rows = [r for r in summary['records'] if r.get('kind') == 'sample' and r.get('phase') == 'active'
            and active+begin <= r['seconds'] <= active+end and r.get('info',{}).get('state') == 2]
    if len(rows) < 10:
        return {'success': False, 'reason': 'fewer than ten one-second samples'}
    first, last = rows[0], rows[-1]
    elapsed = last['seconds']-first['seconds']
    def delta(key): return last['info'][key]-first['info'][key]
    profiles = [r for r in summary['profiles'] if first['camera']['sequence'] <= r['pose'] <= last['camera']['sequence']
                and r['coverage_known'] and r['untracked_submissions'] == 0]
    passes = {name: statistics.mean(p['passes'][name]['gpu_ms'] for p in profiles)
              for name in profiles[0]['passes']} if profiles else {}
    cpu=None
    a,b=first.get('inspection',{}),last.get('inspection',{})
    if a.get('thread_id')==b.get('thread_id') and a.get('thread_cpu_ms') is not None and b.get('thread_cpu_ms') is not None:
        cpu=(b['thread_cpu_ms']-a['thread_cpu_ms'])/max(1,delta('framesSubmitted'))
    return {'success': summary['success'] and bool(profiles), 'sample_seconds': [first['seconds'],last['seconds']],
            'elapsed_seconds': elapsed, 'samples': len(rows), 'profiles': len(profiles),
            'rendered_fps': delta('framesRendered')/elapsed,
            'submitted_pairs_s': delta('framesSubmitted')/elapsed, 'submitted_pairs': delta('framesSubmitted'),
            'presents': delta('presents'), 'reprojected': delta('reprojected'), 'dropped': delta('dropped'),
            'reprojected_percent': 100*delta('reprojected')/delta('presents') if delta('presents') else None,
            'gpu_pass_mean_ms': passes, 'gpu_command_and_sdk_mean_ms': sum(passes.values()) if passes else None,
            'gpu_elapsed_span_mean_ms': statistics.mean(p['gpu_total_ms'] for p in profiles) if profiles else None,
            'render_thread_cpu_mean_ms': statistics.mean(p['render_thread_cpu_ms'] for p in profiles) if profiles else None,
            'render_thread_cpu_cumulative_average_mean_ms':statistics.mean(p['render_thread_cpu_average_ms'] for p in profiles) if profiles else None,
            'game_thread_cpu_ms_per_submitted_pair':cpu,
            'eye': [last['info']['eyeWidth'],last['info']['eyeHeight']],
            'centre': [last['info']['centreWidth'],last['info']['centreHeight']],
            'traced': [last['info']['renderWidth'],last['info']['renderHeight']],
            'refresh_hz': last['info']['refresh'], 'off': False}


def accounting(summary):
    samples = [r for r in summary['records'] if r.get('kind') == 'Q-profile' and r.get('label') == 'active']
    result = {'note': 'Exclusive game-thread callback CPU; quantized Windows accounting, wrapper/clock overhead included.',
              'profiles': []}
    for r in samples:
        result['profiles'].append({'frames': r['frames'], 'elapsed_seconds': r['elapsed'],
            'frame_denominator':r.get('frame_denominator','Active PostRender callbacks (earlier probe)'),
            'postrender_callbacks':r.get('postrender_callbacks',r['frames']),
            'source_frame_first':r.get('source_frame_first'),'source_frame_last':r.get('source_frame_last'),
            'modules': {name: {**values, 'cpu_ms_per_frame': values['cpu_ms']/r['frames'],
                               'cycles_per_frame': values['cycles']/r['frames'],
                               'elapsed_ms_per_frame': values['wall_ms']/r['frames']}
                        for name, values in r['modules'].items()},
            'client_messages': {kind: {**v, 'messages_s':v['count']/r['elapsed'], 'engine_bytes_s':v['bytes']/r['elapsed']}
                                for kind,v in r['client_messages'].items()},
            'other_client_lua_messages':r.get('other_client_lua_messages',{})})
    result['server_network'] = [r for r in summary['records'] if r.get('kind') == 'Q-server-network']
    result['server_profiles'] = [r for r in summary['records'] if r.get('kind') == 'Q-server-profile']
    result['off'] = [r for r in summary['records'] if r.get('kind') == 'Q-off-profile']
    return result


def accounting_checks(result):
    clients=result.get('profiles',[]);servers=result.get('server_profiles',[])
    off=result.get('off',[]);network=result.get('server_network',[])
    return {
        'client_callbacks':bool(clients) and all(r['frames']>0 and r['elapsed_seconds']>0 and
            all(r['modules'].get(k,{}).get('calls',0)>0 for k in ('core','hud','hands','move','ui','interact')) for r in clients),
        'server_callbacks':bool(servers) and all(r['ticks']>0 and r['elapsed']>0 and
            all(r['modules'].get(k,{}).get('calls',0)>0 for k in ('core','move','interact')) for r in servers),
        'client_sync_observed':bool(clients) and all(r['client_messages'].get('3',{}).get('count',0)>0 for r in clients),
        'server_state_observed':bool(network) and all(isinstance(r.get('messages'),dict) and r['messages'].get('41',{}).get('count',0)>0 and r['elapsed']>0 for r in network),
        'off_registry_absent':bool(off) and all(not r.get('global') and not r.get('receiver') for r in off),
    }


def timeline(seconds):
    rows = []
    for i in range(int((seconds+5)*4)+1):
        t=i/4
        rows.append({'time':t,'hmd':{'pos':[0,.001*math.sin(t*.1),1.6],'ang':[0,.01*math.sin(t*.2),0]},
                     **{h:{'pos':[1.1,s*.22,1.6],'ang':[-35,0,0]}
                        for h,s in (('left',1),('right',-1))}, 'actions':{}})
    return frames.natural_timeline({'version':1,'steps':rows})


def main(argv=None):
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--package',type=Path,required=True)
    p.add_argument('--evidence',type=Path,required=True)
    p.add_argument('--map',choices=('gm_construct','modern_house'),default='gm_construct')
    p.add_argument('--window',choices=('1280x720','3840x2160'),default='1280x720')
    p.add_argument('--near',action='store_true',help='same visible hands, plus a small world cube with its mesh front 0.2 m from the head')
    p.add_argument('--profile-modules',action='store_true',help='additional callback-clock profiling; normal GPU comparisons leave it off')
    p.add_argument('--weapon',choices=('weapon_pistol','weapon_smg1','weapon_physgun'),help='fixed armed control; no firing or world targets')
    p.add_argument('--inspect-dll',type=Path,default=ROOT/'out/vr/v2q/inspect/gmcl_nlvrqinspect_win64.dll')
    args=p.parse_args(argv)
    if not args.inspect_dll.is_file(): p.error('Build the read-only helper with tools/vr_measure_build.ps1')
    original_script,original_command,lock=driver.lua_script,driver.command,driver.ExclusiveLock

    class MeasurementLock(lock):
        def __init__(self,path,task,timeout=7200): super().__init__(path,'VR-V2V3-Q measurement',timeout)

    def script(path,config):
        config['q_controller_profiles']=frames.profiles()
        original_script(path,config)
        text=frames.inject(path.read_text(encoding='utf-8'))
        if args.profile_modules:
            text+='\ndo\n'+(ROOT/'companion/tests/vr_measure_probe.lua').read_text(encoding='utf-8')+'\nend\n'
        if args.near:
            text+='''
local nearCube
hook.Add("PreRender","q_near_cube",function()
 if phase=="active" and NLVR and not nearCube then
  nearCube=ClientsideModel("models/hunter/blocks/cube025x025x025.mdl",RENDERGROUP_OPAQUE)
  assert(IsValid(nearCube),"near cube creation failed")
  local minimum=math.huge
  for _,mesh in ipairs(util.GetModelMeshes(nearCube:GetModel()) or {}) do
   for _,vertex in ipairs(mesh.triangles or {}) do minimum=math.min(minimum,vertex.pos.x) end
  end
  assert(minimum<math.huge,"near cube has no visible mesh vertices")
  nearCube:SetModelScale(0.1,0) nearCube:SetAngles(NLVR.Pose.head.ang)
  local centre=NLVR.Space.scale*0.2-minimum*0.1
  nearCube:SetPos(NLVR.Pose.head.pos+NLVR.Pose.head.ang:Forward()*centre)
  emit("Q-near-object",{front_metres=0.2,centre_metres=centre/NLVR.Space.scale,mesh_minimum_x=minimum,
      model=nearCube:GetModel(),model_scale=0.1,position=nearCube:GetPos()})
 elseif phase=="flat-after" then
  if IsValid(nearCube) then nearCube:Remove() end hook.Remove("PreRender","q_near_cube")
 end
end)
'''
        path.write_text(text,encoding='utf-8')

    def command(arguments,evidence,label,**kwargs):
        if label=='game':
            combined.quit_field(evidence)
            code=(ROOT/'companion/tests/vr_measure_server.lua').read_text(encoding='utf-8') if args.profile_modules else ''
            if args.weapon:
                code+='\nlocal p=Entity(1) p:Give("'+args.weapon+'",true) p:SelectWeapon("'+args.weapon+'")\n'
            arguments=combined.stage_fixtures(arguments,evidence,code)
            driver.write_json(evidence/'limited-measurement-policy.json',{'weapon':args.weapon,'targets':'none','damage':False,'world_entity_removal':False,'controllers':'off; scripted poses with recorded Index components; not worn'})
            transport=evidence/'game-arguments.json'
            driver.write_json(transport,[str(v) for v in arguments[1:]])
            arguments=[ROOT/'companion/tests/vr_combined_session.py','--poc-arguments',transport]
        return original_command(arguments,evidence,label,**kwargs)

    driver.timeline,driver.lua_script,driver.command,driver.ExclusiveLock=timeline,script,command,MeasurementLock
    options=['--package',str(args.package),'--evidence',str(args.evidence),'--seconds','45','--window',args.window,
             '--map',args.map,'--inspect-dll',str(args.inspect_dll)]
    if args.map=='modern_house': options+=['--mount-workshop','3495468649','--camera','80,928,545,0,0,0']
    code=driver.main(options)
    if (args.evidence/'summary.json').exists():
        summary=json.loads((args.evidence/'summary.json').read_text(encoding='utf-8'))
        result=steady(summary)
        result.update(map=args.map,window=args.window,near_object=args.near,accounting=accounting(summary))
        result['package']={'path':str(args.package.resolve()),'sha256':driver.sha256(args.package)}
        if args.weapon:
            result['weapon_witness']=weapon_witness(summary,args.weapon)
            result['success'] &= result['weapon_witness']['success']
        result['module_profiler']=args.profile_modules
        result['near_object_geometry']=[r for r in summary['records'] if r.get('kind')=='Q-near-object']
        depths=[]
        for path in (args.evidence/'captures').glob('*/frame_minimum_depth.f32'):
            data=path.read_bytes()
            if len(data)==4:
                value=struct.unpack('<f',data)[0]
                scale=next((r.get('framework',{}).get('debug',{}).get('move',{}).get('space',{}).get('scale')
                            for r in summary['records'] if r.get('framework',{}).get('debug',{}).get('move',{}).get('space',{}).get('scale')),None)
                depths.append({'capture':path.parent.name,'view_depth_units':value,'scale':scale,'view_depth_metres':value/scale if scale else None})
        result['gpu_frame_minimum_depth']=depths
        neutral=next((d['view_depth_metres'] for d in depths if d['capture']=='neutral'),None)
        result['scenario_checks']={'refresh_90_hz':result.get('refresh_hz')==90,
                                   'gpu_depth_verified':neutral is not None and (.195<=neutral<=.205 if args.near else neutral>.4)}
        result['success'] &= all(result['scenario_checks'].values())
        driver.write_json(args.evidence/'measurements.json',result)
        print(json.dumps({'success':result['success'],'evidence':str(args.evidence),'weapon':args.weapon,'submitted_pairs_s':result.get('submitted_pairs_s')}))
        return code or (0 if result['success'] else 1)
    return code or 1


if __name__=='__main__': raise SystemExit(main())
