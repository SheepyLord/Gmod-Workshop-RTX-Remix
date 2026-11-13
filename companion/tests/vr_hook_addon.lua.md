# Competing add-on lifecycle fixture

Registers actual high-priority CalcView, monitor Think and low-priority input
callbacks. They stay installed through Exit and a second Start, and are removed
only after the caller has checked both Exits. The competing view is deliberately
wrong while VR is active: core isolation must prevent it from running; its flat
calls prove the callback is real. Think/input must be called during VR and flat.

ObserveView consumes the actual returned view, not module-health metadata. Callers
can require real hand draws, nonzero production movement and a completed menu
action. Check fails if hooks were added/removed immediately, callbacks were not
dispatched, view isolation failed or requested features lack proof. No settings,
timers, world entities, files, native calls or exit statuses are changed.
