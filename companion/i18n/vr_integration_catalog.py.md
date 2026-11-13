# vr_integration_catalog.py

Writes task Q's three calibration/restart and server-ragdoll help messages to the six
companion catalogs using ASCII-escaped input and explicit UTF-8. Run `python
companion/i18n/vr_integration_catalog.py` after changing these page messages. Inputs: the
page, existing POT/PO catalogs and the embedded translations. Outputs/side effects: updated
catalogs, preserving unrelated translations. Checks complete catalogs and rejects question-mark
runs/replacement characters in its translations. Exit 0 on success, nonzero on a check/error.
