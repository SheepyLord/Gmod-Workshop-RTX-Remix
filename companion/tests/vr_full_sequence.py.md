# Future full acceptance sequence

**Do not run until Claude confirms the separate fixes-module repair is in.**
The deliberate breaking/removal fixtures are unchanged and remain part of acceptance.

After approval, one command per backend:

```
python companion/tests/vr_combined_session.py --case full --fixes-reviewed --simulate --package <fixed gma> --evidence <fresh out folder>
python companion/tests/vr_combined_session.py --case full --fixes-reviewed --package <same fixed gma> --evidence <fresh out folder>
```

Runs a frozen-package sequence of full V2/V3, all-module peer lifecycle, both-hand
geometry, all weapon feature phases, reload calibration/physical/button/empty-reserve,
and tool features. Each chapter uses the production driver, normal rollback and
shared locks; Index chapters take both. Every semantic reducer is mandatory.
sequence.json records package SHA, actual retry folders and per-chapter results.
Unknown/repeated crashes or semantic failure stop the sequence, retaining all evidence.
No push/publication/workflow or SteamVR configuration. Exit0 only on the whole sequence.
The operator flag records reviewed resumption; it is not permission for agents to
ignore the current prohibition. Code-generation/offline tests do not imply runtime pass.


The full command requires the read-only clock helper (default out/vr/v2q/inspect/gmcl_nlvrqinspect_win64.dll, or --inspect-dll). It always passes that observer to combined CPU/network acceptance; missing helper refuses before creating evidence rather than silently omitting that criterion. Build via tools/vr_measure_build.ps1.


The gated matrix also includes allmotion, wall-time temporal movement and armed plus/minus45-degree noclip flight with their own mandatory reducers; it does not rely on the shortened combined motion subset for those witnesses. It still must not execute before Claude confirms the fixes repair.

Round5 geometry allocates130seconds per hand to include Annabelle. Shared driver now always acquires both locks, even in simulation and flat controls.
