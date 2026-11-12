// SPDX-License-Identifier: GPL-2.0-only
#pragma once
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <excpt.h>

// What the studio render hooks may read while a model is drawn.
//
// With queued rendering (mat_queue_mode 2, GMod's default), studiorender draws each model on the material
// system's render thread from a copy of the main thread's DrawModelInfo_t. Its IClientRenderable* is only
// that copy's pointer: when the main thread removes the entity (a prop breaks, a gib fades out, a script
// removes it) while its draw is still queued, the pointer refers to freed memory. prop_fixes.cpp called
// GetModel() through that pointer's vtable; the stale slot ran whatever it pointed at, which overwrote the
// return address, and the game ended at instruction pointer 0 with no handler able to run (three crashes on
// 2026-11-11 and 2026-11-12, return address gmcl_RTXFixesBinary_win64.dll+0x41605b). So the hooks take what
// they need from studiorender's own state for the draw and never read the renderable.
namespace StudioDrawPolicy {

// CStudioRender, the hooks' `this`, in GMod's x64 studiorender.dll: m_pStudioHdr, the header of the model being
// drawn, which DrawModel, DrawModelStaticProp and DrawModelArray set from the draw's own info before any mesh
// is drawn. HardwareSkinningHooks.cpp reads the same field (with m_PoseToWorld at +0xE8).
constexpr std::size_t StudioRenderStudioHdrOffset = 0x108;
// studiohdr_t: id ("IDST") at 0, numbones at 0x9C.
constexpr std::size_t StudioHdrIdOffset = 0;
constexpr std::size_t StudioHdrNumBonesOffset = 0x9C;
constexpr std::int32_t StudioHeaderId = ('T' << 24) + ('S' << 16) + ('D' << 8) + 'I';
// The bone counts the renderable lookup accepted.
constexpr int MaxBones = 4096;

// LIGHTING_HARDWARE in StudioModelLighting_t.
constexpr int LightingHardware = 0;

struct Lighting {
    int lighting;     // what R_StudioSetupSkinAndLighting hands back to its caller
    int meshLighting; // what the R_StudioDrawDynamicMesh hook draws this material's meshes with
};

// prop_fixes' rule, unchanged: r_forcehwlight puts every model on hardware lighting, and so does a model with
// at most one bone; a skinned model, or one whose bone count is unknown (-1), gets it when r_forcehwskin is
// on and keeps the engine's choice otherwise.
constexpr Lighting ChooseLighting(
    int engineLighting, int bones, bool forceHardwareLighting, bool forceHardwareSkinning)
{
    if (forceHardwareLighting || (bones >= 0 && bones <= 1) || forceHardwareSkinning) {
        return {LightingHardware, LightingHardware};
    }
    return {engineLighting, engineLighting};
}

// The bone count of the model studiorender is drawing, from its own state, or -1 when it is unknown: no
// renderable (the renderable lookup found no model then either; the pointer is only compared with null), no
// header, or one that is not a studio header. The header is the one studiorender itself draws from, valid
// for as long as the draw runs. A read that faults gives -1 (a changed layout must not end the game).
inline int BoneCount(const void* studioRender, const void* clientRenderable)
{
    if (!clientRenderable || reinterpret_cast<std::uintptr_t>(studioRender) < 0x10000) {
        return -1;
    }
    __try {
        const unsigned char* header = nullptr;
        std::memcpy(&header, static_cast<const unsigned char*>(studioRender) + StudioRenderStudioHdrOffset,
            sizeof(header));
        if (reinterpret_cast<std::uintptr_t>(header) < 0x10000) {
            return -1;
        }
        std::int32_t id = 0;
        std::int32_t bones = 0;
        std::memcpy(&id, header + StudioHdrIdOffset, sizeof(id));
        std::memcpy(&bones, header + StudioHdrNumBonesOffset, sizeof(bones));
        if (id != StudioHeaderId || bones < 0 || bones > MaxBones) {
            return -1;
        }
        return bones;
    }
    __except (EXCEPTION_EXECUTE_HANDLER) {
        return -1;
    }
}

// r_hwskin_transform_chain: 0, the default, uploads studiorender's pose-to-world bones as they are; 1 and 2
// make them model-relative with the drawn entity's model-to-world, the only use of that matrix. So only those
// two modes read the entity's coordinate frame, through ReadProcessMemory, which cannot fault.
constexpr bool TransformChainNeedsModelToWorld(int mode)
{
    return mode == 1 || mode == 2;
}

} // namespace StudioDrawPolicy
