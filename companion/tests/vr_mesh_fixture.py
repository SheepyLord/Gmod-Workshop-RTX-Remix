"""Generate independent rig/mesh witnesses from raw measurement exports only."""
from pathlib import Path
import argparse
import hashlib
import json
import math
import os
import re
from vr_mesh_measure import plane_fit

# Semantic handle regions selected on the raw XZ/YZ mesh plots, not around a product
# grip value. Cuts exclude triggers, magazines, stocks and barrels. All vertices remain.
HANDLE_CUTS={
 'w_pistol':[(0,.4,4.5),(2,-5.5,-1.5)],'w_smg1':[(0,-9,-5),(2,-9,-1.5)],
 'w_irifle':[(0,11,16),(2,-9,1.5)],'w_shotgun':[(0,13,16),(2,-9,-1)],
 'w_crossbow':[(0,2,7),(2,-9,1)],'w_annabelle':[(0,13,17),(2,-9,0)],
 'w_357':[(0,0,4),(2,-9,0)],'w_rocket_launcher':[(0,10,16),(2,-3,5)],
 'w_grenade':[(2,-1,7.6)],'w_bugbait':[],'w_physics':[(0,0,5),(2,-1,3),(1,-1,4)],
 'w_toolgun':[(0,.9,4),(2,-9,-1)],'w_medkit':[(1,-9,-2)],'camera':[(0,-9,-1),(1,-9,-2.5)]}
GUN_AXIS={'w_pistol':-1,'w_357':1,'w_irifle':-1,'w_shotgun':-1,'w_crossbow':1,
 'w_rocket_launcher':-1,'w_annabelle':-1,'w_physics':1,'w_toolgun':1}

def bounds(points):return [[min(p[i] for p in points) for i in range(3)],[max(p[i] for p in points) for i in range(3)]]

def principal(points):
    mean=[sum(p[i] for p in points)/len(points) for i in range(3)]
    cov=[[sum((p[i]-mean[i])*(p[j]-mean[j]) for p in points) for j in range(3)] for i in range(3)]
    axis=[0.,0.,0.];axis[max(range(3),key=lambda i:cov[i][i])]=1.
    for _ in range(64):
        v=[sum(row[j]*axis[j] for j in range(3)) for row in cov];size=math.sqrt(sum(x*x for x in v))
        if size<1e-12:break
        axis=[x/size for x in v]
    return axis

def shaft_sections(points):
    # Longest empty interval along the asset's longest extent identifies its straight
    # low-poly shaft. Endpoint bands come from that gap, not production cap boxes.
    extent=bounds(points);dim=max(range(3),key=lambda i:extent[1][i]-extent[0][i])
    stations=sorted(set(round(p[dim],1) for p in points))
    gaps=[(b-a,a,b) for a,b in zip(stations,stations[1:])]
    largest=max(g[0] for g in gaps)
    gap,left,right=max((g for g in gaps if g[0]>=largest*.25),key=lambda g:g[2])
    width=min(.6,gap/10)
    sections=[[p for p in points if abs(p[dim]-station)<=width] for station in (left,right)]
    across=[i for i in range(3) if i!=dim]
    ref=min(sections,key=lambda v:sum(bounds(v)[1][i]-bounds(v)[0][i] for i in across))
    centre=[(min(p[i] for p in ref)+max(p[i] for p in ref))/2 for i in across]
    radius=max(math.sqrt(sum((p[i]-c)**2 for i,c in zip(across,centre))) for p in ref)
    result=[]
    for section in sections:
        section=[p for p in section if sum((p[i]-c)**2 for i,c in zip(across,centre))<=(radius*1.3)**2]
        lo,hi=bounds(section);result.append([value for i in range(3) for value in (lo[i]-.00001,hi[i]+.00001)])
    return result

def numbers(value):
    return [float(x) for x in re.findall(r'[-+]?\d*\.?\d+(?:[eE][-+]?\d+)?',value)] if isinstance(value,str) else list(value)

def rotation(angles):
    p,y,r=map(math.radians,numbers(angles));sp,cp=math.sin(p),math.cos(p);sy,cy=math.sin(y),math.cos(y);sr,cr=math.sin(r),math.cos(r)
    return [[cp*cy,sr*sp*cy-cr*sy,cr*sp*cy+sr*sy],
            [cp*sy,sr*sp*sy+cr*cy,cr*sp*sy-sr*cy],[-sp,sr*cp,cr*cp]]

def transpose(a):return [list(v) for v in zip(*a)]
def multiply(a,b):return [[sum(a[i][k]*b[k][j] for k in range(3)) for j in range(3)] for i in range(3)]
def transform(a,p):return [sum(row[k]*p[k] for k in range(3)) for row in a]
def angles(a):return [math.degrees(math.asin(max(-1,min(1,-a[2][0])))),math.degrees(math.atan2(a[1][0],a[0][0])),math.degrees(math.atan2(a[2][1],a[2][2]))]

