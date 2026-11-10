# 0141: "Depth-only" colour targets become colour targets; a refused base texture draws nothing

- Status: Accepted 2026-11-09 (R27)
- Context: the user, 2026-11-09: "some HUD-related addon draw on the entire screen, and causing the entire screen to be
  rendered incorrectly (full white)", with HUD Mk.2 (Workshop 3505713469) and SYNTHETIK targets health bars
  (2372740052) as examples: "investigate and implement a fix, make the fix universal to avoid this in the future or
  other addons."
- Amends: [ADR 0086](0086-inert-shader-effects-and-safe-guard-fallbacks.md) decision 3 ("depth-only targets ... receive
  the fallback") for depth-only requests in a reviewed colour format, and adds a rule to its binding policy.

## What happened (the PoC, R27)

HUD Mk.2 (`lua/hud_mkii/utils/sfx.lua`) asks for a full-screen render target with `MATERIAL_RT_DEPTH_ONLY` and
`IMAGE_FORMAT_RGBA8888`, creates three `UnlitGeneric` materials with `models/debug/debugwhite` as a placeholder base
texture, sets the target as their base texture, draws its whole HUD into the target each frame and then draws the
target over the screen (alpha 0.75, and two tinted copies for its chromatic aberration). In stock GMod the target is
a colour target (the PoC without RTX: the material's base texture became `nenes-hud-hudrt-1280-720` and the HUD drew
normally).

Under RTX the render guard refused the target ("depth-only targets are unsupported under RTX", ADR 0086) and returned
its inert 1x1 target; then it refused the materials' `SetTexture` to that inert target ("incompatible material
mutation ignored"), so they kept `models/debug/debugwhite`; the push of the inert target became a virtual scope in
which the HUD's own draws were skipped; and after it HUD Mk.2 drew the three white materials over the whole screen:
the screen was white. The guard refused each step correctly and the sum was worse than any of them.

SYNTHETIK targets health bars draws untextured rectangles in `HUDPaint` and draws correctly under RTX, with and
without the fix; the white screen with both add-ons came from HUD Mk.2.

## Decision

1. **A depth-only request in an 8-bit colour format becomes a colour target with its own depth buffer.** In
   `GetRenderTargetEx`, `MATERIAL_RT_DEPTH_ONLY` in RGBA8888, ABGR8888, RGB888, BGR888, RGB565, ARGB8888, BGRA8888 or
   BGRX8888 is allocated as `MATERIAL_RT_DEPTH_SEPARATE` (after every other check: names, sizes, budgets, flags), with
   one console note ("depth-only colour target given its own depth buffer under RTX", the guard's new `adapted`
   records). Stock GMod gives these add-ons a colour target, and a colour target with its own depth and stencil is what
   the guard already allows any add-on; it shares nothing with the frame's own buffers. A depth-only request in any
   other format (the default, float, 16-bit and R32F formats real depth passes use, or a depth format proper) still
   gets the inert target.
2. **A material whose base texture the guard refused draws nothing, never its placeholder.** When the guard refuses
   `SetTexture` or `SetString` of `$basetexture` because of the texture itself (the inert target, an engine-reserved
   texture or a refused target's name; not because the caller is an effect source), and Lua created the material
   (`CreateMaterial`), the material is marked by its name: untrusted `surface.SetMaterial` and `render.SetMaterial` calls
   then bind the guard's transparent material and the draws after them are skipped, as for any incompatible material
   (the override setters ignore it). A later `$basetexture` binding that goes through, or `SetShaderAndParams`, clears
   the mark; a texture bound by ID (`surface.SetTexture`) ends the refusal of the material bound before it. Materials
   loaded from files are shared (the world or other add-ons may draw them), so they keep drawing with their own
   texture, and the package's own callers (ADR 0086 point 8) keep native behaviour. This holds whatever made the guard
   refuse the target: an unsupported format, a cubemap, a size or budget limit, an effect source.
3. **The name of a refused target is refused like the target, while the engine has no texture of that name.** Exact
   names only (case aside, a `.vtf` suffix aside), never an engine `_rt_` target, a name allocated before or after is
   cleared, and at most 1,024 are kept: a material first created with such a name as its `$basetexture`, or set to it,
   would show a missing texture, so point 2 applies to it.

## Consequences

- HUD Mk.2 works under RTX (its HUD drawn into its target, the target drawn over the screen, its colour fringes and
  glitches), and the white screen is gone (PoC, R27 report). One difference stays: its scanlines, which stock GMod keeps
  on the HUD's own pixels through `render.OverrideBlend` with "keep the target's alpha" factors, show faintly over the
  whole screen under the RTX runtime (in a probe 2.7 levels of stripes outside the HUD, against 0.1 without RTX;
  turning alpha writes off for the pass did not change it). That is the runtime's blending of 2D draws into a target,
  not something the guard can restore; HUD Mk.2's own `hud_mk2_scanline 0` turns the effect off.
- An add-on whose render target the guard still refuses no longer covers the screen with its placeholder: what it
  meant to draw from that target is missing instead. Its draws into the refused target stay as ADR 0086 has them
  (textured draws skipped; untextured ones were never intercepted).
- A depth-only colour target costs a depth buffer of its size (for a full-screen one at 3840x2160 about 33 MB of
  VRAM); the guard's allocation estimate counts colour bytes only, as before.
- No loader change: the loader appends the companion's guard from the verified package (`loader/guard`), whatever its
  bytes.

## Alternatives considered

- **Skip every draw inside a refused render-target scope, untextured ones too.** More consistent, but it needs new
  wrappers on `surface.DrawRect`, `DrawLine` and `DrawText`, the hottest 2D calls (thousands a frame in the spawn
  menu), each reading the guard's switch; and with point 1 the reported add-on no longer reaches such a scope.
- **Mark the Lua object, not the material.** GMod can hand out two Lua objects for one material (`Material("!name")`
  after `CreateMaterial`), so the mark is kept by the material's name.
- **Draw a refused target's composite with a transparent texture.** It needs a texture the guard owns in every
  material slot an add-on might use; skipping the bind (point 2) reaches the same picture with the existing inert
  material.
- **Allow `MATERIAL_RT_DEPTH_ONLY` through unchanged.** What the engine allocates for that depth mode under the RTX
  runtime was never reviewed (ADR 0086 refused it), and an add-on drawing colour into the target needs none of it.
