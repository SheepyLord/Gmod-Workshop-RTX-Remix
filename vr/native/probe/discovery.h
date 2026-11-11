#pragma once
#include "probe_data.h"
namespace nl::vrprobe {
// No OpenVR headers, DLL loading, registry access or writes: also usable by nlvr.Probe().
Json discover_steamvr();
}
