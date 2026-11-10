# 0144: On maps with many lights the light updater draws a helper only while a light it sets needs it

- Status: Accepted 2026-11-10 (R28)
- Context: the issue 2 diagnosis ([handover/issue-2-memory-report.md](../handover/issue-2-memory-report.md)): the
  fixes' light updater (`remixlua/cl/cl_rtx_light_updater.lua`, on by default: `rtx_lightupdater 1`) draws one helper
  model per map light every frame from Lua, 10.7 us a light: 1.95 ms of every frame for gm_friluft's 182 lights, and
  the most expensive client hook on gm_skyport, which has 4,606 (about 49 ms a frame at that rate). The R28 probe
  measured 1.12 ms a frame on gm_construct (171 lights, 6.5 us each), and found the hook to be the smaller part: on
  gm_backrooms_classic (1,126 lights) the hook takes 10 ms and the frame 40 ms, where a view that needs 13 helpers
  takes 9.5 ms. A helper left out gives back 27-35 us of the frame, three times its own call. The user, 2026-11-10:
  "find and safeguard potential game-lagging methods".

## Why the helpers are drawn, and what the runtime needs

A helper model makes the engine set lights for a draw, which is how the Remix runtime learns of the game's lights.
What the engine sets for a model is not "the light the helper stands at" but the four strongest of the map's world
lights in sight where the model stands (the console variable `r_worldlights`): a light counts if its cluster is in
the PVS of the model's leaf, if it is brighter there than `r_worldlightmin` (0.0002, by distance), and if a ray
against the world reaches within 8 units of it. So a helper sets its own light and that light's neighbours. Among
a map's world lights are the lights no entity stands for: **texture lights** (`emit_surface`, one per lit patch:
1,800 of modern_house's 2,828 world lights), which reach the runtime as spot lights, and the sun.

With the package's settings (`rtx.suppressLightKeeping = True`, `rtx.antiCulling.light.enable = True`,
`packages/runtime/layers/classic_remix_defaults.conf`) the runtime's `LightManager::garbageCollectionInternal`
(`src/dxvk/rtx_render/rtx_light_manager.cpp`) drops a light the first frame it is not set, with one exception: a
light marked outside the view is kept until `rtx.antiCulling.light.numFramesToExtendLightLifetime` (1000) frames
have passed since it was last set. Only point lights can be outside the view (`addGameLight` gives
`D3DLIGHT_POINT` the anti-culling type `GameLight`, tested as a sphere of the light's position and its converted
radius, 9 units here, against the camera's frustum scaled by `rtx.antiCulling.light.fovScale`,
`RtCamera::updateAntiCulling`); spot and directional lights always count as inside, and with the runtime's free
camera on nothing is kept.

So a point light out of view needs to be set once in a long while; a point light in view, a spot light, a texture
light and the sun every frame, by some helper that sets them.

