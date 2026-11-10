# R27 report: HUD add-ons that turned the screen white

The user's report of 2026-11-09: "some HUD-related addon draw on the entire screen, and causing the entire screen to be
rendered incorrectly (full white)", with HUD Mk.2 (Workshop 3505713469) and SYNTHETIK targets health bars (2372740052)
as examples; "investigate and implement a fix, make the fix universal to avoid this in the future or other addons."

Done by Claude, with a Claude subagent for the review; no Codex.

## What happened

HUD Mk.2 draws its whole HUD into a full-screen render target and then that target over the screen, three times
(alpha 0.75 and two tinted copies for its colour fringes). It asks for the target with `MATERIAL_RT_DEPTH_ONLY` in
`IMAGE_FORMAT_RGBA8888` and gives its materials `models/debug/debugwhite` until the target is bound. Stock GMod gives
it a colour target. Under RTX the render guard refused the target ("depth-only targets are unsupported", ADR 0086),
then each material's binding to the inert target that replaced it, so the materials kept their white placeholder; the
push of the inert target became a virtual scope that skipped the HUD's textured draws; and the composite drew white
over the whole screen. Each refusal was right on its own; together they whitened the screen.

SYNTHETIK targets health bars draws untextured rectangles in `HUDPaint` and drew correctly in every session, with and
without the fix: the white screen with both add-ons came from HUD Mk.2.

## The fix ([ADR 0141](../decisions/0141-depth-only-colour-targets-and-refused-base-textures.md))

All in the companion's render guard (`_nativeloader_guard.lua`); no loader or runtime change.

1. **A "depth-only" request in an 8-bit colour format becomes a colour target with its own depth buffer**
   (`MATERIAL_RT_DEPTH_SEPARATE`), after every other check, with one console note in the guard's new `adapted`
   records. Stock GMod gives these add-ons a colour target; a colour target with its own depth and stencil is what the
   guard already allows any add-on. A depth-only request in any other format still gets the inert target.
2. **Universal: a material whose base texture the guard refuses draws nothing, never its placeholder.** Whatever made
   the guard refuse the target (an unsupported format, a cubemap, a size or budget limit, an effect source), a material
   Lua created whose `$basetexture` is refused because of that texture is marked by its name; untrusted
   `surface.SetMaterial` and `render.SetMaterial` calls then bind the guard's transparent material and the draws after
   them are skipped, until a `$basetexture` binding goes through. Loaded materials are shared (the world or other
   add-ons draw them) and keep their own texture; the package's own callers keep native behaviour.
3. **Universal: the name of a refused target is refused like the target**, while the engine has no texture of that
   name (exact names, never an engine `_rt_` target, cleared when the name is allocated): a material created naming it,
   or set to it, would show a missing texture over the screen.

## Checked in the PoC

`out/r27/poc_r27.py` in the `r27` worktree (snapshot, move-aside and clean rollback each time; the two add-ons as loose
folders from the user's Workshop copies, `-noworkshop`, gm_construct, a probe that spawns a citizen, aims at it, hurts
it and the player, with a screenshot at each step):

| Session | What it showed |
|---|---|
| `repro`, the published package | RTX: a white screen, the guard's refusals in the console (target, three bindings, push, clears, draws); the material's base texture `models/debug/debugwhite`. Without RTX: the HUD and the citizen's health bar, the base texture the target |
| `verify`, the package built here | RTX: the scene, HUD Mk.2's HUD and effects and the citizen's health bar; the base texture the target; one note "depth-only colour target given its own depth buffer under RTX" |
| `bisect` | A copy of HUD Mk.2 with its effects off, turned on one by one under RTX (render target, colour fringes, scanlines, distortion, glitches), 20 s each and 20 s all on: no fault |
| `rtprobe`, `stencil`, `blend` | Full-screen colour targets under RTX with every depth mode, clears, stencil and write overrides: no fault; the stencil works with separate, shared and natively allocated depth-only targets; the runtime does not fully keep a target's alpha under "keep alpha" blend factors (RESEARCH, R27) |

The probe's two `lua_run` steps (hurting the citizen and the player) were blocked by GMod (`RunConsoleCommand` may not
run `lua_run`), so HUD Mk.2's damage effects were not exercised; they are a vignette texture drawn over the screen and
the motion-blur and view-shake hooks, none of them in a render target.

