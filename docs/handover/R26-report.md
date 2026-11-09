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

## Measured

(Filled in below as the PoC runs finish.)

## Tests

(Filled in after the gate.)

## Published

(Filled in after the push.)

## Not changed

- The loader (0.16.0): no change.
