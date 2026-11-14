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
