"""Model-space line and joint metrology; no renderer/SteamVR or optional packages."""
import math
from pathlib import Path


def add(a,b): return tuple(x+y for x,y in zip(a,b))
def sub(a,b): return tuple(x-y for x,y in zip(a,b))
def mul(a,s): return tuple(x*s for x in a)
def dot(a,b): return sum(x*y for x,y in zip(a,b))
def length(a): return math.sqrt(dot(a,a))
def unit(a): return mul(a,1/length(a))


def line(points):
    centre=tuple(sum(p[i] for p in points)/len(points) for i in range(3))
    cov=[[sum((p[i]-centre[i])*(p[j]-centre[j]) for p in points) for j in range(3)] for i in range(3)]
    axis=[0,0,0];axis[max(range(3),key=lambda i:cov[i][i])]=1
    for _ in range(80):
        axis=unit(tuple(dot(row,axis) for row in cov))
    return {"pos":centre,"axis":axis,"points":len(points)}


def axis_error(hand,handle,span=.06):
    errors=[]
    for t in (-span/2,0,span/2):
        d=sub(add(hand["pos"],mul(hand["axis"],t)),handle["pos"])
        errors.append(length(sub(d,mul(handle["axis"],dot(d,handle["axis"])))))
    return {"centre_m":errors[1],"rms_m":math.sqrt(sum(x*x for x in errors)/3),"max_m":max(errors),
            "angle_deg":math.degrees(math.acos(min(1,abs(dot(hand["axis"],handle["axis"])))))}


def handle_model(path,side):
    vertices=[tuple(map(float,l.split()[1:4])) for l in Path(path).read_text(encoding="utf-8").splitlines() if l.startswith("v ")]
    sections=[]
    for z in (.085,.095,.105,.115,.125,.135,.145):
        selected=[p for p in vertices if abs(p[2]-z)<.003 and p[0]*(1 if side=="right" else -1)<.025]
        if len(selected)<4: raise ValueError("Index handle section missing")
        sections.append(tuple((min(p[i] for p in selected)+max(p[i] for p in selected))/2 for i in (0,1))+(z,))
    result=line(sections)
    result["sections"]=sections
    result["section_fit"]=axis_error(line(sections),result)
    return result


def source(v): return (-v[2],-v[0],v[1])


def cylinder(points,axis):
    """Least-squares grip centre from proximal/middle surface joints, with a fitted stack direction."""
    axis=unit(axis)
    def cross(a,b): return (a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0])
    u=unit(cross(axis,(1,0,0) if abs(axis[0])<.9 else (0,1,0)))
    v=cross(axis,u)
    origin=tuple(sum(p[i] for p in points)/len(points) for i in range(3))
    rows=[];rhs=[]
    for p in points:
        d=sub(p,origin);x,y=dot(d,u),dot(d,v)
        rows.append((2*x,2*y,1));rhs.append(x*x+y*y)
    m=[[sum(r[i]*r[j] for r in rows) for j in range(3)]+[sum(r[i]*b for r,b in zip(rows,rhs))] for i in range(3)]
    for k in range(3):
        pivot=max(range(k,3),key=lambda i:abs(m[i][k]));m[k],m[pivot]=m[pivot],m[k]
        if abs(m[k][k])<1e-14:raise ValueError("singular grasp cylinder")
        n=m[k][k];m[k]=[x/n for x in m[k]]
        for i in range(3):
            if i!=k:
                n=m[i][k];m[i]=[a-n*b for a,b in zip(m[i],m[k])]
    x,y,c=(m[i][3] for i in range(3))
    return {"pos":add(origin,add(mul(u,x),mul(v,y))),"axis":axis,"radius":math.sqrt(max(0,c+x*x+y*y)),"points":len(points)}
