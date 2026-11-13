"""Independent mesh-plane and placement metrology; no product placement tables."""
import math

def dot(a,b):return sum(x*y for x,y in zip(a,b))
def sub(a,b):return tuple(x-y for x,y in zip(a,b))
def cross(a,b):return (a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0])
def plane_fit(points):
    maximum=max(p[0] for p in points)
    cap=[p for p in points if p[0]>maximum-.15]
    if len(cap)<3:raise ValueError('barrel cap absent')
    mean=tuple(sum(p[i] for p in cap)/len(cap) for i in range(3))
    u=max((sub(p,mean) for p in cap),key=lambda v:dot(v,v))
    v=max((sub(p,mean) for p in cap),key=lambda v:dot(cross(u,v),cross(u,v)))
    normal=cross(u,v);length=math.sqrt(dot(normal,normal))
    if length<1e-10:raise ValueError('degenerate barrel cap')
    normal=tuple(x/length*(1 if normal[0]>=0 else -1) for x in normal)
    residual=max(abs(dot(sub(p,mean),normal)) for p in cap)
    if residual>.03:raise ValueError('barrel cap is not planar')
    spread=math.sqrt(dot(cross(u,v),cross(u,v))/dot(u,u))
    uncertainty=math.degrees(math.atan2(2*(residual+.0001),spread))
    return {'axis':normal,'cap_vertices':len(cap),'max_residual_units':residual,
            'export_position_allowance_units':.0001,'angular_uncertainty_degrees':uncertainty}

def plane_axis(points):return plane_fit(points)['axis']

def placement_checks(grip_error,shaft=False,mount=0):
    return {'mesh_grasp':grip_error is not None and 0<=grip_error<.005,
            'wrist_envelope':math.isfinite(mount) and (not shaft or mount<.12)}
