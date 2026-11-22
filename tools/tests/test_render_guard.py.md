# test_render_guard.py

Twenty-two unittest cases run twenty-five LuaJIT scenarios against the complete production guard,
rather than a policy reimplementation. Run from the repository root:

    python -m unittest discover -s tools/tests -p test_render_guard.py -v

The normal tools/test.ps1 flow also discovers these tests. LuaJIT absence skips them. No game/GPU
or user config is needed; subprocesses only read repository fixtures and print results. These
tests prove Lua policy/contracts, not recovery from native SEH, GPU faults or loops. Exit zero
means success; a failed assertion or subprocess error makes unittest exit nonzero.

Refused calls now return safely (ADR 0086); the NUL scenario checks native C-string boundaries before dispatch. The stack-ownership scenario
checks unowned/active-parent protection, successful Pre/Post balancing, recorded RT restoration
after an error, and explicit reporting when a popped completed camera cannot be safely replayed.
Nested cleanup also checks chronological action propagation from successful children, without
double restoration of failed children's already-cleaned actions.
The verified multiplayer scenario reproduces the bootstrap's private marker and scoped hook
proxy, while global/inherited-marker and server/menu scenarios must not install client wrappers.
The installation label explicitly distinguishes this later path from early startup protection.
The cached-dispatcher scenario captures original hook.Call before installation and requires
existing/future owned late render wrappers to contain failures while healthy callbacks, server
callbacks and loading-hook identity survive. Early registry callback identity remains covered by
its original scenario.

