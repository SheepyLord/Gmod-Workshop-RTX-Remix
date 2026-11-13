"""Q4's all-class natural-hold capture matrix, using C's reviewed frame observer."""
from pathlib import Path
import json
import base64
import sys
import vr_frames_poc as frames
import vr_weapons_poc as weapons


CLASSES=(*weapons.CLASSES,'nlvr_frames_annabelle')

def phases(side):
    return [(cls+'-'+side+'-side',cls,int(side=='left')) for cls in CLASSES]


def muzzle_checks(rows):
    from vr_frames_analyse import distance
    captures=[r for r in rows if r.get('kind')=='capture' and r.get('weapon')]
    samples=[];required=set();seen=set()
    guns={'weapon_pistol','weapon_357','weapon_smg1','weapon_ar2','weapon_shotgun','weapon_crossbow','weapon_rpg','weapon_physgun','gmod_tool','nlvr_frames_annabelle'}
    for row in captures:
        cls=row['weapon']['class']
        if cls in guns:required.add(cls)
        witness=row.get('muzzle_witness')
        if not witness or not row.get('muzzle',{}).get('pos'):continue
        if cls=='weapon_physgun' and (witness.get('source')!='asset_named_core_and_addon_beam' or witness.get('independent_source')!='model_attachment_named_core' or not witness.get('beam_pos')):continue
        seen.add(cls)
        samples.append({'class':cls,'hand':row['weapon']['hand'],'source':witness['source'],
            'error_m':distance(witness['pos'],row['muzzle']['pos'])/row['scale'],
            'beam_error_m':distance(witness['pos'],witness['beam_pos'])/row['scale'] if cls=='weapon_physgun' else 0})
    checks={'all_classes':{r['weapon']['class'] for r in captures}>=set(CLASSES),
        'independent_emitters':bool(required) and required<=seen,
        'muzzle_within_1cm':bool(samples) and all(r['error_m']<=.01 and r['beam_error_m']<=.01 for r in samples)}
    return {'checks':checks,'samples':samples,'missing_emitters':sorted(required-seen),'success':all(checks.values())}


def main(argv=None):
    argv=list(sys.argv[1:] if argv is None else argv)
    side='right'
    export='--export-meshes' in argv
    if export:argv.remove('--export-meshes')
    if '--left-hand' in argv:
        argv.remove('--left-hand')
        side='left'
    frames.PHASES=phases(side)
    if export:
        frames.PHASES=[('empty','nlvr_hands',0)]
        original=frames.driver.lua_script
        def script(path,config):
            original(path,config)
            with path.open('a',encoding='utf-8') as stream:
                stream.write('\ndo\n'+Path(__file__).with_name('vr_v4_meshes.lua').read_text()+'\nend\n')
        frames.driver.lua_script=script
    evidence=Path(argv[argv.index('--evidence')+1]).resolve()
    result=frames.main(argv)
    if export:
        chunks={};models={}
        for line in (evidence/'poc/game/console.log').read_text(errors='replace').splitlines():
            if not line.startswith('NLVR_QMODEL '):continue
            name,part,data=line[12:].split(' ',2);i,n=map(int,part.split('/'))
            chunks.setdefault(name,{})[i]=data
            if len(chunks[name])==n:
                models[name]=json.loads(base64.b64decode(''.join(chunks[name][i] for i in range(1,n+1))))
                del chunks[name]
        frames.driver.write_json(evidence/'models.json',models)
        print(json.dumps({'exported_models':len(models),'incomplete':len(chunks)}))
        return result or (0 if len(models)==16 and not chunks else 1)
    if (evidence/'frames.json').exists():
        rows=json.loads((evidence/'frames.json').read_text())
        result_checks=muzzle_checks(rows);checks=result_checks['checks'];muzzles=result_checks['samples']
        frames.driver.write_json(evidence/'muzzle-checks.json',result_checks)
        print(json.dumps({'geometry_success':all(checks.values()),'muzzle_samples':len(muzzles),
                          'max_error_m':max((r['error_m'] for r in muzzles),default=None)}))
        if not all(checks.values()):return 1
    return result


if __name__=='__main__':
    if len(sys.argv)==3 and sys.argv[1]=='--poc-arguments':
        raise SystemExit(frames.poc.main(json.loads(Path(sys.argv[2]).read_text())))
    raise SystemExit(main())
