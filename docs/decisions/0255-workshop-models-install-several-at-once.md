# 0255: Workshop models install several at once, below normal priority, without a library rebuild each

- Status: Accepted 2026-11-21 (the user's report: after a fresh subscription to a content pack, "the game is laggy for
  each item. Please optimize this lag and the speed of installation")
- Package only: the Model Hotloader's `workshop.lua` and `library.lua`, and its natives (`module.cpp`,
  `source/install-priority.patch`). No loader change.

## Context

A content pack made with the workshop-content-pack skill carries a Model Hotloader package: a manifest in
`data_static/mmdhl/packages/` and each file of each model, compressed, in `data_static/mmdhl/files/`. Every client
installs its models into the player's cache (`workshop.lua`). The pack in the report had twelve characters (with the
RTX package's own two models, 196 files and 416 MB to install).

Measured in the PoC with `tools/qa/pack_install_session.py` (the pack and the RTX package as local packages, a fresh
library, gm_construct at 1600x900):

- **Slow:** the install took 76 s for the pack's twelve characters and the package's own two models. It went one model
  at a time and one file at a time. 64 s of it were the models' asset checks: `StartAssetCheck` loads each character as
  a spawn would (`loadAsset`: its model and texture hashes, the alpha coverage of its cut-out textures, its Source
  materials, which decode every PNG and write each as an uncompressed VTF with mip levels and again into
  `materials-v5.gma`, and its collision fit), 1-13 s per character, on one thread. Moving the files took 11 s
  (streaming 4 s, the natives' commits 7 s). The main thread's own share was small: the install's Think hook took 0.33 s
  of its own time over a 68 s install.
- **A hitch per model:** each installed model asked for a full library rebuild 0.25 s later. A rebuild reads every
  character's settings, checks every manifest's size and time, reads the props' catalog, and rebuilds the library
  window when it is open. With a library of the user's size (220 characters and 20 props, copied into the PoC) and the
  spawn menu open on the Model Hotloader's tab, each model's rebuild took a frame of 100-140 ms (fresh library: 40-90
  ms). Each model also wrote the whole Workshop state file twice.

## Decision

1. **Models install side by side.** The install keeps a few models in hand (`MaxActive`, two more than the checks). The
   main thread streams one file at a time from its package into the native transfer, within the same 4 ms of each frame
   as before. Up to three commits run in the natives at once, and a model whose files are all in place starts its asset
   check at once, while later models' files arrive. Up to `MaxChecks` checks run side by side: one per six logical
   threads, from one to four (`GetWorkerCapabilities`; four on the user's 32-thread computer).
2. **A file moves once.** A file two models list (a shared texture) is not moved for the second while it moves for the
   first. The second model then finds it written and verified this session (same size and time) and needs no hash of
   it on the main thread. A file of the right size already on disk is hashed as before (`SharedFileMatches`).
3. **A check that failed beside others runs once more alone.** Every check's failure is reported as `invalid` (which
   deletes the model's manifest), and a load's memory budget counts what the other checks hold. A failure while
   another check ran is therefore tried again alone, before the model is refused.
4. **Installed models are added to the library on their own** (`library.Add`: the entry a rebuild makes, from that
   model's manifest and settings alone; one revision and one `MMDHL.LibraryChanged` per batch). They are added at most
   every four seconds while models install, the first at once, the rest when the last one is in. Each character's
   manifest is decoded as it installs (`library.Prime`, up to 20 ms for a large one), so an update that lists several
   decodes none. A full rebuild (packages changed, a deleted model loaded again) still runs 0.25 s after it is asked
   for, once for a burst, and lists whatever was installed meanwhile.
5. **State saves wait a moment.** A model's install record is still written before any of its files ("installing", one
   write for the models taken together), so an install that stops part way is resumed by the next scan. The installed
   record and verify's file times are written a second later, once for a burst, and at the batch's end and at
   shutdown. A record lost to a crash costs only a check.
6. **The install work runs below normal CPU priority** (`BackgroundWork` in the natives, around a commit and an asset
   check: `THREAD_PRIORITY_BELOW_NORMAL`, the thread's priority given back after), so the game's own threads come
   first with several checks running; its I/O and memory priority stay normal. A spawn's load (`RequestAsset`) keeps
   the game's priority.

## Consequences

- The pack installs in a fraction of the time, models appear in the library in a few steps instead of one per model,
  and there is no rebuild of the whole library for each model (measured: see the handover report,
  [pack-install-report.md](../handover/pack-install-report.md)).
- More happens at once: up to four checks, each holding a character's model and one decoded texture at a time, and
  writing its Source materials. That is a few hundred MB more memory at the peak and more disk writes per second,
  below normal CPU priority.
- The library window shows new models up to four seconds after they install, instead of a quarter of a second.
- A dedicated server's installs follow the same code (its realm has no library to list them in).

## Rejected

- **Skipping the Source materials and fit in the install's check** (validating only): the check is the model's first
  load. A character whose materials are not built at install builds them at its first spawn, which then waits seconds
  for it.
- **A full rebuild after the last model only:** the library would show nothing new for the whole install. Coalesced
  full rebuilds still cost 100 ms or more each in a big library.
- **Trusting cached manifests without their size and time** (ADR 0238 decided to check them): would save a few
  milliseconds per rebuild, and a rebuild no longer runs per installed model.
- **Building each character's textures on several threads within one check:** more work in the natives' conversion
  code, while checks side by side already use the threads.
- **Windows' background mode for the install work** (`THREAD_MODE_BACKGROUND_BEGIN`, the first build): it also lowers
  the thread's I/O and memory priority to very low. In the PoC the frames were as smooth, but beside other checks a
  large character's check, which writes about a gigabyte of Source materials, took 93-114 s instead of 8-13 s, and
  the pack took longer than before (119 s).
