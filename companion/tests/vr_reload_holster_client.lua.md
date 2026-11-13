# Holster regression fixture

Private client probe selected by `vr_reload_poc.py --holster`. Two fifteen-second
phases fire/eject an SMG and empty a pistol, select Hands for 4.5 seconds, return,
then attempt physical insertion and firing. Uses normal production control/network
paths; only fixture weapon selection/inventory initialization is scripted. Saves
and restores its settings and flat command hook. Records counters/captures through
the usual production session driver. Outputs NLVR_K records under repository out.
No standalone entry point; errors fail the parent session. Not packaged.
