"""Run W's combined weapon/physics fixture with controller poses for C's real hand frames."""
import math
import sys
import vr_weapons_poc as weapons
from vr_frames_poc import angle, controller_offsets, multiply, mv


def rotation(angles):
    p, y, r = map(math.radians, angles)
    cp, sp, cy, sy, cr, sr = math.cos(p), math.sin(p), math.cos(y), math.sin(y), math.cos(r), math.sin(r)
    return [[cp*cy, cy*sp*sr-sy*cr, cy*sp*cr+sy*sr],
            [cp*sy, sy*sp*sr+cy*cr, sy*sp*cr-cy*sr], [-sp, cp*sr, cp*cr]]


original_timeline = weapons.timeline


def natural_timeline(seconds, phases):
    data = original_timeline(seconds, phases)
    offsets = controller_offsets()
    for step in data["steps"]:
        for side in ("left", "right"):
            natural, palm = offsets[side]
            pose = step[side]
            raw = multiply(rotation(pose["ang"]), natural)
            delta = mv(raw, palm)
            pose["pos"] = [x-d for x, d in zip(pose["pos"], delta)]
            pose["ang"] = angle(raw)
    return data


if __name__ == "__main__":
    if len(sys.argv) == 3 and sys.argv[1] == "--poc-arguments":
        import json
        from pathlib import Path
        raise SystemExit(weapons.poc.main(json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))))
    # W now adapts canonical poses itself, including --left-hand.
    original_lock = weapons.driver.ExclusiveLock
    class TaskLock(original_lock):
        def __init__(self, path, task, timeout=7200):
            super().__init__(path, "VR-V4-C combined weapons", timeout)
    weapons.driver.ExclusiveLock = TaskLock
    raise SystemExit(weapons.main())