One more rule of the runtime limits where a light may stop being set at all (`LightManager::dynamicLightMatching`,
found by this round's second review). A light that was set in the last frame and is not set in this one is taken
for a light that moved: if a new point light lies within `rtx.uniqueObjectDistance` (300 units, the default), that
one inherits it and the old light is erased. A new point light is a dynamic light that starts, or one that moves
(a game light's identity is its position): a muzzle flash, an explosion, a lamp being carried. While every helper
was drawn every frame no map light was ever in that state; a light whose helper stops is, for one frame, each time
it stops.

## Decision

`RenderLightUpdaters` keeps a draw list (built again whenever the set of lights changes), and uses it **on maps
with 256 lights or more**, where the helpers cost a third of a frame and more; on smaller maps every helper is
drawn every frame as before (`rtx_lightupdater_all`, not saved: 0 by map size, -1 the list on every map, 1 never).
A helper is **bounded**, drawn only when needed, if every light it may set is either a steady point light or a
light that another helper, drawn every frame, sets; every other helper is drawn every frame, as before.

1. **Never bounded:** the helpers of `light_spot`, `light_environment`, `light_dynamic`, the `gmod_light` and
   `gmod_lamp` entities, and of any `light` with a `targetname` (a map can switch it) or a light `style` (it
   flickers).
2. **What a helper may set is worked out once a map** from the map's world lights (NikNaks' `GetWorldLights`, the
   HDR list when the game renders HDR), by the engine's own rule with a margin, a few helpers a frame (1 ms, or
   5 % of a long frame).
   - First for each map light whose helper is drawn every frame (a `light_spot`, a named or styled `light`):
     whether that helper sets it. It does when the light is among the two strongest where the helper stands, the
     helper's leaf can see the light's cluster and a ray reaches it. Such a light needs no other helper.
   - Then for each steady point light's helper. It is bounded unless a light that no helper is known to set
     every frame (a texture light, a light whose helper could not be placed, a light its own helper was not
     found to set) could be among the engine's four: one whose cluster the helper's leaf can see (the map's PVS,
     for the helper's spot and six spots 12 units around it), unless eight steady lights in sight are stronger
     than the strongest such light, which is taken at its full brightness (no cone, no light style) and whether
     or not a ray reaches it. It is not bounded either when the map has a sun and the helper sees the sky along
     it (the game's directional light is ignored while the package's sky is on, but that can change in a
     session).
   Until a map's helpers are all worked out, and for a map whose world lights cannot be read, do not match its
   light entities or number more than 20,000, every helper is drawn every frame.
3. **A bounded helper is drawn** while its own light counts as in view, and in turns otherwise: once every 120
   frames, an eighth of what the runtime allows, spread evenly, in every view of its frame (a frame's first view
   can be a camera or a mirror whose draws the runtime takes no lights from). A light counts as in view
   - with its origin inside the view's sides, taken generously (the view setup's own angles with their tangents
     times 1.15, 96 units around, up to the far plane and 5 % more), and for two frames after it left them: the
     runtime tests a frame's lights with the view of the frame before, so a fast zoom or turn is a frame late;
   - within 450 units of the eye (the runtime's matching distance and 150 more), and within 450 units of every
     dynamic light the file can know of: the `gmod_light` and `gmod_lamp` entities, and lights made with
     `DynamicLight` from Lua. Those it notes through a wrapper of that function, for a dozen frames after each
     call, with the position as the add-on writes it: the object the game returns can be written, not read
     (`light.pos` is nil), so the write is seen through the object's metatable, and where that cannot be done the
     entity the light is keyed by stands for it. Near those a light never stops being set, so the runtime has
     nothing to hand to a new light.
4. **A steady light its own helper does not set** (the light is not among the two strongest where the helper
   stands, or no ray reaches it from there: a helper that had to be moved) reaches the runtime through its
   neighbours' helpers. Each helper that has such a light among the 48 strongest steady lights around it is drawn
   while that light is in view as well.
5. **The runtime's options** the list relies on are read from the game folder's `rtx.conf`
   (`RemixConfig.GetConfigVariable`): with `rtx.antiCulling.light.enable` off, `rtx.camera.enableFreeCamera` on, a
   lifetime under 40 frames, a `fovScale` over 4 or a `uniqueObjectDistance` over 4000 every helper is drawn every
   frame; a shorter lifetime shortens the turns to a quarter of it, a larger `fovScale` widens the view tested and
   a larger `uniqueObjectDistance` the distances of rule 3.

After the list is rebuilt every light is drawn in that frame and the next, so a new light shows at once.
`rtx_lightupdater_all 1` (not saved) draws every helper every frame as before, for a comparison;
`rtx_lightupdater_status` prints how many helpers are bounded, how many are still being worked out, how many the
last view drew, and why the list is off when it is. The view test runs on plain numbers in one loop; what was
worked out is kept when a lamp is spawned or removed.

## Consequences

- The updater's cost follows what is in view, not the map. Six views from one spot, every helper against the list (1920x1080, an
  RTX 5090): gm_backrooms_classic (1,126 lights, all point lights; 1,125 helpers bounded) 38.5-38.6 ms a frame against 9.4,
  12.4, 26.1, 22.8, 9.2 and 9.2 ms (28, 142, 652, 536, 13 and 13 helpers); modern_house (1,032 helpers, 959 bounded; 1,800
  texture lights) 38.2-38.9 ms against 27.7, 17.5, 22.8, 26.4, 20.0 and 16.4 ms (634 to 197 helpers). The screenshots of
  each pair match within the path tracer's noise, and so does the picture after a turn (R28 report).
- gm_construct (142 lights) is under 256 and unchanged by default: 7.3 ms a frame; with the list asked for,
  5.4-6.8 ms.
- A map seen from a corner with everything ahead, or lit mostly by `light_spot` or by texture lights, gains
  little: a spot light's own helper is drawn every frame, and so is a helper that may set a texture light.
- The rule's margin is its assumption: that the engine's four lights at a helper are among what the study lists.
  Where that fails a light would be set one frame in 120; `rtx_lightupdater_all 1` is the way back, and the
  report says what was compared in the game.
- **The hand-over in the game.** With a list by view and turns alone (this round's build before the second
  review) a Lua light going round the eye left copies of itself out of view: the list's pictures were brighter by
  12-42 of 255 levels and whiter in six poses of six. With rule 3's distances the poses that are clean in a
  control match (0.3-0.6 levels), and a light that stands still gives the same picture either way (RESEARCH, R28).
