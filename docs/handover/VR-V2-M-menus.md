# VR-V2-M: menus, panels and the page

Read [VR-V2V3-plan.md](VR-V2V3-plan.md) first, all of it, then task F's report
`docs/handover/VR-V2-F-report.md` ("how to write a module"): you build on F's framework (overlays, input claims,
rays). [VR-plan.md](VR-plan.md)'s "Weapons and tools" (its menu items), "HUD and panels" and "The add-on and the VR
page" describe what the player should get.

Your branch is `v2m`, worktree `H:\BACKUP_20260815\Modding\!NVIDIA-RTX-Remix\out\worktrees\v2m`.

## What to build (`modules/cl_ui.lua`, and `cl_ui_*.lua`)

1. **Panels.** A panel is a VGUI panel painted (`PaintManual`) into its own render target and shown as an overlay a
   comfortable distance in front of the player where it was opened (world-fixed in tracking space), at a fixed pixel
   size independent of the desktop window (which may be 3840 x 2160 with a GUI scaler). Close on the same button or
   by a close mark on the panel.
2. **The laser.** From the main hand while a panel is open (an overlay beam from the hand and a dot where it hits);
   the trigger clicks (it is claimed while the beam is on a panel), the main stick scrolls, a hold drags. Panels get
   real VGUI input (cursor moves, presses, releases, wheel) at the hit point; the desktop cursor is put back after.
3. **The wrist menu** on the off hand's B: a small overlay panel at the off hand with Spawn menu, Context menu,
   Flat screen, Settings (comfort options of the plan's interface 10, the height calibration of task L, Recenter,
   Exit VR).
4. **The spawn menu** (the sandbox's `g_SpawnMenu`, with its tabs and search) and **the context menu**
   (`g_ContextMenu`, its icons and properties) as panels; the context menu's world clicks (properties on an entity)
   aim with the main hand's ray instead of the screen.
5. **The flat-screen panel**: the game window's own picture after its 2D (task N's `nlvr.OverlayWindow`, task R's
   runtime source), shown with `NO_MIRROR` so it is the 2D alone; the laser drives the real cursor over the window, so
   the escape menu, the console and other add-ons' windows can be used. When the runtime lacks the source, the panel
   says so.
6. **Text**: a text field that takes focus in a VR panel opens SteamVR's keyboard (task N), and the typed text goes
   into the field.
7. **The VR page** (companion): the options of the plan's interface 10 with their texts (comfort, dominant hand, HUD,
   the Alyx mechanics' switches), a button for SteamVR's binding UI, the height calibration button; translated into the
   tab's six languages (a Python script writing UTF-8, checked for `?` runs; see the plan's rules).
8. **Debug values** for the probe: open panels, laser hit (panel, u, v), the last click, keyboard state.

## Files you may change

`vr/addon/lua/nlvr/modules/cl_ui*.lua` and their `.md`,
`companion/nativeloader/lua/autorun/client/nativeloader_vr.lua` (the page's look and texts; F created the console
variables, leave them), `companion/i18n/**` (the page's texts only), your tests in `companion/tests/` (new files with
a `vr_ui` prefix), decision records **0167** (VR panels: painted VGUI and the laser) and **0168** (the flat-screen
panel) with their lines in `docs/decisions/README.md`, and your report. If F's core needs a change, do not make it:
describe it in your report and work around it in your module meanwhile.

## Proof

- LuaJIT tests: hit to panel coordinates, the claims, the click and drag state machine, the wrist menu's items.
- Simulated PoC sessions (task N's `--simulate`, once on `vr2`; until then the Index with both locks) with scripted
  hands and buttons: open the wrist menu, open the spawn menu, laser-click a prop's icon (a new entity appears), open
  the context menu and use a property on an entity by the hand's ray, open the flat-screen panel with the escape menu
  and click "Resume Game", type into a text field through a scripted keyboard event; overlay captures of each panel.
- One session on the Index: the same, with the compositor's counters.

## Report

`docs/handover/VR-V2-M-report.md`: what you built, pictures (paths) of each panel, the tests and evidence, what is
open, your text for the shared documents. `tools\test.ps1 -Config Release` passing in your worktree.
