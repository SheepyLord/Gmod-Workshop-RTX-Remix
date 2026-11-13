"""Run C's controller-frame companion suite in the repository gate."""
from vr_feature_suite import feature_suite


def load_tests(loader, tests, pattern):
    return feature_suite(loader, "vr_frames_test", "C controller frames")
