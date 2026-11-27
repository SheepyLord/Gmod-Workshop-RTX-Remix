# calibrate_enhanced_night.py

Measures the two Milky Way assets for the Enhanced renderer's `kNumosNightImageScale`. Run with Python, Pillow and NumPy.

Patch 0117 multiplies this physical conversion by 64 for the night image and meteors. The renderer's
separate `kNumosNightLookGain` sets that look. [PoC bracket and final-build checks](../../docs/handover/sky-enhanced-NR-report.md#nr2)

```powershell
python tools/sky/calibrate_enhanced_night.py <asset-folder>/galaxy.dds <numos>/assets/nightsky/milkyway.bin
```

The first input is the unpacked NightSky HD galaxy texture shipped by the runtime package. The second is the pinned library's RGB9E5 Gaia background. The script reads mip zero and integrates linear BT.709 luminance over the celestial sphere. It applies the editor's default master brightness to the image band and removes the library's storage scale from Gaia. JSON on standard output gives both means and their ratio. The script reads its inputs without modifying them. An invalid file or a zero-light image yields a nonzero exit code.
