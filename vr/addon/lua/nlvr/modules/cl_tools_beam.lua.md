# cl_tools_beam.lua

Tools-owned live-registry adapter for DrawPhysgunBeam. Replays the existing library
with original callbacks/ULib priority levels exposed, then draws T's local VR beam and
returns false to the engine. This covers engine-cached dispatch functions; replacing
public Call/Run fields alone did not. First registers an ordinary ctx.hook, creating empty
ULib event priority levels before inspection. Stock registry mutability is capability-probed;
ULib uses its live priority registry. Unknown/detached/unsupported registries retain the
ordinary hook without throwing or failing VR Start. This fallback obeys that library's normal
hook ordering; it cannot promise post-dispatch replay for an unknown dispatcher.
Reentrancy prevents replaying the dispatcher and its ordinary fallback.
Other players retain normal callback/gamemode behavior. Stop restores only still-owned
registries, preserving callbacks added during the session; retained references are inert.
Empty/populated ULib events restore exact ordinary/priority table identities and contents,
including a second Start/Stop. Private stock probes are removed. No files/network/settings.
Faithful ULib/unknown-library, native peer counters and cached-dispatch tests verify it.
