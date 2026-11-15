# test_secret_handoff.py

Checks runtime patch `0098-The-About-tab-takes-the-secret-replacements-whole-no.patch`
([runtime/README.md](../../runtime/README.md)): the asset replacer hands its secret replacements to the About tab
whole, so the tab never walks a map that DXVK's command thread is clearing and refilling (the field's start-up crash
of 2026-11-15, a null read in `ImGuiAbout::Secrets::update`).

```powershell
python -m unittest tools.tests.test_secret_handoff
```

| Test | Checks |
|---|---|
| the handoff's unit test from the patch | writes `rtx_secret_handoff.h` and `tests/rtx/unit/test_secret_handoff.cpp` as the committed patch creates them into `out\tmp`, compiles them with MSVC (`/std:c++17 /W4 /WX`, as the runtime's own unit test builds) and runs them: `PASS secret handoff: N checks` (nothing before a publish; a published map taken once; a load without secret replacements is not pending; the newest publish wins; a copy outlives the next publish; a command thread publishing while a present thread takes never yields a torn or older map). Skipped without the VS 2022 Build Tools |
| the handoff publishes and copies under one lock | `publish` and `take` hold the same mutex; the flag is stored with release and read with acquire; `take` returns a copy, not a reference; the header includes the standard library only |
| the replacer builds the map and publishes it whole | `updateSecretReplacements` fills a map of its own, checks the selected variants against it, then publishes it; the shared map is no longer cleared in place nor the bare flag set |
| the About tab's accessors go through the handoff | `hasNewSecretReplacementInfo` and `getSecretReplacementInfo` (now by value) use the handoff, the old member and flag are gone, `dxvk_imgui_about.cpp` is unchanged (its `const auto&` binds the copy); meson lists the header and the unit test |

Writes only a scratch folder under `out\tmp`, removed afterwards. Exit 0 when every test passes.
