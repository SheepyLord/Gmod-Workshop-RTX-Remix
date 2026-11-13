# cl_tools_wheel.lua

Reviewed selection policy supersedes repeated SelectWeapon: one non-preview/networked
command, then up to one second for acknowledgement. Refusal/expiry shows a two-second
passive notice in the existing wheel source, without repeated switch/Holster attempts.
DrawWeaponSelection overrides are used where present, excluding the unchanged function
inherited from weapon_base. The inherited base WepSelectIcon texture is also ignored;
Hands therefore keeps its Hands glyph. A failed custom draw falls back.
Custom drawings are clipped to the 120 x 60 icon area, including error cleanup, so a
SWEP's enlarged icon/progress bar cannot cover a neighbouring weapon card or label.
Inventory membership polls at most every 0.25 s while open (invalid entries immediately),
and only membership changes trigger descriptions/sorting. Closed debug entries are cached;
unchanged world transforms/visibility skip native calls via cl_tools_presentation.

Trigger ownership is retained by cl_tools_controls after close/cancel and across a
handedness change, until that physical trigger is released. Command masking alone
is insufficient because P also uses Input claims to decide hand use.

A pending K reload can own B before T's frame. The wheel waits for that ownership to
clear before opening, preserving the pending reload command. Losing B ownership while
open cancels selection and requires physical release before reopening. A remains K/W's.

Selection skips prediction command zero and issues one ordinary CUserCmd selection, then
waits for acknowledgement until ownership/validity fails, a new wheel opens, or one second
expires. Debug distinguishes requested, pending, confirmed and refused selection.

Owned B-hold wheel helper for cl_tools. New(ctx,controls) returns Frame/Move/Close/Debug/Stop.
Holding B 0.3 seconds freezes a head-facing plane at the hand. Main-hand movement in the
plane highlights after 3 cm. Hands first, inventory by HUD slot/position/class. Twelve
entries per page; beyond 24 cm up/down at most 10 cm sideways advances/wraps one page.
Return inside 18 cm to rearm, keeping large inventories readable. Release queues
CUserCmd:SelectWeapon; neutral/lost tracking/mirroring/death/Exit cancels. No direct select.

The 1035 x 1037 canvas is 42 cm wide, repainted on highlight/page/inventory change. SWEP
texture icons and HalfLife2 selection-font glyphs, slot/name fallbacks. Move consumes
attack/reload while open and preserves existing claims. Full entries/highlight/selection
are plain debug. No files/settings/network or process exit code. Parent/framework own
the canvas; verify via vr_tools_test.py and PoC captures. Cards are 168 x 120 pixels and
do not overlap for any page size 1..12; a larger central label shows the current highlight.
Text elision preserves UTF-8 boundaries, including malformed-input termination. Debug also
records the number of paints.
