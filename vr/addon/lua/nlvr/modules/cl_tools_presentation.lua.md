# cl_tools_presentation.lua

Included only by the tools module at VR Start. New(overlay) caches visible state and the
last submitted world transform/width. Show changes and width changes apply immediately.
Place coalesces movement within 1 mm and a wrapped Euler delta norm within 0.1 degree.
Compare against the last submission, not the last sample, so accumulated motion still
updates and positional lag stays bounded by 1 mm. Cached vectors/angles are reused.
Tests use continuously moving hand poses, accumulated translation, angle wrap and width changes.
Overlay lifetime remains the caller's. No input, network, files or settings; no exit code.
