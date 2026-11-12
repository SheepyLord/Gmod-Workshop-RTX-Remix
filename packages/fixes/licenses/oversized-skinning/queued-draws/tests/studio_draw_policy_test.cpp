// GPL-2.0. Regression for source/studio_draw_policy.h: the studio render hooks take the drawn model from
// studiorender's own state and never read the renderable, which on the queued render thread can be an entity
// the main thread has already deleted (the crashes of 2026-11-11 and 2026-11-12 at instruction pointer 0).
// Compiles alone (no SDK, Windows): cl /EHsc /std:c++17 /W4 /WX /UNDEBUG tests/studio_draw_policy_test.cpp
#include <cassert>
#include <cstdint>
#include <cstring>
#include <iostream>
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#include "../source/studio_draw_policy.h"

using namespace StudioDrawPolicy;

namespace {

// The first bytes of a studiohdr_t, as far as the policy reads them.
struct Header {
    alignas(8) unsigned char bytes[0xA0] = {};
    explicit Header(int bones, std::int32_t id = StudioHeaderId) {
        std::memcpy(bytes + StudioHdrIdOffset, &id, sizeof(id));
        std::memcpy(bytes + StudioHdrNumBonesOffset, &bones, sizeof(bones));
    }
};

// CStudioRender up to m_pStudioHdr.
struct StudioRender {
    alignas(8) unsigned char bytes[StudioRenderStudioHdrOffset + sizeof(void*)] = {};
    explicit StudioRender(const void* header) { Point(header); }
    void Point(const void* header) { std::memcpy(bytes + StudioRenderStudioHdrOffset, &header, sizeof(header)); }
};

// A deleted entity as the dumps show it: its first word still leads to a table whose slot 9
// (IClientRenderable::GetModel) points at code. The renderable lookup this policy replaced called that slot.
bool g_staleSlotCalled = false;
void* StaleSlot(void*)
{
    g_staleSlotCalled = true;
    return nullptr;
}
struct DeletedEntity {
    void* vtable = nullptr;
    void* table[16] = {};
    DeletedEntity()
    {
        for (void*& slot : table) {
            slot = reinterpret_cast<void*>(&StaleSlot);
        }
        vtable = table;
    }
};

// A renderable in a guard page: any read of it raises the guard exception, and Windows clears the guard.
struct GuardedPage {
    void* page = nullptr;
    GuardedPage()
    {
        page = VirtualAlloc(nullptr, 4096, MEM_RESERVE | MEM_COMMIT, PAGE_READWRITE);
        assert(page != nullptr);
        DWORD old = 0;
        const BOOL guarded = VirtualProtect(page, 4096, PAGE_READWRITE | PAGE_GUARD, &old);
        assert(guarded);
    }
    ~GuardedPage() { VirtualFree(page, 0, MEM_RELEASE); }
    bool Untouched() const
    {
        MEMORY_BASIC_INFORMATION info{};
        const SIZE_T size = VirtualQuery(page, &info, sizeof(info));
        assert(size == sizeof(info));
        return (info.Protect & PAGE_GUARD) != 0;
    }
};

// Reads one byte and says whether that raised an exception (no objects to unwind here, for __try).
bool ReadRaises(const void* address)
{
    __try {
        volatile unsigned char probe = *static_cast<const volatile unsigned char*>(address);
        (void)probe;
        return false;
    }
    __except (EXCEPTION_EXECUTE_HANDLER) {
        return true;
    }
}

// A page nobody may read, for headers that are not there.
struct NoAccessPage {
    unsigned char* page = nullptr;
    NoAccessPage()
    {
        page = static_cast<unsigned char*>(VirtualAlloc(nullptr, 8192, MEM_RESERVE | MEM_COMMIT, PAGE_READWRITE));
        assert(page != nullptr);
        DWORD old = 0;
        const BOOL closed = VirtualProtect(page + 4096, 4096, PAGE_NOACCESS, &old);
        assert(closed);
    }
    ~NoAccessPage() { VirtualFree(page, 0, MEM_RELEASE); }
};

void BoneCountFromTheDraw()
{
    Header prop(1), chunk(0), ragdoll(57), most(MaxBones);
    StudioRender render(&prop);
    int renderable = 0;
    assert(BoneCount(&render, &renderable) == 1 && "the drawn model's bone count");
    render.Point(&chunk);
    assert(BoneCount(&render, &renderable) == 0);
    render.Point(&ragdoll);
    assert(BoneCount(&render, &renderable) == 57 && "the next draw's model, whatever the renderable says");
    render.Point(&most);
    assert(BoneCount(&render, &renderable) == MaxBones);
}

void UnknownCounts()
{
    int renderable = 0;
    Header prop(1);
    StudioRender render(&prop);
    assert(BoneCount(&render, nullptr) == -1 && "a draw without a renderable keeps -1, as the lookup gave it");
    assert(BoneCount(nullptr, &renderable) == -1);
    assert(BoneCount(reinterpret_cast<const void*>(std::uintptr_t{0x1234}), &renderable) == -1);

    Header tooMany(MaxBones + 1), negative(-5), notStudio(1, 0x12345678);
    for (const Header* header : {&tooMany, &negative, &notStudio}) {
        render.Point(header);
        assert(BoneCount(&render, &renderable) == -1 && "only a studio header with a sane bone count");
    }
    render.Point(nullptr);
    assert(BoneCount(&render, &renderable) == -1);
    render.Point(reinterpret_cast<const void*>(std::uintptr_t{0x40}));
    assert(BoneCount(&render, &renderable) == -1);

    // A header that is not readable (a changed layout) gives -1 instead of ending the game.
    NoAccessPage closed;
    render.Point(closed.page + 4096);
    assert(BoneCount(&render, &renderable) == -1);
    // ... also when only numbones lies past the readable page.
    unsigned char* edge = closed.page + 4096 - 8;
    const std::int32_t id = StudioHeaderId;
    std::memcpy(edge, &id, sizeof(id));
    render.Point(edge);
    assert(BoneCount(&render, &renderable) == -1);
}

void TheRenderableIsNeverRead()
{
    Header gib(1);
    StudioRender render(&gib);

    DeletedEntity deleted;
    assert(BoneCount(&render, &deleted) == 1);
    assert(!g_staleSlotCalled && "nothing is called through the renderable's vtable");

    GuardedPage guarded;
    assert(BoneCount(&render, guarded.page) == 1);
    assert(guarded.Untouched() && "not one byte of the renderable is read");

    // The guard works: a read trips it.
    const bool tripped = ReadRaises(guarded.page);
    assert(tripped && !guarded.Untouched() && "the guard page notices a read");
}

void LightingRuleUnchanged()
{
    constexpr int software = 1, mouth = 2;
    struct Case { int engine, bones; bool forceLight, forceSkin; int lighting; };
    const Case cases[] = {
        {software, 1, false, false, LightingHardware},  // a one-bone prop gets hardware lighting
        {software, 0, false, false, LightingHardware},  // so does a model without bones
        {software, 2, false, false, software},          // a skinned model keeps the engine's choice
        {LightingHardware, 57, false, false, LightingHardware},
        {mouth, 57, false, false, mouth},
        {software, 57, false, true, LightingHardware},  // r_forcehwskin: hardware for skinned models
        {software, -1, false, false, software},         // an unknown count counts as skinned
        {software, -1, false, true, LightingHardware},
        {software, 57, true, false, LightingHardware},  // r_forcehwlight: hardware for everything
        {mouth, -1, true, false, LightingHardware},
    };
    for (const Case& c : cases) {
        const Lighting chosen = ChooseLighting(c.engine, c.bones, c.forceLight, c.forceSkin);
        assert(chosen.lighting == c.lighting && chosen.meshLighting == c.lighting);
    }
    // The rule prop_fixes.cpp wrote out before this change, over a grid.
    for (int engine : {0, 1, 2}) {
        for (int bones : {-1, 0, 1, 2, 3, 57, 128, MaxBones}) {
            for (bool forceLight : {false, true}) {
                for (bool forceSkin : {false, true}) {
                    int lighting = engine;
                    if (forceLight || (bones >= 0 && bones <= 1) || forceSkin) {
                        lighting = LightingHardware;
                    }
                    const Lighting chosen = ChooseLighting(engine, bones, forceLight, forceSkin);
                    assert(chosen.lighting == lighting && chosen.meshLighting == lighting);
                }
            }
        }
    }
}

void TransformChainModes()
{
    assert(!TransformChainNeedsModelToWorld(0) && "the default never reads the renderable");
    assert(TransformChainNeedsModelToWorld(1) && TransformChainNeedsModelToWorld(2));
    assert(!TransformChainNeedsModelToWorld(-1) && !TransformChainNeedsModelToWorld(3));
}

} // namespace

int main()
{
    BoneCountFromTheDraw();
    UnknownCounts();
    TheRenderableIsNeverRead();
    LightingRuleUnchanged();
    TransformChainModes();
    std::cout << "PASS studio draw policy: bone counts from studiorender's header (0, 1, 57, 4096), unknown counts "
                 "(no renderable, no or unreadable header, wrong id, out of range), a deleted entity's renderable "
                 "never read or called, the lighting rule unchanged, model-to-world only for transform chains 1 and 2\n";
    return 0;
}
