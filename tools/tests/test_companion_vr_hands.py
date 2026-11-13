"""Run H hands's companion tests in the repository gate."""
from vr_feature_suite import feature_suite


def load_tests(loader, tests, pattern):
    return feature_suite(loader, "vr_hands_test", "H hands")
