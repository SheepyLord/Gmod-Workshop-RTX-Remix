/* SPDX-License-Identifier: MIT */
/* Compile the shared header as C as well as C++; guard the Windows x64 wire layout. */
#include "include/rtxvr_api.h"
#include <stddef.h>

_Static_assert(sizeof(rtxvr_Matrix34) == 48, "matrix ABI");
_Static_assert(sizeof(rtxvr_Eye) == 64, "eye ABI");
_Static_assert(sizeof(rtxvr_StartInfo) == 168, "start ABI");
_Static_assert(offsetof(rtxvr_StartInfo, getGenericInterface) == 8, "interface pointer ABI");
_Static_assert(offsetof(rtxvr_StartInfo, eyes) == 32, "eyes ABI");
_Static_assert(sizeof(rtxvr_FramePose) == 112, "pose ABI");
_Static_assert(offsetof(rtxvr_FramePose, sequence) == 8, "sequence ABI");
_Static_assert(sizeof(rtxvr_Status) == 496, "status ABI");
_Static_assert(offsetof(rtxvr_Status, gpuMsWork) == 488, "GPU work ABI");
_Static_assert(offsetof(rtxvr_Status, stereoActive) == 492, "stereo flag ABI");
_Static_assert(RTXVR_QUALITY_TRUE_STEREO == 0x4u, "true stereo flag ABI");
_Static_assert(offsetof(rtxvr_Status, qualityRenderScale) == 456, "quality status follows the V3 fields");
_Static_assert(offsetof(rtxvr_Status, qualityChanges) == 480, "quality counter alignment ABI");
_Static_assert(sizeof(rtxvr_Quality) == 24, "quality ABI");
_Static_assert(offsetof(rtxvr_Quality, flags) == 20, "quality flags ABI");
_Static_assert(offsetof(rtxvr_Status, framesRendered) == 296, "counter alignment ABI");
_Static_assert(offsetof(rtxvr_Status, overlayUpdates) == 376, "overlay counter ABI");

int nlvr_c_api_layout(void) { return RTXVR_API_VERSION; }
