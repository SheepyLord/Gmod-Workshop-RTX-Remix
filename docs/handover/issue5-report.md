# GitHub issue 5: "Default texture pack is not ready: resource_sampling_unsupported" (2026-11-13)

[Issue 5](https://github.com/SheepyLord/Gmod-Workshop-RTX-Remix/issues/5), opened 2026-11-13: one white line in the
middle of the screen, `Default texture pack is not ready: resource_sampling_unsupported:[[0,0,0],[0,0,0],[0,0,0],[0,0,0],[0,0,0],[0,0,0]]`,
on every map (two screenshots, 1920x1080 and 1440x1080, path tracing clearly working). It stayed after the player
disabled their only HUD add-on ("HL2 customizable hud"); "everything seems to be functioning fine", and "if theres any
way to just prevent the message of showing up it would be good enough". The owner answered "Working on a fix, ready
today."

Done by Claude on the branch `claude/issue5-texture-pack-7c440f`; package only (the companion's render guard), no
loader (`winmm.dll`), runtime or native module change.
[ADR 0210](../decisions/0210-an-add-ons-notice-of-the-guards-refusal-stays-off-the-screen.md); the facts with file
and line references are in [RESEARCH.md](../RESEARCH.md) ("GitHub issue 5").

## Root cause

1. **The line is MineMod's, not the package's.** Nothing in this repository (any branch or worktree), the fixes fork,
   the runtime fork, the unpacked package parts, the published `.gma` or the 838 Workshop items on this computer holds
   it. GitHub's code search finds both halves in [schweiziske/MineMod](https://github.com/schweiziske/MineMod)
   ("MineMod Engine", MIT, Minecraft's block worlds in Garry's Mod): its English catalog's
   `"loading.default_unavailable": "Default texture pack is not ready: {error}"` and
   `lua/mc/resources/cl_sampling.lua`'s `reason="resource_sampling_unsupported:"..util.TableToJSON(samples)`. The
   player has MineMod installed.
2. **The render guard makes its texture pack probe read black.** MineMod builds its default texture pack from PNG at
   start, after a probe that draws six full-screen quads with its own shader (`screenspace_general_8tex` with
   `$vertexshader`/`$pixshader`, one per mip level) into a 16x16 target cleared to black and reads the centre pixel of
   each back. Under RTX the guard refuses binding any custom shader (ADR 0086) and binds its transparent material
   instead: the six samples are the clear colour, `[0,0,0]`, exactly as on the screenshots, and the bake fails.
3. **MineMod then shows the failure for the rest of the game.** Its `HUDPaint` hook (`lua/mc/cl_resource_packs.lua`)
   draws the line at the centre of the screen whenever the default pack is pending and its last bake failed; it
   tries the bake again only once per catalog revision, so the line never goes, on any map.

The refusal itself is right and stays: MineMod draws its blocks and passes with its own shaders too, all inert under
RTX for ADR 0086's reasons, and it draws no world while its pack is pending. MineMod cannot work in an RTX session
either way. Only the line was wrong: a permanent notice over the path-traced image whose sole cause is the guard.
The owner's first guess, a HUD or crosshair add-on, fits a centred line, but HUD add-ons were not involved.

## The fix

[`_nativeloader_guard.lua`](../../companion/nativeloader/lua/autorun/_nativeloader_guard.lua) (the companion's render
guard, RTX sessions only):

- A short list of **notices that only report the guard's refusal** (`notices`, `policy.notice`), each matched by the
  exact virtual path of the callback that draws it, its event and the add-on's own failure code. One entry: MineMod's
  `HUDPaint` from `lua/mc/cl_resource_packs.lua`, skipped while `MC.TexturePackPending` is set and MineMod's last apply
  job (`MC.ResourcePacks.jobs[MC.ResourcePacks.lastId]`) has failed with an error that starts with
  `resource_sampling_unsupported`. With the guard on, the probe is always refused, so in an RTX session that failure
  is always the guard's.
- Skipped where the guard already skips known effect callbacks (ADR 0086): in its dispatcher and through the
  registration filter, so a cached original `hook.Call` and the verified multiplayer route skip it too.
- The quieter path is the console: the first time, one `adapted` record and one line,
  `[nativeloader] RTX guard: hook.HUDPaint: MineMod's default texture pack cannot be baked while its shaders are inert
  under RTX: its "Default texture pack is not ready: resource_sampling_unsupported" line is kept off the screen
  (lua/mc/cl_resource_packs.lua)`. MineMod's own console fault and the guard's refusal line for the probe stay. No
  notice window: the player asked for no message, and nothing in the RTX session can fix MineMod.
- Everything else is MineMod's as before: its "Baking the default texture pack from PNG…" line while a bake runs, any
  other failure (a probe that raised an error, a missing file, a restore error), its other hooks and windows, other
  add-ons, sessions without RTX, and `nativeloader_guard 0`. The state is read in `pcall`: anything unexpected shows
  the line.
- `skipCallback` now normalizes a callback's source once and uses it for both the effect and the notice check, so the
  per-frame cost is one table lookup more than before, not another string pass.

## Verified

- **Offline, LuaJIT harness** ([`render_guard_harness.lua`](../../tools/tests/render_guard_harness.lua.md), scenarios
  `minemod_notice`, the early route and the guard's dispatcher, and `minemod_notice_multiplayer`, the verified
  multiplayer route where only the registration filter acts; run by
  [`test_render_guard.py`](../../tools/tests/test_render_guard.py.md)). Stand-ins written for the test carry MineMod's
  source labels (no MineMod code in the repository): its baking line shows; its probe's shader is still refused; after
  the sampling failure its hook is not entered through either dispatcher, with one console note and one record; its
  `Think` hook and another add-on's `HUDPaint` run; other failure codes, a restore error, unreadable state, a pack no
  longer pending and `nativeloader_guard 0` all show MineMod's line as before; an autorefreshed registration is kept
  off the same way. Against `main`'s guard the scenario fails at its first hidden frame (`not drawn: 5 ~= 1`).
- **The gate:** `tools\test.ps1 -Config Release` passed (below).
- **Not run in a game.** No PoC session: the user asked for offline work first and a question before any in-game test,
  MineMod is not installed on this computer, and the PoC is in use by the VR V8 session (`out\r10\poc.lock`). An
  in-game check would install MineMod's add-ons as loose folders in the PoC (from its GitHub repository, or the
  player's Workshop items), start an RTX session, confirm the line is gone, the console note is there and nothing
  else changed, then remove them.

## Gate

`tools\test.ps1 -Config Release` on `9c3bed13`, from the short worktree `out\worktrees\i5` (the long
`.claude\worktrees` path breaks the C++ build, MAX_PATH; `NL_FIXES_CLONE` set to the fixes fork clone): **all checks
passed**: the Release build and 35 of 35 CTest tests; Python 1,854 tests in `tools` (1 skipped), 29 in `tools\gmapack`
and 26 in `tools\steam` (1 skipped each); the repository conventions. The first run, on `98704b87`, failed one test
only: `test_vr_review_docs` wants a branch's additions to the decision index to be table rows, and the entry was a
bullet; `9c3bed13` made it a row. `-SkipNative` in this worktree showed the same single failure before the fix.

## For the player now

Until the package update reaches them: disabling MineMod ("MineMod Engine") in the Addons menu removes the line, if
they do not use it; MineMod's blocks do not show in RTX sessions in any case, so to play MineMod they start the game
without RTX. Nothing else needs changing.

## Draft reply for the issue (for the owner to post)

> Thanks for the screenshots, they made this easy to track down.
>
> That line doesn't come from the RTX package itself: it's from **MineMod** (the Minecraft blocks add-on, "MineMod
> Engine"), which you have installed. When MineMod starts, it tests how the game samples textures by drawing a tiny
> image with its own shader and reading a few pixels back. In RTX sessions the package's render guard switches custom
> shaders like that off, because the path tracer can't render them and they aren't safe there. So MineMod's test reads
> black, its default texture pack never gets built, and it keeps printing that line in the middle of the screen on
> every map, even though nothing is wrong with your game.
>
> The next update of the RTX package keeps that line off the screen in RTX sessions (it leaves one note in the console
> instead). Until then, if you don't use MineMod, disabling it in the Addons menu removes the message. MineMod's blocks
> won't show with RTX on either way, since they're drawn with its own shaders; to play MineMod, start the game without
> RTX.

## Open

- The in-game check with MineMod: offered, and the user chose to merge without it (2026-11-13).
- Posting the reply on the issue: the user's call (the draft is above).
- If MineMod's author wants it, MineMod could detect an RTX session itself and say once that it needs a start
  without RTX; that would be their change, not this package's.
