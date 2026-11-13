# vr_tools_poc_client.lua

Capture metadata includes the actual last native camera and compact eye-projection info.
Long private records use the bounded T chunk protocol rather than Source's truncated
single print line. Pixel checks read actual capture records, not only Q's standard labels.

Review evidence observes actual render.DrawBeam calls from T, recording call arguments,
the model's independent muzzle attachment and native pose id, plus two ordinary peer
beam-hook counters. It never substitutes Weapon.Muzzle for that measurement. Wrappers/
peer hooks restore at Exit. Review timelines after 60 s keep their native declared poses
and actions; setting restoration moves to three seconds before that case's end.

The wrapper supplies pre-Start m_yaw to this fixture's saved settings. It restores and
compares that exact string with the other settings before Exit; the shared probe separately
owns restoration on early failures before this client attaches.

Stock tool panels are located by their actual numeric ToolPanels array, then their unchanged
tool button Name/Command. Missing targets suppress the fixture press instead of clicking a
default point. The tool-info capture is offset from the shared 42-second capture request so
the runtime's one-request capture slot cannot overwrite it.
The real tool search field is set as well as its filter, because stock Think re-applies that
field periodically. Its original text is restored before closing and on early Exit. Captures
before both clicks retain the actual menu; click records include widget/ancestor bounds,
enabled/visible state and the engine's hovered panel. The test never calls the tool's DoClick.
After closing each tool list, holds a neutral level hand before requesting the next target,
then aims at it. This keeps the real tool target in the eye captures rather than spawning
it along the stale upward menu-pointing ray.

The motion prototype adds native Use+forward/back from the claimed stick, after normal
movement processing. It observes the engine distance path instead of inventing a grab.

The engine diagnostic alone adds Use/mouse/turn-key pulses after L's mouse handling; it
changes no production module, directly observes native command behavior and makes no
hand-following acceptance claim. Trigger and native holding remain W/engine actions.

Private client evidence appended by vr_tools_poc.py after the ordinary production probe.
Registers an owned earliest mover to clear physical keyboard/mouse; W/K/T process the actual
native timeline afterward. Requests admin fixture setup, samples plain tool/weapon debug and
captures settled yaw/pitch/roll, push/pull, freeze/unfreeze and wheel stages. Native TestState
timestamps are retained. After Exit it asks the server fixture to remove itself and removes
its private hook. Output is console JSON/capture requests under the launcher's allowed out root.
The temporary test convars listed below restore exactly; no direct tool callback or console
attack command is used. No process exit code; Lua errors
fail shared acceptance. Requires real packaged W/K/T, never an offline weapon stand-in.
The longer feature case reveals actual stock tool-list buttons and laser-clicks them through
M, applies remover/colour at a hand-aimed prop, checks secondary colour sampling and B reset,
then picks the crowbar in the wheel. It restores every test-edited tool convar before Exit.
The pre-Exit receipt compares their raw strings exactly and records the actual world scale.
The classic package contains physgun_drawbeams 0. The fixture temporarily enables it solely
for beam pictures, then restores and compares its raw string in both native/features cases;
production respects this existing visibility setting. Early Exit also requests restoration.
The fixture temporarily selects right dominance, standing mode and zero gun correction through
the normal live convars, so its declared poses do not depend on the player's current preferences.
Their original strings restore with the beam/tool settings before Exit and compare exactly.
Captures include each visible handle's actual OverlayInfo: SDK visibility, texture dimensions,
binding/transform errors, simulation flag and OpenVR matrix, alongside the matching saved PNG.
Samples retain W's live muzzle for gun-ray distance observations. Beam proof instead uses
the separately intercepted DrawBeam call/model attachment at the capture's native pose id.
Separate post-action eye captures retain the removed-target scene and the coloured prop,
alongside the actual client/server colour and removal measurements.
