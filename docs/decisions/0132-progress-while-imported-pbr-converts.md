# 0132: A progress notice while imported characters' PBR converts; one top-right notice

- Status: Accepted 2026-11-08 (R23, the user's item 3); the notice of
  [ADR 0129](0129-the-upscaling-hint-also-at-the-top-right.md) becomes a shared module, its look and timing
  unchanged
- Context: the user: "If the user import a model with PBR and the game is processing them before they are
  applied, let the user know it is loading and show a small progress bar to the user."

## Decision

1. The RTX fixes' ToPBR driver counts the imported game materials it submitted whose native view still says
   `waiting`, and how many the batch had (`RTXGamePBRProgress()`); the batch ends when none is pending. An
   unreadable view counts as finished.
2. The companion polls it four times a second (`nativeloader_pbr_progress.lua`). Once a batch has lasted
   1.5 s it shows the top-right notice with "Preparing PBR materials for imported characters: done of total."
   and a bar, updates both, and ends with "PBR materials for imported characters are ready." for four seconds.
   A batch restored from saved maps within 1.5 s shows nothing; a notice the player closes stays closed for its
   batch. Translated (`L`).
3. The top-right notice is one companion module, `nativeloader/notice.lua`: R22's frame generation hint, the
   start-up stall notice ([ADR 0130](0130-an-engine-guard-for-lua-start-up.md)) and this progress use it. It
   gains an optional bar, lasting notices (`seconds = 0`), text and progress updates, and a finish; notices
   stack below every other notice-sized panel in the corner, including the companion's own.

## Consequences

A player who spawns an imported character sees that its PBR is being prepared and how far along it is, and
when it is ready. The cost is one native view read per pending material, four times a second, only while a
batch is pending.
