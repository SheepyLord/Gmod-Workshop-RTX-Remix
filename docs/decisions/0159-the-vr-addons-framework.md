# 0159: The VR add-on's framework

Accepted for the V2/V3 task branches, 2026-11-11, implementing the interfaces in
[the work plan](../handover/VR-V2V3-plan.md). Integration and milestone approval remain separate.

V1's client session becomes a composition root with fixed core, HUD, hands, movement, UI and
interaction modules. The core retains the owned CalcView registry, predicted floor, hidden render
proxies and exact restoration. Hook functions and engine convars remain untouched. The HUD retains
its literal 769 x 257 target and runtime-copy acknowledgement.

Each module returns a name, order, Start and Stop. A small shared resource registry scopes hooks,
timers, event subscriptions, movers, hand resolvers, overlays and cleanup callbacks. A failed module
hook logs once, stops that module and releases its resources; a failed camera/core or overlay paint
ends the session through V1's error handler. Startup failures unwind through the page. Stop runs in
reverse order and also handles partially started modules. Off has no NLVR global or callbacks.

Tracking is Source-basis metres; the world conversion is the player's predicted feet plus a yaw
rotation of tracking minus anchor, times scale. A seated translation applies equally to head and
hands. Turn rotates about the tracked head. Shift takes a displacement of the player's feet in
world game units: the locomotion module moves those feet and calls Shift once to compensate the
tracking anchor. This explicit unit convention avoids applying scale or yaw twice. Recenter keeps
V1's relatching behavior. Poses expose physical and dominant roles; resolvers modify a separate
shown pose. Native controller -Z already becomes Source +X, so rays use Forward without a second
controller-model rotation. Angular velocity stays Source-axis radians/s; linear velocity scales to
game units/s. Client movers run in ascending priority, stable on ties. Aim lasts one engine tick.

Input is a data mapping by main/off role, mirrored by the dominant setting. Physical controls
remain rebindable in SteamVR. Claims are first-owner-wins for the frame; edges and release taps
(at most 0.3 s) use wall time, including paused rendering. Missing/inactive input releases buttons.

Every UI surface is a native SteamVR overlay with one owned render target, painted only after
invalidation. The manager reserves odd, unique sizes for the follow-on features and rejects live
duplicates. Source retains the bounded named RT allocations until process exit. Overlay coordinates
use the native Source basis: front -X, image right -Y, image up +Z. Hit tests return normalized UVs
and distance in game units and reject back faces, hidden panels, absent tracking and out-of-bounds rays.

Settings are created once by the dormant page; active-only callbacks update the core and notify
modules. The console's contiguous height range is 0..2.2; the core normalizes positive heights below
1.2 to 1.2 to implement the plan's disjoint 0 or 1.2..2.2 range without changing saved values.

Offline tests exercise production Lua through independent transforms, command/move objects and a
bit-level float wire. Real-package Index acceptance remains required; offline tests cannot prove
compositor pictures or native restoration.
