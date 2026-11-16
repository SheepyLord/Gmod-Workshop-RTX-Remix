# portal_limits_harness.lua

LuaJIT harness for [test_portal_limits.py](test_portal_limits.py.md) (review finding 5, 2026-11-16): a pasted
Seamless Portals dupe with a side count of two billion hung the host and every client, because the duplicator restores
a portal's network vars through the generated setters (`SetSidesInternal`, `SetSizeInternal`), not through
`ENT:SetSides`, and every reader trusted them.

```powershell
luajit tools\tests\portal_limits_harness.lua <folder>
```

The folder holds the portal entity's `sh_init.lua`, `init.lua` and `cl_init.lua` (the fixes part's
`GMod-Seamless-Portals-Remix/lua/entities/seamless_portal/`), already turned into plain Lua by the runner. The harness
stubs the engine (vectors, angles, a portal with its network vars and physics object, meshes) and counts every vector
it makes: a call that makes more than 100000 fails as a runaway instead of eating memory.

On the server (`sh_init.lua` and `init.lua`) it checks that:

- the side limit is shared (`SeamlessPortals.LimitSides`, `ENT:GetSides`);
- the tools' side counts (3, 4, 50, 100) build hulls of two points a side, and `ENT:SetSides` stores 100, 3, 3, 4,
  4, 4, 100 and 3 for 2^31-1, 0, -5, NaN, inf, -inf, 1e300 and 3.7;
- a hull built from those raw network vars has at most 200 points and costs a bounded number of vectors;
- `ENT:GetSize()` of (1e30, -1e30, NaN) is (2048, 1, 8), of (inf, NaN, -inf) the default (50, 50, 8), of zero a size
  within the limits; the tools' sizes (500 x 500 x 100, the fitter's 999.9, the gun's 33 x 17 x 8) and a Hammer portal
  of 4096 x 4096 units stay as they were; it returns a new vector each call; `ENT:SetSize` stores a bounded size;
- a crafted dupe spawns (`ENT:Initialize`) with a 200-point hull and a bounded stored size, and after the duplicator
  restores the crafted values again `ENT:PostEntityPaste` stores 100 sides and a bounded size and rebuilds the hull;
- a new portal gets the default size and a sized one keeps its size and sides.

On a client (`sh_init.lua` and `cl_init.lua`) it checks that `SeamlessPortals.GetRenderMesh` builds nine vertices a
side, at most 900, for every crafted side count and keeps at most one mesh per side count from 3 to 100, and that a
client's `ENT:Think` and `ENT:DrawModelMesh` of a crafted portal stay bounded.

Prints `PASS: portal side counts and sizes stay within their limits`; exit 1 with `FAIL: <reason>` on stderr
otherwise. Against the files before the fix it fails (`SetSides(nan) stores 4, not nan` once the helper check is
skipped). No game, network or user files.
