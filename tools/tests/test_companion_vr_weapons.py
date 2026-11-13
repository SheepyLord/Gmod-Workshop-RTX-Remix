"""Run W weapons's companion tests in the repository gate."""
from vr_feature_suite import feature_suite


def load_tests(loader, tests, pattern):
    return feature_suite(loader, "vr_weapons_test", "W weapons", optional=True)
