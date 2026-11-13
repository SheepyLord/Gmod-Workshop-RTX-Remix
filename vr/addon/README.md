# nlvr add-on (V1)

MIT, original implementation. Package as `garrysmod/addons/nlvr`; there is deliberately no `autorun`.
The companion includes [lua/nlvr/client.lua](lua/nlvr/client.lua.md) only when the API-v1 module's Info reports
`sdk_ready`, before the first traced frame. This add-on contains the authoritative head view, 3D view-model/body suppression and wrist overlay,
with session cleanup. Desktop 2D drawing stays intact; the runtime takes the eyes before those desktop passes.
No server scripts, networking, physical hands, locomotion or weapon controls ship in V1.

The companion owns the lifecycle; the module owns OpenVR; the runtime owns eye/overlay images. This add-on does
not use another VR add-on's implementation. See the task's [report](../../docs/handover/VR-V1-E-report.md) for
packaging instructions, tests, defaults and open integration checks.

## V2/V3 branch integration

The fixed client/server roots load at Start through the companion page/stub. The shared registry
owns hooks, events, movers, resolvers, canvases and reverse cleanup. Only the single-player
player/listen host activates full authority; one dormant server receiver remains off.

Hands are lit c_arms world geometry with smoothed curls/splay, brush/physical stops and overlay
ghosts. Movement separates same-frame room/head tracking from motor interpolation; the latter
buffers actual coalesced FOLLOW cadence and delivery, is bounded to 120 ms, and samples at the
view lookup. This preserves smooth motion without increasing server message rates. Motor lag
is explicitly measured and is not optical head latency.

The physical module's BodyTrace predicates bridge its existing owned-body collision exclusions
to server hull checks and client prediction. Climbing solves hand-relative-to-head contact
constraints, cancelling common delayed body translation instead of amplifying a pull. Native
Use/kit grants stay authoritative; two hands share the same object Use cooldown.

Panels, laser, ghost outlines, gloves, teleport and comfort are SteamVR overlays, never traced
UI. Borrowed sandbox widgets retain callbacks/state; the window source uses bounded native
input in this process. SteamVR keyboard is tried first, then a laser keyboard on failure.
The native overlay bound is 32; the complete reserved roles plus arc dots fit it.

Private acceptance Lua is absent from the package and is staged only inside a snapshotted PoC
add-on tree. See the Q integration report for the exact tested package, errors, counts and limits.
