# nlvr add-on (V1)

MIT, original implementation. Package as `garrysmod/addons/nlvr`; there is deliberately no `autorun`.
The companion includes [lua/nlvr/client.lua](lua/nlvr/client.lua.md) only when the API-v1 module's Info reports
`sdk_ready`, before the first traced frame. This add-on contains the authoritative head view, 3D view-model/body suppression and wrist overlay,
with session cleanup. Desktop 2D drawing stays intact; the runtime takes the eyes before those desktop passes.
No server scripts, networking, physical hands, locomotion or weapon controls ship in V1.

The companion owns the lifecycle; the module owns OpenVR; the runtime owns eye/overlay images. This add-on does
not use another VR add-on's implementation. See the task's [report](../../docs/handover/VR-V1-E-report.md) for
packaging instructions, tests, defaults and open integration checks.
