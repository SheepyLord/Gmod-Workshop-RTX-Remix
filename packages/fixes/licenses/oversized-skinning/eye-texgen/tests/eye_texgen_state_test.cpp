// Regression for eye_texgen_state.h (patch 13, eye-texgen): the eye shaders' TexGen request is written again just
// before the eye's draw, after Source's shader API overwrote stage 1, and never touches a draw after the request ends.
// Builds alone: cl /EHsc /std:c++17 /W4 /WX /UNDEBUG /DWIN32_LEAN_AND_MEAN /DNOMINMAX eye_texgen_state_test.cpp
#include <windows.h>
#include <d3d9.h>

#include <cstdio>
#include <cstdlib>
#include <map>
#include <utility>
#include <vector>

#include "../source/eye_texgen_state.h"

static_assert(EyeTexGen::kTexCoordIndex == D3DTSS_TEXCOORDINDEX, "D3DTSS_TEXCOORDINDEX");
static_assert(EyeTexGen::kTextureTransformFlags == D3DTSS_TEXTURETRANSFORMFLAGS, "D3DTSS_TEXTURETRANSFORMFLAGS");
static_assert(EyeTexGen::kCameraSpacePosition == D3DTSS_TCI_CAMERASPACEPOSITION, "D3DTSS_TCI_CAMERASPACEPOSITION");
static_assert(EyeTexGen::kCount2 == D3DTTFF_COUNT2, "D3DTTFF_COUNT2");
static_assert(EyeTexGen::kAddressU == D3DSAMP_ADDRESSU, "D3DSAMP_ADDRESSU");
static_assert(EyeTexGen::kAddressV == D3DSAMP_ADDRESSV, "D3DSAMP_ADDRESSV");
static_assert(EyeTexGen::kClamp == D3DTADDRESS_CLAMP, "D3DTADDRESS_CLAMP");

namespace {

int g_checks = 0;

void Check(bool condition, const char* what) {
    ++g_checks;
    if (!condition) {
        std::printf("FAIL %s\n", what);
        std::exit(1);
    }
}

// A device that keeps the stage and sampler states it is given and counts the writes.
struct FakeDevice {
    std::map<std::pair<unsigned long, unsigned long>, unsigned long> stages;
    std::map<std::pair<unsigned long, unsigned long>, unsigned long> samplers;
    int writes = 0;

    void SetTextureStageState(unsigned long stage, unsigned long type, unsigned long value) {
        stages[{stage, type}] = value;
        ++writes;
    }
    void SetSamplerState(unsigned long stage, unsigned long type, unsigned long value) {
        samplers[{stage, type}] = value;
        ++writes;
    }
    unsigned long Stage(unsigned long stage, unsigned long type) const {
        auto it = stages.find({stage, type});
        return it == stages.end() ? 0xFFFFFFFFul : it->second;
    }
    unsigned long Sampler(unsigned long stage, unsigned long type) const {
        auto it = samplers.find({stage, type});
        return it == samplers.end() ? 0xFFFFFFFFul : it->second;
    }
    // What the iris stage holds at a draw is what Remix reads.
    bool IrisTexGen() const {
        return Stage(1, D3DTSS_TEXCOORDINDEX) == D3DTSS_TCI_CAMERASPACEPOSITION &&
               (Stage(1, D3DTSS_TEXTURETRANSFORMFLAGS) & 0x3) != D3DTTFF_DISABLE;
    }
};

// What RTX_SetEyeTexGenState writes on the device itself (unchanged by the patch).
void HelperWrites(FakeDevice& device, bool enable) {
    device.SetTextureStageState(0, D3DTSS_TEXCOORDINDEX, 0);
    device.SetTextureStageState(0, D3DTSS_TEXTURETRANSFORMFLAGS, D3DTTFF_DISABLE);
    device.SetTextureStageState(1, D3DTSS_TEXCOORDINDEX, enable ? D3DTSS_TCI_CAMERASPACEPOSITION : 1);
    device.SetTextureStageState(1, D3DTSS_TEXTURETRANSFORMFLAGS, enable ? D3DTTFF_COUNT2 : D3DTTFF_DISABLE);
}

// Source's shader API committing its cached stage 1 state before the draw: the overwrite that lost the first eye.
void ShaderApiCommit(FakeDevice& device) {
    device.SetTextureStageState(1, D3DTSS_TEXCOORDINDEX, 1);
    device.SetTextureStageState(1, D3DTSS_TEXTURETRANSFORMFLAGS, D3DTTFF_COUNT4);
}

}  // namespace

