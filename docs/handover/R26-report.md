# R26 report: the sky without a horizon; faster map loads

The user's request of 2026-11-09, two items:

1. "In the sky and weather tab, add an option to allow the sky to be rendered in the whole sky box (like some universe
   / floating island maps), disabling the horizon." The user's answer: a no-horizon option in the sky options; when it
   is on, the whole sky box shows the sky, with no horizon effect.
2. "Implement the plan for the loading speed optimization", with the user's answers to the plan's nine questions
   ([ADR 0140](../decisions/0140-the-load-accelerator.md) quotes them): hook or pack anything with the Workshop
   add-on; package only, reporting limitations, and it should also run without RTX; on by default; a dropped-in add-on
   may wait for a restart but an edited Lua or material file must show; the user's Workshop items and GitHub may be
   updated; the package's add-on folders stay; the implementation is ours; third-party add-ons only patched from the
   package, robust to their updates, and the optimization general; no refusal after a GMod update. Verbose progress
   during the load; each item to a deliverable state, lower risk first, dropping what is not needed.

Done by Claude, with Claude subagents (the sky option, the review); no Codex.

## 1. The sky without a horizon

**No horizon** under Sky in the RTX Remix tab's Sky and weather panel (`nativeloader_sky_no_horizon`, off by default,
saved like the other sky settings; [ADR 0139](../decisions/0139-the-sky-without-a-horizon.md)). The runtime had no
such option, so runtime patch 0041 adds `rtx.atmosphere.noHorizon` (the dev menu's No Horizon under Atmosphere; it
takes the `r18Pad0` slot, so the constant buffer keeps its size, and a change bakes only the sky-view lookup table
again). With it on, a direction below the horizon shows sky instead of the planet's even ground haze:

