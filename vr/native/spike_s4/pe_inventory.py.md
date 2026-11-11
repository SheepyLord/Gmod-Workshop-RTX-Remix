# pe_inventory.py

Read-only PE inventory used for S4. Example:
`python vr/native/spike_s4/pe_inventory.py H:/SteamLibrary/steamapps/common/GarrysMod_PoC/bin/win64/materialsystem.dll --out out/vr/d/s4/static.json`.
Reads and hashes the supplied PE64 image, finds the named material/context RTTI type descriptors,
complete object locators and primary vtables, and records selected slot RVAs and instruction
prefixes. Uses only Python's standard library and never loads or executes the image. Writes one
JSON evidence file at `--out` (choose a path under repository `out/`) and prints SHA-256.
Exit 0 means inventory completed; a malformed/missing image or output error raises an exception.
This inventory establishes byte locations; the Ghidra evidence and live probe establish their
meaning and behavior. It does not turn inferred method names into source symbols.