- **What is left of the runtime's hand-over.** The engine's own dynamic lights (a muzzle flash of a Source weapon,
  an explosion, a burning or flying thing) cannot be seen from Lua. One that starts or moves more than 450 units
  from the eye, within 300 units of a steady light that is out of view, can take that light in the one frame after
  the light's turn; the light is then off until its next turn (120 frames at most), or for as long as such a light
  keeps moving beside it, and the moving light's own last copy can stay behind, out of view, for the runtime's
  1000 frames. It is a light the player is not looking at, more than 450 units away; what it lit in
  view dims for that time. On a map under 256 lights nothing of this applies. Removing it needs the runtime to
  know a map light from a moving one (a later round).
- **The Remix free camera** (developer menu) switches the runtime's keeping of lights off, and Lua cannot see it
  switched on in the menu: with it, the lights outside the game's own view are set one frame in 120 on a map
  that uses the list. `rtx_lightupdater_all 1` for the time it is used; `rtx_lightupdater_status` says so.
- A change of the runtime's options made in the Remix menu and not saved to `rtx.conf` is not seen from Lua.
- A dynamic light from Lua with no model near it (an explosion's flash) was set by any helper within its radius;
  now by those drawn that frame. The lights of `gmod_light` and of anything with a model of its own are unchanged.
- The fixes part's Lua changes locally (GPL-2.0, as the part is); no loader or runtime change.
  [`light_updater_harness.lua`](../../tools/tests/light_updater_harness.lua.md) runs the file's rules without a game.

## Alternatives considered

- **Bound every steady point light's helper by its own light alone.** This round's first build did, and the
  review named what it broke: a texture light, a spot light for the runtime, that only an out-of-view helper set
  would have been lit one frame in 120. In the game the difference did not show on
  modern_house: the first build's pictures matched in the six poses tried, and helpers drawn beside texture lights alone
  changed nothing visible (a patch there has a brightness of 2-14 against the hundreds of a point light, and a point
  light stood within 83 units of every candidate). The rule is kept for the rooms a texture light lights alone.
- **Switch the list on only for maps whose world lights are all steady point lights.** gm_backrooms_classic is
  one; nearly every other map has a sun or a `light_spot`, and would gain nothing where most of its rooms could.
- **Use the list on every map.** gm_construct's 142 helpers cost 1 ms of a 7.4 ms frame; the list gives back up to
  2 ms there, and brings what is left of the runtime's hand-over with it. Under 256 lights the old behaviour is
  kept: nothing changes where little is to be gained.
- **Leave the list off unless asked for.** The maps that need it are the ones where the game runs at 25 frames a
  second because of the helpers; what is left of the hand-over there is a light out of view dimming for a moment.
- **Change the runtime now** (keep a map light apart from a moving one in `dynamicLightMatching`, keep lights with
  the free camera). The right place, and a round of its own: the matching is what removes a moving light's old
  position, so the rule has to tell the two apart, and every map and every dynamic light has to be looked at
  again with the new runtime.
- **Take the engine's four lights exactly, without a margin.** The engine measures at the model's lighting origin,
  caches the result for a 32-unit cell, and traces against the world alone, where a Lua trace also stops at static
  props: an exact answer here would be wrong at the edges, and a wrong one is a light that flashes.
- **A fixed number of helpers a frame for every light.** Lights in view would miss frames, and the runtime drops
  them at once: flicker.
- **Leave out lights the map's visibility data hides from the camera.** A light in a room the camera cannot see
  still lights the corridor it can; path tracing has no such cut. (The visibility data is used only as the engine
  uses it: for which lights a helper's own leaf can take.)
- **Let the runtime keep lights (`rtx.suppressLightKeeping = False`).** Then a light that was steady for fifty
  frames is never dropped or updated again: a `gmod_light` switched off would stay lit.
- **Draw the helpers under a material whose texture the runtime ignores.** The runtime takes a draw's lights before
  it rejects an ignored texture (`D3D9Rtx::processRenderState`), so such a helper still sets its light and is no
  geometry for the path tracer. Tried (the shipped `rtx_lightupdater/rtx_lightupdater` material, its texture set
  to the Ignore category): the frame stayed at 40.1 ms against 40.2-40.4. A helper's cost is the draw that sets
  the light, not its geometry.
- **Create the map's lights through the Remix API instead** (the fixes' other mode, `rtx_lightupdater 0`). Another
  look (the lights' values come from the map file, not from the engine's own light data), and the package's default
  is the classic install's.