int main() {
    // No request: a draw changes nothing.
    {
        EyeTexGen::Request request;
        FakeDevice device;
        Check(!request.Pending(), "a new request is off");
        Check(!request.ApplyBeforeDraw(device), "no write without a request");
        Check(device.writes == 0, "no device write without a request");
    }

    // A request writes exactly the iris stage's four states, the values RTX_SetEyeTexGenState(1) writes.
    {
        EyeTexGen::Request request;
        FakeDevice device;
        request.Set(true);
        Check(request.Pending(), "the request stands");
        Check(request.ApplyBeforeDraw(device), "the request writes");
        Check(device.writes == 4, "four writes");
        Check(device.Stage(1, D3DTSS_TEXCOORDINDEX) == D3DTSS_TCI_CAMERASPACEPOSITION, "camera-space TexGen on stage 1");
        Check(device.Stage(1, D3DTSS_TEXTURETRANSFORMFLAGS) == D3DTTFF_COUNT2, "two transformed coordinates");
        Check(device.Sampler(1, D3DSAMP_ADDRESSU) == D3DTADDRESS_CLAMP, "clamped in U");
        Check(device.Sampler(1, D3DSAMP_ADDRESSV) == D3DTADDRESS_CLAMP, "clamped in V");
        Check(device.Stage(0, D3DTSS_TEXCOORDINDEX) == 0xFFFFFFFFul, "stage 0 (the sclera's UV0) untouched");
        Check(request.ApplyBeforeDraw(device) && device.writes == 8, "every draw while it stands");
        request.Set(false);
        Check(!request.ApplyBeforeDraw(device) && device.writes == 8, "nothing once it ends");
    }

    // The sequence that lost the first eye of a model every frame: the helper's write, the shader API's commit, the
    // draw. Without the draw-time write Remix sees no TexGen; with it, it does; the draw after the shader's own reset
    // is left alone.
    {
        FakeDevice before;
        HelperWrites(before, true);
        ShaderApiCommit(before);
        Check(!before.IrisTexGen(), "the commit removes the eye's TexGen (the fault)");

        EyeTexGen::Request request;
        FakeDevice device;
        request.Set(true);
        HelperWrites(device, true);
        ShaderApiCommit(device);
        request.ApplyBeforeDraw(device);
        Check(device.IrisTexGen(), "the first eye's draw has camera-space TexGen");

        // The second eye: no commit in between (the cache already agreed); still fine.
        HelperWrites(device, true);
        request.ApplyBeforeDraw(device);
        Check(device.IrisTexGen(), "the second eye's draw has camera-space TexGen");

        // The shader's RTX_SetEyeTexGenState(0) after its draw, then the next (non-eye) draw.
        request.Set(false);
        HelperWrites(device, false);
        const int writes = device.writes;
        Check(!request.ApplyBeforeDraw(device), "no write for the next draw");
        Check(device.writes == writes && !device.IrisTexGen(), "the next draw keeps the reset state");
    }

    // Requests are per object: the module keeps one per thread, so another thread's draws never see this one.
    {
        EyeTexGen::Request renderThread, mainThread;
        FakeDevice device;
        renderThread.Set(true);
        Check(!mainThread.ApplyBeforeDraw(device) && device.writes == 0, "another request is unaffected");
    }

    std::printf("PASS eye texgen: %d checks\n", g_checks);
    return 0;
}
