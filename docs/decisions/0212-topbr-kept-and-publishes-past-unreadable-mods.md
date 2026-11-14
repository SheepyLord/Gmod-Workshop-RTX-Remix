# 0212: ToPBR stays, and publishes past mods it cannot read

- Status: Accepted 2026-11-14 for GitHub issue 6, on branch `qol-topbr`; awaiting the user's review and an in-game
  check (package only, no loader change).
- Decided by: Claude, from the session's brief ("decide whether we need to fix, migrate or remove to pbr that we
  inherited from the old repo and address user's issue and concern").
- Context: [GitHub issue 6](https://github.com/SheepyLord/Gmod-Workshop-RTX-Remix/issues/6), "Gmod ToPBR stopped
  loading?" (opened 2026-11-13): after enabling ToPBR "the GmodtoPBR file in the rtx-remix folder does get bigger, and
  if I open it I can see materials being made, but in game I do not see them"; reinstalling, disabling add-ons and
  rolling the loader back three times changed nothing. The owner first replied that ToPBR was inherited and replaced,
  then that the reply may be wrong.
- Amends: [ADR 0091](0091-automatic-pbr-fallbacks.md) "Replacement precedence and scope limit" (its rule that an
  unreadable mod suppresses all generated output) and the last paragraph of [ADR 0092](0092-generated-fallback-mods-rank-last.md)
  "Decision", which kept that rule as a coverage limit. Everything else of both stands.

## What happened

ToPBR's worker publishes its materials as `rtx-remix\mods\~gmod_topbr\materials.usda`, every 3 s when they change.
Before each publication it scanned every other mod's USD text for `mat_<hash>` names, to leave out the textures an
authored mod covers. Since R11 (2026-11-02), a scan that could not read every file published nothing
(`FallbackGuard::Select` returned an empty set when `complete` was false): one binary USD, one USD over 16 MiB, more
than 64 MiB of USD text, more than 32,768 entries, a link or a folder 17 deep. Conversion was not stopped, only
publication, so `~gmod_topbr\textures` filled with DDS files named after the materials while `materials.usda` stayed
`over "Looks" {}` and the console said `Published 0 fallback materials (N authored hashes, scan=uncertain/suppressed)`.
That is the report, word for word: the folder grows, the files show materials being made, nothing shows in game, and
nothing the player tried could change it, because the cause is a file in their `rtx-remix\mods`.

Binary USD is ordinary: the RTX Remix Toolkit saves meshes as `.usd` crates, and many RTX map packs carry them. The
owner's own field install shows it: 26 unread files in three content packs (binary models in `country_estate_rtx`,
`funkis_rtx` and `safehouse_rtx`, a 29 MB `.usd`), 65.5 MB of USD text in 33 mods, and a `materials.usda` that has
last written 2026-11-11, empty; with the packs installed on 2026-11-12/13 every later publication is empty too. The
same snapshot carries Imported game PBR, so imported characters lose their game maps
there too. Which file the reporter has is not known; the reply asks for the console line.

Nothing in the runtime is at fault: its mod-load cache (patch 0086) is used only for a mod's first load and keys
every entry on size, write and change time and file id; hot reloads read as before; and the generated mod's root layer
is touched after each publication, which the runtime's directory watch reports.

## Decision

1. **ToPBR stays, fixed.** It is the only part of the package that gives Source materials (maps, props, weapons,
   view models) Remix PBR from what their VMTs already have: bump and normal maps, SSBump, Phong and envmap masks, and
   the community PBR shaders (ExoPBR, GPBR, MWB, BlueFlyTrap). The "alternative system" is Imported game PBR (R11-R13),
   which covers only Model Hotloader imports whose source folder holds a game's packed maps. Both run in the same
   native `TextureProcessor` and publish into the same mod, so removing ToPBR would remove nothing but its switch, and
   migration has nowhere to go. World conversion stays off by default (ADR 0091).
2. **A partial scan no longer suppresses.** `FallbackGuard::Select` publishes every generated material whose hash no
   readable mod names. The runtime already ranks `~gmod_topbr` after every authored mod (patch 0020), so an authored
   material in a file the scan cannot read still wins in game; the scan only spares duplicate work and memory. The
   fixes module ships only in the package that ships that runtime.
3. **The scan is bounded per scan and cached.** At most every 30 s, none with both switches off; a file is read again
   only when its size or write time changed; a binary crate costs its 8-byte magic; a scan reads at most 64 MiB of new
   text and the next one continues; 65,536 entries. Before, every 3 s publication read every mod's USD text, even with
   ToPBR off (Imported game PBR is on by default): about 65 MB every 3 s on the owner's field install.
4. **The console says why once**: `Mod scan partial (N of M USD files not read; first: ...)`, and each publication
   line ends in `scan=complete` or `scan=partial`.
5. **The menu says what each page is.** "ToPBR" becomes **Map and prop PBR (ToPBR)**: what it builds and from what,
   that it is off by default, that a real PBR mod always wins, that imported characters use Imported game PBR, and
   where its textures go. The "Experimental Metallic Detection" switch leaves the page: since R11 darkness never makes a
   material metal and `rtx_topbr_metallic` changes nothing (the convar stays for old configs). Imported game PBR's page
   gains a line pointing maps and props to ToPBR. Turning ToPBR on queues the materials already drawn, so "Requires a
   map reload to enable" is gone.

## Consequences

- An install with any mod the scan cannot read sees ToPBR's and Imported game PBR's materials again, from the first
  publication after the update. An authored replacement in an unreadable file is drawn as before (patch 0020).
- A texture an unreadable mod covers may also get a generated material that is never drawn; its textures load only at
  first draw (runtime patches 0026, 0030), which never comes.
- The fixes module grows by about 79 KB (5,518,848 to 5,597,696 bytes, with ADR 0213's patch).
- Not verified in a game: the in-game checks are in the [report](../handover/issue6-topbr-report.md).

## Alternatives

- **Remove ToPBR**: removes a working opt-in feature some players use, and Imported game PBR with it unless its
  publication were split out first.
- **Read binary USD**: a crate's token table is LZ4-compressed and its layout versioned; patch 0020 makes the answer
  unnecessary.
- **Keep suppression, tell the player which file**: leaves the feature off for most players with a map pack.
