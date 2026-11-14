# 0213: Automatic categorization keeps the player's choices and its own bounds

- Status: Accepted 2026-11-14 on branch `qol-topbr`, with [ADR 0212](0212-topbr-kept-and-publishes-past-unreadable-mods.md);
  awaiting the user's review and an in-game check (package only, no loader change).
- Decided by: Claude, from the session's brief ("the auto-categorization, if in use, should be made more robust":
  wrong categories, failures, map changes, conflicts with the user's own `rtx.conf` categories, idempotence, bounded
  work).
- Context: the RTX fixes' Auto-Categorization (Utilities > RTX Remix), inherited like ToPBR. It is on by default
  (`rtx_auto_categorize 1`; the classic defaults turn World Geometry, Particles and Overlay Decals on and Legacy
  Emissive off).

## What it does

- **At each map load**, after `rtx_auto_categorize_delay` (3 s), Lua (`cl_remix_category_0_manager.lua`) reads the
  BSP through NikNaks and marks the map's brush materials, blended displacements and static-prop materials as decals
  (`rtx.decalTextures`, DECAL_STATIC: Remix then blends them as world geometry), except translucent and `no_decal`
  brushes; `$decal` materials as decals; `$selfillum` and unlit materials as legacy emissive (with force-albedo for
  unlit ones). It sends the list to the native side, which marks those materials when they are drawn later.
- **At every new texture draw**, the native pipeline (`AutoCategorisation`) marks particles and sprites, decals,
  animated water, sky and ignored detail textures, with rules for hashes two materials share (water is never a decal,
  world geometry outranks particle, a contested emissive hash loses its glow).
- **Every write goes to the runtime's user layer** (`remixapi_AddTextureHash` / `RemoveTextureHash`), the strongest
  layer and the one Save Settings writes to `user.conf`.

## What was wrong

1. **World Geometry did nothing**: `rtx_auto_categorize_world` was never read; Overlay Decals did not govern the map
   scan's own `$decal` branch.
2. **The map scan ran in one frame** with a quadratic de-duplication, one or more GAME-path VMT reads per material
   (1-3.5 ms each with many add-ons) and a console line per categorized hash; on a large map that is a freeze of
   seconds three seconds into the map.
3. **The queue grew without bound and was checked whole every frame**: every Scan Now or second pass added another
   entry per material, and every BSP material not yet drawn stays queued (two native lookups each per frame).
4. **One unreadable material stopped the scan** (a Lua error ends it).
5. **Blended displacements were looked up under names the tracker never uses** (`maps/<map>/..._wvt_patch` and two
   variants), so they waited forever.
6. **Switches and map changes left work behind**: switching off did not empty the queue, and a scan or a delayed
   start of the previous map could still run.
7. **The player's own choices lost.** A texture taken out of a category in the Remix developer menu (a `-0x...` entry
   in `rtx.conf`) was put back by the next automatic pass in the stronger user layer, every session.

## Decision

1. **The scan is a job** of at most 2 ms a frame (a coroutine resumed from `Think`), with set-based de-duplication,
   one VMT read per material per scan, one summary line, and per-material `pcall` (an unreadable material is counted
   as "Unreadable" and skipped). Scan Now and the map load start it; a running scan restarts.
2. **It obeys its switches**: World Geometry governs brushes, displacements, static props and the native world list
   (cleared when off); Overlay Decals the `$decal` branch; Legacy Emissive the emissive one. Switching World Geometry,
   Overlay Decals or Legacy Emissive (or the master switch) drops queued automatic work and scans again; switching off
   applies to textures not yet categorized (a restart removes what was).
3. **One queue entry per material**, merging later requests' bits and callbacks; at most 16,384 entries; each frame
   checks at most 64, in turn.
4. **Blended displacements are named as the tracker names them** (no `maps/<map>/` prefix or `_wvt_patch` suffix, as
   `MarkWorldTextures` and `rtx_look_hash` already did).
5. **Map changes start clean**: a token per map load stops the previous scan and its delayed start; the queue is
   emptied.
6. **The player's `rtx.conf` wins over automatic adds** (the fixes' twelfth native patch, `player-categories`): no
   automatic path adds a hash to a texture list the player's `rtx.conf` takes it out of. The native paths ask it
   directly; `RemixMaterial.SetHashCategory` asks it when its new third argument is `true`, which the category manager
   passes for automatic work only. Manual commands, the player body's proxies ([ADR 0043](0043-player-body-viewmodel-and-shadows.md))
   and RTX Water's own textures are not limited. `rtx.conf` is read again when it changes.
7. **Removals and `user.conf` are left as they are.** Automatic removals correct automatic leftovers (water saved as a
   decal: 4 hashes in the owner's field `rtx.conf` and `user.conf`, 33 in the package's classic defaults); blocking
   removals for every `rtx.conf` entry would freeze those. Remix writes texture lists to `user.conf` only from automatic
   categories a Save Settings kept, so its entries are not the player's choices.

## Consequences

- A big map's categorization no longer stalls a frame; it finishes over more frames (the summary line says when).
- A player who un-categorizes a texture in the developer menu and saves `rtx.conf` keeps that from the next session
  on. In the session of the change the runtime's user layer still holds the automatic opinion, which the developer
  menu shows as set by a stronger layer.
- Automatic categories still live in the user layer and still go into `user.conf` when the player saves settings; a
  runtime change (an unsaved layer for API category writes, below `rtx.conf`) would end that, at the cost of the
  correction above for leftovers already in `user.conf`. Left open for the user.
- The C++ categorizer's rules themselves (decal for world geometry, particle shaders and paths) are unchanged.

## Alternatives

- **Protect every hash the player's files mention, both ways**: freezes the leftovers the water and contested-hash
  rules correct today (both files hold dozens).
- **Read `user.conf` too**: treats saved automatic categories as the player's.
- **Turn auto-categorization off by default**: the classic install had it on, and maps rely on its decal marking.
