# authored_mod_probe.lua

The client side of [authored_mod_session.py](authored_mod_session.py.md), sent through the console by the driver
(never installed in the game). It defines the global table `NLAM` and prints `NLAM_INSTALLED {}`.

| Function | Prints |
|---|---|
| `NLAM.Hashes(a, b)` | `NLAM_HASHES {json}`: for the crowbar's view model and the props with entity indexes `a` and `b`, each material, its `$basetexture` and its Remix texture hash from the RTX fixes' `RemixMaterial.GetTextureHash` (the hash text, `0x...`); `{"error": ...}` if reading failed |
| `NLAM.CloseUI()` | `NLAM_CLOSED {"closed": n}`: removes the package's windows whose title names RTX or Remix (the first-start guide among them) and releases the mouse, before a screenshot |

The view model comes from `LocalPlayer():GetViewModel()`, then `Entity(1)`, then the first `viewmodel` or
`predicted_viewmodel` entity: in one PoC run `LocalPlayer()` returned an object without `GetViewModel` in the chunk
the console ran.

No side effects beyond the removed windows. Exit codes do not apply (Lua run in the game).
