# The RTX Remix menu (Alt+X) with frame generation on: report (2026-11-15)

The user's report of 2026-11-15: "Fix a critical bug, the remix Alt+X menu can not be opened in field game and other
users." and "In active game session, it is already reproduced. Alt+X will disable control to the game, but the remix
menu is not drawn." (their main menu's diagnostics: package 0.0.0-dev.20261115092107+a9e94d7a). Done by Claude on the
branch `altx-menu`: runtime patch 0096 (fork branch `claude/dlfg-menu`); no loader (`winmm.dll`) change.

## Cause

Runtime patch 0094 (the crosshair under DLSS frame generation, [ADR 0223](../decisions/0223-frame-generation-gets-the-frame-before-its-ui.md))
blits the frame before its UI into the frame generation presenter's HUD-less image beside each back buffer. It did so
right after the back buffer's own blit, in `D3D9SwapChainEx::PresentImage`. The DXVK HUD and the Remix menu, drawn next,
bind no render target of their own (`ImGui_ImplDxvk::RenderDrawData` draws into the one bound): they went into the
HUD-less image, which DLSS-G only reads. So with frame generation on, Alt+X opened the menu as far as the runtime knew
(it took the game's input) and nothing appeared on screen. Frame generation off, the menu was fine. It shipped in the
package of 2026-11-15 02:58Z and every one after.

## Fix

Patch 0096 blits the HUD-less copy first and the back buffer last, so the HUD and the menu are drawn into the
presented image again. The HUD-less copy stays without UI, so DLSS-G treats the menu as UI and keeps it in place in the
generated frames, as it does the crosshair.

## Checked

- **Reproduced in the PoC** (RTX 5090, 1280 x 720, DLSS frame generation 3x on; `out\qa-poc\altx\01-menu`, the
  published package): the menu opened through `rtx.showUI` (what Alt+X sets) was absent with frame generation on and
  drawn with it off.
- **Fixed** (`out\qa-poc\altx\02-menu-fixed`, the branch's package): the User Graphics Settings window and the
  Developer Menu are drawn with frame generation on ("Status: active - DLSS Frame Generation, 3x") and off; the DXVK
  frame counter shows; the HUD-less input is still used (`[DLFG] frame generation gets each frame before its UI`).
- `test_dlfg_hudless.py` checks the blits' order in patch 0096; the gate passes.

## What is left

- Not checked in the field install; the field takes the Workshop item's update at its next start.
