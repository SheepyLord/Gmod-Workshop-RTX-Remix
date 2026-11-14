#pragma once

// The eye shaders' request for camera-space TexGen on the iris stage, kept until the draw it is for.
//
// The fixed-function Eyes_dx9 and EyeRefract_ff shaders (stdshader_dx6.dll) call RTX_SetEyeTexGenState(1) at the end
// of their dynamic state, and the tagged iris transform reaches Remix only if stage 1 still has camera-space TexGen
// at the draw. Source's shader API commits its own cached texture stage state between that call and the draw, and the
// helper writes the device directly, behind that cache: when the cache differs from what the API wants (the first
// eye after other draws, every frame), the commit overwrites stage 1 and Remix sees that eye as a plain sclera. The
// draw hook therefore asserts the request once more just before the draw.
//
// Standard C++ only (no Source SDK, no Windows SDK), so tests/eye_texgen_state_test.cpp builds it alone.

namespace EyeTexGen {

// Direct3D 9 values (d3d9types.h); HardwareSkinningHooks.cpp checks them against the SDK.
constexpr unsigned long kTexCoordIndex = 11;              // D3DTSS_TEXCOORDINDEX
constexpr unsigned long kTextureTransformFlags = 24;      // D3DTSS_TEXTURETRANSFORMFLAGS
constexpr unsigned long kCameraSpacePosition = 0x20000;   // D3DTSS_TCI_CAMERASPACEPOSITION
constexpr unsigned long kCount2 = 2;                      // D3DTTFF_COUNT2
constexpr unsigned long kAddressU = 1;                    // D3DSAMP_ADDRESSU
constexpr unsigned long kAddressV = 2;                    // D3DSAMP_ADDRESSV
constexpr unsigned long kClamp = 3;                       // D3DTADDRESS_CLAMP

// Stage 1 holds the projected iris; stage 0 keeps the sclera on the model's UV0.
constexpr unsigned long kIrisStage = 1;

class Request {
public:
    // RTX_SetEyeTexGenState(enable): on until the shader, or a hook's safety net, turns it off.
    void Set(bool enable) { m_pending = enable; }
    bool Pending() const { return m_pending; }

    // Just before a draw: while an eye shader's request stands, write the iris stage's TexGen state again (the same
    // values RTX_SetEyeTexGenState(1) writes). Device is anything with SetTextureStageState(stage, type, value) and
    // SetSamplerState(stage, type, value). Returns whether it wrote.
    template <class Device>
    bool ApplyBeforeDraw(Device& device) const {
        if (!m_pending) {
            return false;
        }
        device.SetTextureStageState(kIrisStage, kTexCoordIndex, kCameraSpacePosition);
        device.SetTextureStageState(kIrisStage, kTextureTransformFlags, kCount2);
        device.SetSamplerState(kIrisStage, kAddressU, kClamp);
        device.SetSamplerState(kIrisStage, kAddressV, kClamp);
        return true;
    }

private:
    bool m_pending = false;
};

}  // namespace EyeTexGen