[ADR 0056](../../docs/decisions/0056-guard-and-startup-fallbacks.md) cases: the autorun install
of a local RTX start without the early view; a served initializer (early flag without this
machine's active start) and an RTX-off start installing nothing; error reports with the original
message and quarantine only after three consecutive failures within ten seconds, never for a
gamemode method; per-category report caps; scopes leaked outside protected callbacks at
FrameNumber and PreRender boundaries; and the hot-path contracts (no switch read for unprotected
events, lazy entry render target, cached shader names).

R8 adds a separate 24-scenario suite plus an inventory/hash check in
[test_render_guard_addons.py](test_render_guard_addons.py.md).
Together the suites run 47 methods/49 LuaJIT scenario invocations and the static check. Material
creation/reading stays native; unsupported bindings receive the fallback. Shader names are first
queried at binding and then cached. Existing refusal assertions now require
no escaped error and verify native-call counters; deliberate add-on errors still test containment,
reporting and quarantine. The leaked-scope limit test balances ignored pushes/pops instead of
relying on a guard-created exception to unwind a successful callback.

R20-D: ordinary camera closers End/End2D/End3D share tracked scopes; Start3D2D requires
End3D2D. Regression scenario `camera_aliases` checks 257 icon-style pairs, every ordinary
start/closer combination, nested calls, cross-family refusal, virtual pushes and error cleanup.

R20-D also loads the real effect observer on top of the real guard (`effect_observer`), rejects
an untrusted screenspace binding and draw with the original virtual caller, then permits a normal
UnlitGeneric sprite. The observer's renderer forwarding stays in tail position.

Native-mode correction (ADR 0122): End and End3D are equivalent 3D pops, while End2D, End3D2D and
EndOrthoView have separate native counters. Generic Start's type selects its family and cleanup.
The harness models independent modes, checks generic 2D cleanup and optional orthographic scopes,
and refuses wrong-mode closers without a native call. Native color-material helpers also clear
stale inert shader state; forwarding through the observer preserves caller policy.

R20-D raster preview compatibility: suppressed-lighting PostRender model previews use bounded,
cached UnlitGeneric base-texture studio overrides (256 materials, 32 slots) and restore every
owned override on success/error. Entity submaterial strings are untouched. Explicit caller
material overrides retain precedence. The wrapper catches late render.Model definitions and
startup replacements; suppression intent is retained for the protected callback because stock
helpers can reset the flag between draws. Early/late definitions, multiple parts, caller overrides,
returns and exception cleanup are exercised by preview_materials / preview_late.

Preview cache follow-up: use stable material/texture names rather than weak Lua userdata keys;
native lookups can return transient wrappers. The regression repeats 300 preview draws with new
wrappers without exhausting the material budget. The DX7 fallback uses a representative base map
through the global studio override; entity submaterials are untouched and explicit indexed/global
caller overrides retain precedence. Multi-material/custom-shader thumbnails are approximate.

R27 adds `test_depth_only_colour_targets_and_refused_base_textures` (the `hud_composite` scenario, ADR 0141): HUD
Mk.2's "depth-only" full-screen target in a color format is allocated with its own depth buffer and its composite
draws; a depth-only request in an unreviewed format still gets the inert target; a created material whose
`$basetexture` binding is refused draws nothing through `surface` or `render` until a binding goes through, and a
texture bound by ID afterwards draws; a material created naming a refused target, or set to that name, is refused; a
loaded material keeps drawing; a name refused and then allocated, one allocated and then refused once, a similar name
(`rt_scale_0.75` against `rt_scale_0.5`) and an engine `_rt_` name keep drawing; a repeat creation changes nothing; a
depth-only request in a float format still gets the inert target.

R28 adds `test_periodic_read_backs_repeated_font_definitions_and_slow_render_callbacks` (the `cost_safeguards`
scenario, ADR 0143). Read-backs: at two a second nineteen are made and the twentieth is not; a refused reader gets
the last picture's values, the picture's last pixel for one it does not hold, and no native read; it stays refused
while it keeps asking and is told once; another add-on's reads stay real meanwhile; after five quiet seconds it reads
again. A reader of about one read a second (330 of them, unevenly spaced) and a bundled caller are never limited; a
batch of eight is made in full; bursts of four every 1.1 s are cut in the third. Two targets read through one helper
keep a picture each, and a target read for the first time is read. Two files that read back through `pcall` have an
allowance each. A fractional coordinate finds its pixel. A file that reads 1,100 pixels of a picture is never
limited. A refused picture stops answering after five seconds, and at once with `nativeloader_guard_readbacks 1`.
A reader of one sample a second that overran once (seven of a burst of nine made) is let in again after a while and
never limited after that. Read-backs every frame with no pixel read are limited, and a pixel read afterwards is
the engine's last picture, then remembered. Two add-ons that read through one shared library have an allowance
each. Another file reading 1,100 pixels of a reader's picture leaves that reader limited.
What `render.ReadPixel` returns after a read-back that was made is what the engine returned. Fonts: the same
definition is made once, also under another case of the name, and again after ten seconds; a changed one, one with
fewer keys, another name, a call with other arguments and a table with a metatable go to the engine, and a caller
that reuses its table is compared with a copy. Slow callbacks: one that takes 6 ms of every frame is recorded once
with its hook's name and its cost (a later window updates the record, and so does another function added under the
same name), a quick one is not, twelve frames are no window and thirty at two a second are, a gamemode method and an
entity's hook are named as such, 32 records at most, and a failing `PreDrawViewModels` callback is contained. A
function entered in `NativeLoaderRenderGuard.timed` is recorded as the function it times, an effect callback the
guard leaves out stays left out under it, and a hook stopped after repeated errors stays stopped under its timer
and after it.

GitHub issue 5 adds `test_minemods_not_ready_line_stays_off_screen_only_while_the_guard_refused_its_probe` (the
`minemod_notice` and `minemod_notice_multiplayer` scenarios, ADR 0210). While MineMod bakes, its line shows. Its
probe's custom shader is still refused (a `render.SetMaterial` record from `lua/mc/resources/cl_sampling.lua`). Once
its last job has failed with `resource_sampling_unsupported:[[0,0,0],...]` and its default pack is pending, its
`HUDPaint` hook is not entered, frame after frame, through the guard's dispatcher and the harness's original one,
with one console note and one `adapted` record naming the failure, and no error record. Its `Think` hook and another
add-on's `HUDPaint` hook still run. Another failure code (`resource_sampling_probe:...`) and a restore error show
as MineMod wrote them; MineMod state that raises an error when read shows the line, without an error of the guard's;
with the pack no longer pending its hook is entered again; with `nativeloader_guard 0` the line shows; a new
registration under the same name and file (an autorefresh) is kept off the same way; the note is never repeated.
Against the guard before this change the scenario fails at its first hidden frame.

