"""Generate inert, concrete OpenVR test interfaces from the pinned declarations."""
from pathlib import Path
import re
import sys

source = Path(sys.argv[1]).read_text(encoding="utf-8")
source = re.sub(r"/\*.*?\*/|//[^\n]*", "", source, flags=re.S)
out = ["// Generated for offline tests only; declarations from Valve's BSD-3-Clause SDK.",
       "#pragma once", "#include <openvr.h>", "namespace vr {"]
for name in ("IVRSystem", "IVRCompositor", "IVRInput", "IVROverlay", "IVRRenderModels"):
    start = re.search(r"\bclass\s+" + name + r"\s*\{", source).end()
    depth, end = 1, start
    while depth:
        if source[end] == "{":
            depth += 1
        elif source[end] == "}":
            depth -= 1
        end += 1
    body = source[start:end - 1]
    out.append(f"struct Stub{name} : {name} {{")
    functions = re.findall(r"virtual\s+([^;]+?)\s*=\s*0\s*;", body, flags=re.S)
    if not functions:
        raise ValueError("no methods found: " + name)
    for method in functions:
        method = " ".join(method.split())
        returns_void = bool(re.match(r"void\s+\w+\s*\(", method))
        out.append(f"  {method} override {{ {'return;' if returns_void else 'return {};'} }}")
    out.append("};")
out.append("}")
Path(sys.argv[2]).write_text("\n".join(out) + "\n", encoding="utf-8")
