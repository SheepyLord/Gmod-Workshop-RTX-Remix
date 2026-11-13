# Natural controller transforms in test observers

Used by `vr_fixture_frames.py`: `Encode` maps a desired palm/aim pose to the raw
Index basis, and `Decode` reverses it. Observers that alter raw frame poses can
use these before/after their edits. `Components` keeps live component receipts,
substituting the supplied recorded reference only for an invalid controller.
It preserves the raw live receipts separately. This is private test support with
no hooks, convars, file writes, SDK calls or process exit status.

Aim preserves the desired palm while iteratively aiming the real SteamVR tip origin at a tracking-space target. Both-hand geometric tests require the resulting tip ray to hit, keeping the tip/palm parallax explicit.