ADR 0246 adds `test_the_directx_level_prelude_is_included_where_the_client_module_did_not_run_it` (the `dxlevel_fallback`,
`dxlevel_multiplayer` and `dxlevel_present` scenarios): where `NativeLoaderDXLevel` is absent (the RTX client module did
not run the companion's prelude before `includes/init.lua`), the guard includes `nativeloader/prelude/dxlevel.lua`
once, through the engine's `include` in a local game's early view and through the private environment's scoped
`include` in the late multiplayer route; where the prelude already installed it, nothing is included.

ADR 0256 adds `test_the_guard_takes_its_place_in_dlibs_hook_library` (the `dlib_hooks` and `dlib_hooks_multiplayer`
scenarios, with the harness's stand-in that takes the hook table over as DLib does). Early route: the guard finds
DLib's library at the gamemode's load (`NativeLoaderRenderGuard.hook_library` is `"DLib"`, one console line); then
MineMod's line stays off the screen and its hook is not entered while its `Think` hook runs; the effects registered
before and after DLib stay inert; a failing render callback is contained, what it pushed is popped, and it is stopped
after three failures; DLib's priority order holds, a hook DLib disabled stays disabled, an object's hook gets its
object; `NeedsDepthPass` answers false; `hook.GetTable()` still holds the add-ons' own functions; a hook added later
and an autorefreshed MineMod hook are protected the same way; a slow callback is named with its hook; a second
loading event wraps nothing twice; with `nativeloader_guard 0` everything runs as DLib runs it. Late route: found at
the install, DLib's `Call2` (the remote server's dispatcher) unchanged; MineMod's line and an owned callback
registered before the install are kept off and protected, an owned callback after it is protected, a server's
callback keeps its identity and its error propagates, `NeedsDepthPass` answers false. Against the guard before this
change the early scenario fails at its first check (no library found); with that check left out, MineMod's line was
drawn in four frames of four, the later effect ran every frame, `NeedsDepthPass` was true and a render callback's error
came out of `hook.Call`.

ADR 0257 adds `test_the_guard_works_inside_ulibs_hook_library` (the `ulib_hooks` and `ulib_hooks_multiplayer`
scenarios, with the harness's stand-in that does what ULib's hook library does). Early route: the guard finds ULib's
library at the gamemode's load (`hook_library` `"ULib"`, one console line), and ULib's `Call`, `Add`, `Remove` and
`GetTable` stay in the hook table, `hook.GetTable()` and `hook.GetULibTable()` the same tables; ULib's order holds
(monitor -2, -1, 0, 1, monitor 2, the monitors' values ignored); MineMod's line stays off the screen and its hook is
not entered while its `Think` hook runs; the effects registered before and after ULib stay inert; failing render
callbacks, before ULib and after it, are contained, what they pushed is popped, and they are stopped after three
failures; an object's hook gets its object and a gone object's hook is dropped by ULib; `NeedsDepthPass` answers false,
also with no add-on hook and a gamemode that asks for the pass; `hook.GetTable()` still holds the add-ons' own
functions; ULib's value rules hold (a value from -1 ends the call, a monitor's does not); hooks added later, through
`hook.Add` and through a kept reference to ULib's `Add`, and an autorefreshed MineMod hook are protected the same way;
a slow callback is named with its hook at its share of each frame (the frame counted once); a second loading event
adds and wraps nothing twice; with `nativeloader_guard 0` everything runs as ULib runs it. Late route: found at the
install, ULib's `Call` (the remote server's dispatcher) unchanged and no hook of the guard's own; MineMod's line, an
effect and an owned callback registered before the install are kept off, inert and protected; owned callbacks after
it, through the private proxy and through ULib's `Add`, are protected; a server's callback keeps its identity and its
error propagates; `NeedsDepthPass` answers false. Against the guard before this change both scenarios fail at the
check that the library was found; with that check left out, the early route drew MineMod's line in four frames of
four, ran the later effect every frame, let eight render callback errors out of `hook.Call` and answered
`NeedsDepthPass` true. Changing the guard back step by step (no watch on new names, no walk of the records already
there, no depth pass hook, no frame hook, a frame counted twice, the guard's own hooks also in the late route) makes
one of the two scenarios fail each time.
