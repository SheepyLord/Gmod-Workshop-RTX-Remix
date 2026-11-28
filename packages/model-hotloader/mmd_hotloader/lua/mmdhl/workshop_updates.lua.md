# workshop_updates.lua

Loaded by `workshop.lua` in each realm. During package discovery it identifies each physical
add-on folder or directly mounted Workshop item. The loader journal identifies which Workshop
item or local package owns a deployed folder in the current and previous generations. At
reconciliation it matches a character's item
key or unique source path to the pack's install records. After a verified install it records the
successor and the client switches its library choices. The client checks old carrier sidecars
across frames and records a witness for saved games before releasing an unused asset for deletion.

Inputs are the mounted manifests, install records, local import provenance and carrier files.
The caller persists changes in `mmd_hotloader/workshop/state.json`. An ambiguous match produces
no replacement. The module has no command-line entry point.
