# vr_ui_poc.py

Usage: `py -3 companion/tests/vr_ui_poc.py --package out/dist/PACKAGE.gma --evidence out/vr/v2m/RUN`.
After task N is merged, add `--simulate`; `--window` passes through N's option. Uses the production
VR driver, both shared locks on Index (only PoC for simulation), process inventory, snapshots,
protected-file hashes, live setting restoration and verified rollback. It appends vr_ui_poc.lua to
the acknowledged probe and creates one fixed server prop through normal console setup. No field
files, SteamVR settings or binaries are changed. The wrapper adapts only its main-hand pose/actions
at the native-to-Lua test boundary to actual widget geometry; it never replaces panel hit tests or
VGUI dispatch. The native timeline owns head/off hand and scripts keyboard_done at 18 seconds.
Outputs: standard receipts/images, ui-records.json, ui-acceptance.json and helper hashes. An overlay validator
accepts bounded RGBA panel sizes and keeps the original strict glyph check for the actual wrist, avoiding
V1's one-megapixel wrist limit rejecting a valid spawn/flat canvas. Feature assertions enforce spawn/property/
text/drag/scroll/close outcomes and image paths. Missing runtime sources are explicitly open, never accepted
as Resume. Full acceptance is separate from available checks passing. Exit 0 requires the standard driver
and available feature checks; failures return 1, screenshot preflight keeps the driver's 2.

`--gui-scaler` accepts a cached GMA or a verified extracted folder under out, staged into a fresh PoC-only
add-on before launch. No download occurs. Folder input requires a sibling .provenance.json with matching
file hashes and per-file CRC validation; native files are refused. The normal snapshotted addons-root rollback
removes it. This handles the installed GUI Scaler archive's stale whole CRC through stock gmad extraction,
without weakening the repository extractor or modifying the Steam cache. `--flat-probe --seconds 25` selects
the short cursor/HTML diagnostic. Lock polling varies between 1.5 and 3 seconds, waits up to two hours, and
inherits owner-token release. Source snapshots retain the exact helper/fixture bytes used, including after a
long lock wait. A no-site-packages preflight test proves refusal before any evidence/lock/game work.
`--settings-probe --seconds 15` selects a short settings-layout capture and restores all variables afterward.
Diagnostic fixtures record actual cursor state and desktop focus. Source hashes are taken from the exact
loaded Python bytes and generated Lua fixture, not mutable files reread after a long run. Native keyboard
or MENU input failures remain failed UI assertions even when the standard renderer/rollback receipt passes.

Q checker accepts an empty Lua changes table encoded as [] as no changes (a failed drag), preserving a failed receipt instead of raising AttributeError.
# Follow-up

`--window-probe --seconds 15` selects the native posted-input Resume diagnostic. It uses the normal
snapshot/PoC lock/rollback driver and writes an acceptance receipt requiring visibility immediately
before the actual posted button press. It does not treat automatic HideGameUI as a successful click.
`--window-press-at 20 --seconds 30` allows a foreground control. `--followup --seconds 50` adds the
real model-search field and console through the US fallback laser keys. Only simulation injects a
ShowKeyboard failure after recording its native result; Index uses the actual SteamVR return.
Search acceptance requires CurrentSearch=barrel with positive stock results. Console acceptance
requires the actual bare echo output in the game's log, not just successful character posting.
Preliminary sessions recorded an in-memory keyboard-size contract fixture before S's merge.
The final fixture now asserts S's real central reservations and supplies no size fallback.
Follow-up UI preparation runs on a bounded joined worker while the normal game command holds M's
PoC lock: two fixed showconsole/hideconsole operations through the existing launcher's console path,
selected by tokenised fixture markers. Lock owner, game process path and unique Valve001 target are
rechecked before sending. No other command is accepted and the echo command is never sent there.