What it leaves: HUD Mk.2's scanlines show faintly over the whole screen under RTX (7.8 levels of stripes on the sky with
them on, 0.1 with them off), because the runtime blends 2D draws into a target slightly differently; turning alpha
writes off for that pass did not change it. `hud_mk2_scanline 0` turns the effect off.

Two of the sessions with both add-ons and the fix ended in a fault in the engine's mesh code (`shaderapidx9.dll`, a
null vertex buffer at `SetStreamSource`; the frames below it are `materialsystem.dll` and `engine.dll`, not the 2D
surface). They fell in a quarter of an hour in which another session's RTX game, reproducing GitHub issue 2's RAM
exhaustion on the same GPU, crashed three times, and that game, without this change, also ended with the same
`engine.dll` 0xC0000409 at four other times (RESEARCH, R27). That session crashed its game on purpose, and its report
(branch `claude/issue2-memory-9053a9`, not merged here) measured 22-26 GB more system commit for each crash's Windows
Error Reporting snapshot; the PoC's dump recorded a peak commit of 104 GiB. The two later sessions with both add-ons and the fix, HUD
Mk.2 alone, the bisect and every probe ran without a fault.

Also seen: the loader once refused to deploy ("Garry's Mod is running from this folder") while another copy's game
was running, because its running-game check counts a `gmod.exe` it cannot open as running from this folder
(`loader/core/src/deploy.cpp`, `game_running`). Not changed (a loader change); recorded in RESEARCH.

## Review

An independent Claude subagent reviewed the guard change, replaying each case against the guard before and after it.
It found the depth-only conversion safe (every converted request reaches the engine with depth mode 1, nothing with
3, after every check) and no added cost in the hot `surface.SetMaterial`/`render.SetMaterial` paths beyond a table
read. Its findings and what became of them:

| # | Finding | Outcome |
|---|---|---|
| 1 | Medium: a refused name stayed refused for the session even when a texture of that name existed (refused then allocated; allocated then refused once; `rt_scale_0.75` matching `rt_scale_0.5` through the extension-stripping key; an engine `_rt_` name) | Names are exact (a `.vtf` suffix aside), never `_rt_`, not recorded when already allocated and cleared when allocated later; each case is in the `hud_composite` scenario |
| 2 | Medium: a refused `surface.SetMaterial` left the inert flag set, so another add-on's `surface.SetTexture` draws (`draw.RoundedBox`'s corners) were skipped | `surface.SetTexture` clears the flag; in the scenario |
| 3 | Low-medium: a material created naming a refused target got a permanent creation hint, never cleared by a later good binding; a repeat `CreateMaterial` of a name could hint the cached material | Such a material is marked lost (cleared by a good binding) at its first creation only; both in the scenario |
| 4 | Low: the mark ignored why the mutation was refused (an effect-source caller) and applied to the package's own callers | Marked only when the texture itself is refused; bundled callers keep native behaviour |
| 5 | Low: the refused names were unbounded | At most 1,024 (and 8,192 created names) |
| 6 | Low: the mark was per Lua object, and GMod can hand out two for one material | Kept by the material's name |
| 7 | Low: the conversion covered float, 16-bit, R32F and default formats, which real depth passes use | Only the 8-bit colour formats; a float request stays inert, in the scenario |
| Nits | Every `SetString` key checked against refused names; docs wording on the override setters | `$basetexture` only; wording fixed |

## Tests

`tools\test.ps1 -Config Release` passed on the final tree: repository conventions, 30 of 30 C++ tests and 29 + 26 + 775
Python tests, among them [`test_render_guard.py`](../../tools/tests/test_render_guard.py.md) with the `hud_composite`
scenario (HUD Mk.2's request, the refused-texture rule and each case the review raised). The package built from the
final tree ran once more in the PoC under RTX with both add-ons: the target adapted, the materials bound to it, the
whole probe ran, no fault and no Lua error but the probe's own blocked `lua_run`; the Steam overlay was open over that
session's screenshots, which show the scene and the HUD under it.

## Published

(Filled in after the push.)
