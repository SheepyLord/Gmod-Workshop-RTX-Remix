# Reload server probe

Injected only by vr_reload_poc.py through the ordinary admin console path. Gives
and selects each test weapon, sets initial clip/reserves, records stock muzzle
attachments, native reload/pump/must-reload flags and actual clip/reserve/fire
deadlines at 10 Hz. A test-only SWEP counts its real Reload calls. God mode keeps
rocket testing from killing the local fixture. No engine code is emulated or
production reload function replaced. Test state ends with the transactional game.
Probe hook/commands remove at Exit. Console NLVR_K records become reload.json;
no disk file/Steam setting/user.conf is changed by this Lua. Lua errors fail the run.

The button witness records StartCommand IN_RELOAD ticks, observes the toolgun's
original Reload callback with a forwarding wrapper, and observes OnPhysgunReload
without returning a hook value. It does not substitute either action. No-ammo
tools retain Clip1=-1 and receive no invalid ammo grant.
Phase and observed-hold duration use the monotonic wall clock, matching N's
timeline. Engine CurTime and its primary deadline remain separately recorded;
capture stalls must not make the two clocks interchangeable.
The client supplies its native phase time and same-process monotonic clock so
initial setup/ack delay does not move the first gun's analysis windows. Recording
ends are checked only within the requested phase; Exit's previous-weapon restore
is excluded from the no-auto-switch interval. Actual attack-bit attempts during
the empty hold are recorded separately from native ammo consumption.

The physgun observer uses the actual [OnPhysgunReload](https://wiki.facepunch.com/gmod/GM:OnPhysgunReload) hook and returns nothing, preserving default unfreeze behavior.

Holster mode adds a fixture-only weapon-selection command and watches the holstered weapon's actual clip/reserve/holster timestamp while Hands is active. The pistol begins with one round. A timer round-trip at initial setup records GMod's relative FIELD_TIME API; native Holster later overwrites that active-phase calibration. No clip or ejection state is edited after setup, and no synthetic FinishReload is invoked.

Samples include the native remaining player attack lock, using GetInternalVariable.

Deploy-lock mode uses the native relative m_flNextAttack save field and records its positive readback plus remaining lock on each observed reload command.
