# Reload client probe

Appended by vr_reload_poc.py after the shared production probe. Records actual
model-local port transforms to tracking poses for a subsequent scripted timeline;
requests server phase setup with acknowledgement/retry and eye/overlay captures
of held ammo, the well and after fire. Selects physical/button setting and disables
foregrip only during the test; restores the saved strings after Exit. Server
fixture is registered in both realms so a SWEP can witness ordinary B reload.
Probe hooks/commands end after Exit. No production code or native poses are replaced.
Evidence goes to console under NLVR_K; failures propagate to driver acceptance.

The shared flat-baseline probe's own CreateMove button clearer is suspended only
during this feature run, then restored after Exit. Otherwise it would erase W/K's
actual engine command bits. Native OverlayInfo/OverlayVisible receipts and counter
paint counts are sampled every 250 ms, including the real compositor transform.

The fixture snapshots eight weapon/tracking option strings. Five seconds after
injection (after the shared flat baseline and before its Start), it selects right
hand, 40 units/metre, no seated/height offset, gun pitch zero, foregrip off and ammo
counter on, with physical reload matching the run mode. After Exit it restores all
strings and verifies them after command processing. No per-frame option writes.

Button mode records the real Input.Tapped observations around the B window (down/pressed/released/held/tap/owner/frame/tick). A private read-only wrapper returns the original result and is restored at Exit; it distinguishes an unobserved/overlong scripted press from a command-delivery failure.

A private priority-71 observer, owned by the existing reload registry entry, records command number/tick and the reload bit after K. It changes no command and is removed by normal registry teardown. Zero-number/zero-tick prediction calls are distinguished from networked commands ([CUserCmd](https://wiki.facepunch.com/gmod/CUserCmd)).

Button-command observations include the native remaining player attack lock.

Command traces include client CurTime alongside the absolute native client attack deadline.

B readiness observations cover phase2.6..8 s, including the RPG's later client readiness, to measure bounded delivery directly.
