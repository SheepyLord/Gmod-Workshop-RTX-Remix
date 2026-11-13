"""Load companion feature suites for the tools-only gate and print their own counts."""
import importlib
from pathlib import Path
import sys
import unittest

COMPANION = Path(__file__).resolve().parents[2] / "companion/tests"


def feature_suite(loader, module_name, label, optional=False):
    sys.path.insert(0, str(COMPANION))
    if optional and not (COMPANION / (module_name + ".py")).is_file():
        @unittest.skip(f"{label}: companion suite has not landed on this branch ({module_name}.py)")
        class PendingSuite(unittest.TestCase):
            def test_pending_feature_suite(self):
                pass
        suite = loader.loadTestsFromTestCase(PendingSuite)
        print(f"VR {label}: 0 feature tests; 1 explicit pending-suite skip", flush=True)
        return suite
    # Import errors inside a present suite are real failures, never availability skips.
    suite = loader.loadTestsFromModule(importlib.import_module(module_name))
    if suite.countTestCases() == 0:
        raise AssertionError(f"VR {label}: present suite has no tests")
    print(f"VR {label}: {suite.countTestCases()} tests", flush=True)
    return suite
