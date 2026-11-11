"""Expose VR-E's companion-owned harness to the repository's tools-only test gate."""
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "companion/tests"))
from test_vr import VRCatalogTests, VRTests  # noqa: E402, F401
