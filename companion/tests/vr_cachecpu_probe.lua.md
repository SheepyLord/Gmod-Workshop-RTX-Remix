# vr_cachecpu_probe.lua

Private stationary cache control embedded by vr_cachecpu_session.py. Two six-second blocks per
mode, balanced in order: uncached, cached, cached, uncached. Uncached changes HandRevision at each
Refresh; cached uses production behavior. Whole game-thread CPU/cycle intervals are measured between
adjacent PostRender frames strictly inside the same block, excluding 250 ms at each edge. This avoids
misattributing CreateMove work across alternating frame boundaries. Records actual resolver passes,
call counts and frame denominators; requires the read-only clock helper. Normal core cleanup restores
the wrapper. No files, SDK calls or settings writes; private console commands select Hands/noclip and
request beginning/end server health. Missing data fails the parent receipt.