- the sky's colours from its mirror above, continuous at the horizon;
- the clouds and high clouds of the opposite side of the sky (a mirror of them read as a lake's reflection);
- the sun's glow, silver linings and halos around the real sun only;
- the stars, the galaxy and the moon wherever they are (a moon below the horizon was a black disc; it is lit now).

The sun still sets: below the horizon it is night. It also reaches a map add-on's own sky, but toggling it does not
take that sky over. Off, the rendering is unchanged (an A/B of off against the packaged runtime in the PoC: within the
frame-to-frame noise). Its cost at 3840x2160, on: about 0.5 ms in clear weather, 1.2-1.8 ms partly cloudy, up to
3.2 ms overcast (the clouds below the horizon are marched). The guide's Sky and weather picture shows the checkbox;
the texts are in the six languages. The runtime was built through `runtime\build_runtime.ps1` and imported:
`d3d9.dll` 418,258,944 bytes, SHA-256 `35ce5008...`, `remix-main+17dcc86c`.

What it leaves (ADR 0139): the bright band of the sky's own gradient at eye level stays on both sides, so a soft line
remains where the horizon was in daylight (at night none is visible); clouds below are seen from underneath; a
reflection of the lower sky may put a silver lining in the wrong place; a moon below the horizon does not light the
scene.

## 2. Faster map loads: the load accelerator

The work was first a plan (R24's evidence, `out/load-speedup/PLAN.md` in the worktree `recursing-cartwright-4600e1`).
What was built ([ADR 0140](../decisions/0140-the-load-accelerator.md), [`fs_accel`](../../fs_accel/README.md)):

- **A: failed lookups in the loose add-on folders, from directory listings.** GMod tries every folder add-on on disk
  for each game file before the mounted archives, and a missed open twice. Import hooks on `filesystem_stdio.dll`
  (`CreateFileA/W`, `GetFileAttributesExA/W`, chained after the loader's own) answer "not there" from a listing of the
  folder taken on first use, with Windows' error codes; every positive lookup still reaches the disk, so an edited
  file shows; a watcher stops caching a folder that changes. Installed at menu start by the companion's menu script
  `load_accel.lua`.
- **B: `file.Find(pattern, <add-on title>)` from an index of GMod's add-on table.** GMod walks every file of every
  add-on for each such search (Extended Spawnmenu makes 2,263 right after a map loads). The module reads the table
  under SEH, checking every link and size, and the add-on `nlloadaccel` answers those searches from the index after a
  self-test against GMod's own answers. No GMod or third-party code is patched, so it is general and survives their
  updates (answers 8 and 9).
- **C1: no spawn-menu rebuild at every start.** The bundled bullet-break simulator, and the user's Workshop item
  3789611737 as 0.19.16 (its 0.19.15 with that change alone), rebuild the spawn menu after their settings-layout
  migration only in a running game (a Lua refresh).
- **Progress during the load:** the load overlay's status line counts the lookups answered ("N file lookups answered
  from memory"), the end-of-load line names the total, and the client prints the load's tally.
- **Off switches:** `nativeloader_load_accel 0` (archived, from the next start), `nativeloader_load_accel_verify 1`
  (every answer also asked of GMod and Windows, differences counted). A start that ended within 20 s of installing the
  hooks leaves them out once: a native marker, because the menu realm cannot write files.

Dropped, with the reasons in ADR 0140: B0 (an Extended Spawnmenu patch; B covers it generally), C2 (the companion's
`i18n.lua` already caches), C3 (merging the package's folder add-ons; answer 6, and A removes their cost), D
(per-add-on blame), E (prefetch for cold loads: not measurable here), F (an ARC9-only icon patch), G (memoizing Lua).

### What cannot be done from the package: starts without RTX

The user asked that it also run without RTX. It does not, and cannot without a loader change: the combined RTX
package is marked `requires_remix` (any part that needs Remix marks it, `tools/package_workshop.py`), and in a start
without RTX the loader leaves every add-on folder of such a package out of GMod's searches
([ADR 0013](../decisions/0013-rtx-only-addons-hidden-without-rtx.md); the PoC's `session.json` listed `nlloadaccel`
among the 25 folders left out), while GMod never mounts the package's own archive (its native files are outside
GMod's whitelist). So no Lua of the package runs there, and nothing loads the modules, which stay in
`garrysmod/lua/bin`. A loader change could keep one part's add-on folder visible (a per-part flag in the manifest); it
was not made, as the user asked for the package only and loader changes wait for approval. The C1 change reaches
starts without RTX through the user's Workshop item, which every start mounts.

## Review

An independent Claude subagent reviewed the accelerator's code (not anchored on this report). It found no case where
part A answers "not found" for a file that exists (it checked case folding, non-ASCII names, 8.3 names, devices,
trailing dots and spaces, streams, `.`/`..`, `\\?\` and UNC paths, junctions and links, folders with case-sensitive
names, the watch armed before any listing), and no crash or deadlock in the hooks beyond what the table lists. Each
finding and what became of it:

| # | Finding | Outcome |
|---|---|---|
| 1 | Medium: part B's tree walks could loop forever on links that never end (a different layout, or a tree changing while read); SEH stops only access violations, and nothing guarded B | Every walk has a step budget (under 2n + 64 steps); links that never end are refused. A CTest points a link back at its own node |
| 2 | Medium: the start-up marker came off 20 s after menu start, before the first map load, where most lookups are | The marker stays until a map has loaded with the hooks and 20 s have passed: the menu script says so 10 s after the first load ends, the add-on 5 s after `InitPostEntity` (a dedicated server's own) |
| 3 | Medium-low: the self-test could pass without testing an add-on; a title GMod's table does not hold turned B off | It scans the list until three mounted add-ons agree, skips one GMod finds nothing under, needs at least one, and gives no verdict while the table is changing |
| 4 | Medium-low: `nativeloader_load_accel 0` could not reach the menu realm (it cannot see a client's Lua convar), so part A was still installed | The client keeps `data/nativeloader/load_accel_off.txt` while it is 0; the menu script reads it and makes no convar of its own |
| 5 | Low: the index could go stale after an unmount and a mount that leave every size the same | The fingerprint mixes in every list node (its address, owner, title and path); a CTest remounts that way |
| 6 | Low: a name another program creates in a cached folder reads as missing until the watcher's notification lands | Documented in ADR 0140; nothing in the package writes into a cached folder while the game runs |
| 7 | Low: a table that changes again and again would be read whole for each search | At most one build every 2 s; GMod answers meanwhile |
| 8 | Nit: two folders whose names differ only in case could share a cache key | Neither is cached |
| 9 | Nits: a map change turned off checks turned on in the other realm; the watcher test could pass before the watcher re-armed; a lock a thread held when the process began to exit; the README's "write open" | The checks' switch is passed on only when on; the test waits for the change to be read and checks the drop; once the process shuts down nothing is answered and no lock is taken; wording fixed |

## Measured

The PoC with the user's 774 subscriptions mounted, gm_construct (`out/r26/poc_r26.py` in the `r26` worktree; the
PoC's own loader, deployment and data moved aside and put back each time, rollback clean).

**`check -b`** (the package built here, the checks on: every answer also asked of Windows and of GMod):

| Session | What it showed |
|---|---|
| RTX start | The menu script installed the hooks at menu start, 25 folders cached. 1,743,871 hooked calls, 1,585,988 answered as missing (91 %), 2,882 passed on, 194 listings, **0 disagreements** with Windows. The load overlay's end line: "the load accelerator answered 1,449,260 file lookups from memory". The index: 117,720 entries, built once; Extended Spawnmenu's 2,253 searches answered from it, 2 left to GMod. Every mounted title searched with 17 patterns, the index against GMod: **13,158 searches, 0 different** (790 left to GMod: the folder-wildcard pattern for each title, and a title GMod's table does not hold). The start's marker was gone afterwards. |
| Start without RTX, a marker of a gone process planted | Nothing of the package ran (the loader hid its 25 add-on folders); the marker was untouched. |
| RTX start after it | "left out once" in the menu, the server and the client realm; the add-on searches still answered from the index (2,253); the marker removed. |

Earlier runs found what the unit tests could not: the menu realm cannot write files (the first marker was Lua; it is
native now), GMod gives a name once when two add-ons share a title, and no tables for a wildcard in the folder part;
the index follows both.

**`timing`** (the published package, 0.0.0-dev.20261109063824, against the package built here with the review's fixes
and the sky option merged; RTX starts, alternating, the checks off; seconds from the server's first Lua to
`InitPostEntity` and to the game responding, no frame over 100 ms for 2 s; "map loaded" is the load overlay's own
line):

| Session | First Lua to `InitPostEntity` | Then until it responds | In all | Overlay's "map loaded" |
|---|---|---|---|---|
| Published, 1st (the first start after the install) | 19.4 | 12.3 | 31.7 | 24.1 |
| Built here, 1st | 12.1 | 5.2 | 17.4 | 12.8 |
| Published, 2nd | 17.7 | 8.5 | 26.2 | 18.8 |
| Built here, 2nd | 12.0 | 5.2 | 17.2 | 12.6 |

About 9 s, a third of a warm RTX load, is gone: 5.7 s of the load itself (the failed lookups) and 3.3 s of the freeze
after it (the add-on searches). The index was built once, in 16 ms. Each session with the accelerator ended with its
marker taken off, and the next one installed the hooks again. These sessions also ran the merged package's new
runtime (No horizon off) with no problem.

## Tests

`tools\test.ps1 -Config Release` passed on the final tree: repository conventions, 30 of 30 C++ tests (among them
`nl_fs_accel_tests`, 10 cases) and 29 + 26 + 774 Python tests, among them
[`test_load_accel.py`](../../tools/tests/test_load_accel.py.md) (20 scenarios) and the sky's
[`test_companion_sky.py`](../../tools/tests/test_companion_sky.py.md) (17). The package built here was checked in the
PoC after the last change that reached the game (`timing`, above); the sky option's own PoC sessions are in
[ADR 0139](../decisions/0139-the-sky-without-a-horizon.md) and TESTING.

## Published

- **The user's Workshop item 3789611737** (Procedural Bodygroup Destruction) as **0.19.16**: its 0.19.15 with only the
  spawn-menu rebuild made conditional and the version string changed (`out/r26/c1/make_ws_gma.py` checks that exactly
  those two files differ), packed with `gmapack create --strict` (740,495 bytes, SHA-256
  `52845276e6590e45c638cd8122c82cf9f937c1dcfdbf2a5776f052aa76face04`) and uploaded with gmpublish through
  `tools/publish_workshop.upload` on 2026-11-09; Steam's public record shows 740,495 bytes, updated 13:34:20 UTC, its
  visibility unchanged.
- **`main`** was fast-forwarded to `b698645` (the `r26` branch: the load accelerator, the sky branch `r26-sky` merged,
  the review's fixes) and pushed (0570b6d..b698645, five Git LFS objects, 62 MB: the runtime and the accelerator's
  modules). The merge's hook built the package here and uploaded it to item 3829070317 as
  **0.0.0-dev.20261109133732+adc5cf08** (2,183,829,338 bytes, SHA-256
  `f9e63ed1c9a6a84450a21c0c6c299df0f2faaf23e1c9c7fd6468b835c0992e79`); Steam's public record shows that size, updated
  13:38:11 UTC. The push's hook found the same inputs and uploaded nothing. No GitHub Action was started. The loader is
  unchanged (0.16.0); the runtime gains patch 0041.

## Not changed

- The loader (0.16.0): no change.