def hands(records):
    result={}
    for side in ('right','left'):
        label='pistol-'+side+'-side'
        row=next(r for r in records if r.get('kind')=='capture' and r.get('label')==label and not r.get('diagnostic'))
        observed=row[side];bone=observed['bones']['Hand'];origin=numbers(bone['pos']);inverse=transpose(rotation(bone['ang']))
        shown=row['shown'][side]
        # Binding is recovered from actual rendered bone and physical hand poses.
        # Do not import the product's reported palm frame or its grip field.
        frame={'pos':transform(inverse,[x-y for x,y in zip(numbers(shown['pos']),origin)]),
               'ang':angles(multiply(inverse,rotation(shown['ang']))),'calibrated':True}
        local={name:transform(inverse,[x-y for x,y in zip(numbers(p['pos']),origin)]) for name,p in observed['bones'].items()}
        result[side]={'frame':frame,'bones':local,'model':observed['model'],'source_capture':label}
    return result

def build(exports,hand_records):
    models={}
    for data in exports:
        for name,row in data.items():
            path=row.get('path') or 'models/weapons/'+name+'.mdl'
            bone=row['bones'].get('ValveBiped.Bip01_R_Hand')
            if not bone:raise ValueError('authored holding-hand bone absent: '+path)
            spec={'kind':'rig_bone','grip_bone':'ValveBiped.Bip01_R_Hand'}
            raw=row['vertices'];vertices=sorted({tuple(p) for p in raw})
            if name in ('w_crowbar','w_stunbaton'):
                spec['kind']='shaft';spec['shaft_caps']=shaft_sections(raw)
            elif name in HANDLE_CUTS:
                cuts=HANDLE_CUTS[name];handle=[p for p in raw if all(lo<p[axis]<hi for axis,lo,hi in cuts)]
                if not handle:raise ValueError('semantic handle region has no vertices: '+name)
                spec['handle_cuts']=cuts;spec['handle_bounds']=bounds(handle)
                if name not in ('w_bugbait','w_grenade','w_medkit','w_rocket_launcher'):spec['handle_axis']=principal(handle)
            if name=='w_smg1':
                spec['barrel_caps']=True;spec['barrel_fit']=plane_fit(raw);spec['barrel_tolerance_degrees']=.1
                if spec['barrel_fit']['angular_uncertainty_degrees']>=.05:raise ValueError('barrel fit too uncertain')
            if name in GUN_AXIS:spec['gun_axis']=[GUN_AXIS[name],0,0]
            attachments={}
            exported=row.get('attachments') or {}
            if isinstance(exported,list):exported={a['name']:a for a in exported}
            for key,value in exported.items():
                if key.isdigit():continue
                if 'pose' in value:attachments[key]=value
                else:
                    index=value.get('id') or value.get('ID')
                    if index is None:
                        index=next((int(k) for k,v in exported.items() if k.isdigit() and v==value),None)
                    # Exporters without numeric aliases still keep named semantic references.
                    attachments[key]={'id':index,'pose':value}
            models[path]={'spec':spec,'vertices':vertices,'bone_pose':bone,
                          'bounds':[numbers(row['lo']),numbers(row['hi'])],'attachments':attachments}
    return {'models':dict(sorted(models.items())),'hands':hands(hand_records)}

def generate(model_paths,hand_path):
    sources=[];exports=[]
    for path in [*model_paths,hand_path]:
        path=Path(path)
        if path.resolve().suffix.lower()!='.json':raise ValueError('only declared raw JSON measurement exports are accepted')
        content=path.read_bytes()
        name=os.path.relpath(path.resolve(),Path(__file__).resolve().parents[2]).replace('\\','/')
        sources.append({'file':name,'sha256':hashlib.sha256(content).hexdigest()})
        value=json.loads(content)
        if Path(path)==Path(hand_path):hand_records=value
        else:exports.append(value)
    result=build(exports,hand_records)
    result['provenance']={'generator':'companion/tests/vr_mesh_fixture.py','sources':sources,
        'grips':'full raw geometry, independently selected handle envelope/centreline and authored bone versus drawn finger circle; no product grip fields/tables',
        'binding':'physical hand pose relative to actually rendered hand bone; no reported palm/grip frame'}
    return result

def main(argv=None):
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--models',type=Path,action='append',required=True)
    p.add_argument('--hands',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args(argv)
    result=generate(a.models,a.hands);a.output.parent.mkdir(parents=True,exist_ok=True)
    a.output.write_text(json.dumps(result,indent=2,sort_keys=True)+'\n',encoding='utf-8')
    print('Generated',len(result['models']),'authored-bone/mesh witnesses; no product files read.')
    return 0

if __name__=='__main__':raise SystemExit(main())
