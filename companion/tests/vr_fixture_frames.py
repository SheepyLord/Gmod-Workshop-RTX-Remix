"""Natural-pose conversion and recorded-component fallback for integrated VR fixtures."""
import copy
import json
from pathlib import Path
from vr_frames_poc import controller_offsets, angle, transpose, multiply, mv
from vr_frames_weapons_poc import rotation

ROOT=Path(__file__).resolve().parents[2]


def profiles():
    source=json.loads((ROOT/'vr/native/sim/index-v1.json').read_text())['controllers']
    basis=[[0,0,-1],[-1,0,0],[0,1,0]]
    result={}
    for side,(natural,palm) in controller_offsets().items():
        data=source[side]
        result[side]={'model':data['model'],
            'aim':{'pos':mv(basis,[r[3] for r in data['tip']]),'ang':angle(transpose(natural))},
            'hand':{'pos':palm,'ang':angle(transpose(natural))},
            'wrist':{'pos':mv(basis,[r[3] for r in data['wrist']]),'ang':angle(multiply(multiply(basis,[r[:3] for r in data['wrist']]),transpose(basis)))}}
    return result


def natural_timeline(data):
    data=copy.deepcopy(data)
    for step in data['steps']:
        for side,(natural,palm) in controller_offsets().items():
            if side not in step:continue
            pose=step[side]
            raw=multiply(rotation(pose['ang']),natural)
            offset=mv(raw,palm)
            pose['pos']=[a-b for a,b in zip(pose['pos'],offset)]
            pose['ang']=angle(raw)
    return data


def inject(text):
    """Keep live component receipts; supply recorded Index components only when absent."""
    setup=Path(__file__).with_suffix('.lua').read_text(encoding='utf-8')
    marker='local f, detail = originalBegin(...)'
    if text.count(marker)!=1:raise ValueError('shared BeginFrame probe changed')
    at=text.index('\n',text.index('local CONFIG = util.JSONToTable('))+1
    text=text[:at]+'local QFrames=(function()\n'+setup+'\nend)().New(CONFIG.q_controller_profiles)\n'+text[at:]
    return text.replace(marker,marker+'\n        if f then QFrames.Components(f) end',1)
