# The changelog on the Workshop, noclip and broken glass, the crosshair under frame generation: report (2026-11-14)

The user's requests of 2026-11-14, after the GitHub issue 1 round: "Update the standard, from now on the changelog
should also be posted fully to the Steam workshop update log. Address two minor bugs: 1. No-clipping players can
interact with physical scattered glass. 2. Draw the crosshair as the UI texture is not so already, so it won't be
affected by frame generation." Done by Claude on the branch `glass-crosshair-1114`: tooling, the glass add-on and
runtime patch 0094; no loader (`winmm.dll`) change.

## The changelog on the Workshop ([ADR 0222](../decisions/0222-the-workshop-change-notes-carry-the-changelog.md))

Every upload of item 3829070317 posted a one-line change note (the version and the commit). Now
`tools/publish_workshop.py` posts after that line, in full, every `CHANGELOG.md` entry of `[Unreleased]` that the
uploaded commit has and the commit of the item's last upload lacked, in Steam's markup and ASCII (`gmpublish.exe`
reads its command line in the ANSI code page). What one note cannot hold (Steam keeps 8000 characters) goes up in
further notes with the same archive: Steam uploads only changed chunks (16.3 MB of the 2 GB package last time, 25 s).
Releases (`--from-ci`) do the same. `--show-notes` previews the notes. AGENTS.md rule 5 and the documentation duties
say so: changelog entries are public on the Workshop from now on, so they say first what changed for the player.

## Noclip and broken glass

**Cause.** R14 made a player in noclip or spectating pass through broken glass (`debris_scene.lua`: such a player is
neither living nor a body). But `kind()` excluded an equipped weapon only while its owner was living, so a flying
player's weapon fell through to an object (kind 1), which the default mask (objects and ragdolls) mirrors: a box at
the player's feet moved through the pieces and kicked them around.

**Fix.** A player's weapon is never an object of its own, whatever the player's state, and an entity parented to a
flying or spectating player is not a body either; one parented to a walking player follows the objects bit as before.
The harness's `scene_ghost_carries` (`test_glass_interaction.py`) checks it with the default mask and with every
category, and fails on the code before the fix.

**In the PoC** (gm_construct, `out/gx-qa/glass_noclip_probe.lua`: a settled pile of broken pieces through
`NLGlassDebris.Spawn`, then a pass in noclip with the physgun out, then a walking pass with living players on):

| Package | Pile | Noclip pass | Walking control (mask 15) |
|---|---|---|---|
| published (`c7ab57a1`) | 232 pieces, 0 moving | up to 318 moving, 404 pieces after splits | up to 294 moving |
| this branch | 288 pieces, 0 moving | **0 moving, no split** | up to 298 moving |

## The crosshair under frame generation ([ADR 0223](../decisions/0223-frame-generation-gets-the-frame-before-its-ui.md))

**Cause.** The crosshair is already UI to Remix: GMod draws it in 2D with an orthographic projection, which
`isRenderingUI()` takes for UI, and it is rasterized over the path traced image after injection, like the HUD. A UI
texture tag would change nothing. Frame generation moved it: Remix gave DLSS-G only the finished back buffer, motion
vectors and depth, so DLSS-G moved every pixel with the scene's motion, the UI's too.

**Fix.** Runtime patch 0094 gives DLSS-G the frame before its UI, NGX's HUD-less colour (`pHudless`): the D3D9
swapchain keeps a copy of its back buffer while the frame generation presenter runs; injection blits the final output
into it after the game's target; the present blits it beside each frame generation back buffer with the back
buffer's own blitter call; the present thread passes it only for a frame that filled it. Built from fork branch
`claude/dlfg-hudless` (`81b4d393` on 0093's `20e3553e`) by `build_runtime.ps1`: `d3d9.dll` 478,622,720 bytes,
SHA-256 `55b30956085671e3d1d970a6da65e8d52c402b51f15304c50d1c5836a575b27d`. The handoff's unit test (38 checks) runs in
the Release gate from the patch (`test_dlfg_hudless.py`).

**In the PoC** (`out/gx-qa/fg_probe.lua`: DLSS Frame Generation on through the Remix API, a test bar and a one-pixel
test cross beside the crosshair, the view turning; `fg_capture.py` samples the window through `PrintWindow`, which
returns generated frames too, even with the window covered):

| Setting | Published runtime | Runtime 0094 |
|---|---|---|
| 1280x720, about 560 rendered frames a second, one generated frame each, 60 degrees a second | bar and dot intact in 1,145 samples | intact in 1,140 samples |
| 3840x2160, three generated frames per rendered one, 180 degrees a second | ghost copies of the crosshair dot in 16 of 290 samples, the bar damaged in 22 | **no ghost in 305 samples, the bar intact in all**; the cross's darkest pixel median 207 against 173 |

The runtime logged `[DLFG] frame generation gets each frame before its UI (HUD-less input), from frame 87` in every
0094 session; no frame generation error, device loss or crash; normal quits. The PoC's `user.conf` and `rtx.conf` were
byte-identical before and after; the loader was uninstalled afterwards and the install verified against Steam's
manifest. Evidence: `out/worktrees/gx/out/gx-qa` (`poc/` sessions 01-13, `fg-old-4k`, `fg-new-4k`, `fg-compare.json`).

## Found on the way

- Changing `rtx.dlfg.maxInterpolatedFrames` while frame generation runs stopped the published runtime's presenter
  (`DxvkDLFGCommandListArray::nextCmdList: vkWaitForFences failed`; the window kept answering, nothing more was drawn).
  Off, change, on again works. Not fixed here; open.
- `fps_max` cannot be set from Lua, and ffmpeg 6.1.1's Desktop Duplication source has no `dup_frames`
  ([RESEARCH.md](../RESEARCH.md)).

Not covered: the field install; VR (frame generation is off there, ADR 0205); FSR frame generation (it already had
the final output as its HUD-less colour).

## Open

- The multiplier change while frame generation runs (above).
