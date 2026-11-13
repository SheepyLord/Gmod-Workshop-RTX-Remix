# test_vr_measure.py

Offline evidence regressions for the Q measurement/parity tools. Checks explicit sample
windows and independent submitted-pair rate, reprojection, command work, elapsed GPU span
and render-thread CPU; uncovered profiles and missing samples fail. Generates a ten-launch
flat batch, verifies exact expected off stub inventories and rejects missing launches/extra
VR timers. Engine timer dumps preserve exact names/source lines and reject unknown dump commands
or live VR timers. An unexplained non-nlvr callback also fails whole-package parity. Server CPU receipts
retain separate tick/time denominators; missing realm/callback/send/off data fails acceptance.
Client CPU uses the distinct game-frame count even when raw PostRender calls differ.
Sampled render CPU stays distinct from cumulative averages. A preparation-only retry retains
the failed folder, refuses any attempted game and cannot bypass ten complete launched games.
PNGs are generated in scratch under out/tmp; no binary fixtures, GPU, game, SDK,
network or settings. Paired-image case skips only if Pillow is unavailable. Runs through the
Release gate; exit 0 on pass, nonzero on failure.


Armed-window regression rejects a wrong class, missing model or stationary draw count.


Flat runtime retry tests reproduce the old private positional CLI failure, require a reproducible evidence argument and reject unknown, repeated or outside-root retry substitution. No game runs in these tests.

Round5: after the reviewed queued-draw repair, any fixes stack marker (including an unreviewed build) stops; only the NVIDIA startup signature permits one restored fresh-folder retry. Old receipt flags cannot override current policy. The normal field-quit helper is driver-only; exit5 after a quit crash is fatal and its evidence is retained.
