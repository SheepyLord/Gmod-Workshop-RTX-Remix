"""Expose VR V6's and V7's companion-owned tests to the repository's tools-only test gate."""
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "companion/tests"))
from vr_perf_test import VRPerfTests, VRQualityAnalysisTests  # noqa: E402, F401
from vr_stereo_test import VRStereoAnalysisTests  # noqa: E402, F401
