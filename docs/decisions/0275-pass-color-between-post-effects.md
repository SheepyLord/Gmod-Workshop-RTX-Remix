# 0275. Pass the current color between post effects

- Status: Accepted 2026-11-27 (the user approved the local Workshop update)
- Requested by the user: "Please address #2 and #3 to a ready to commit state."

## Context

Sharpening, motion blur and lens effects need separate input and output images because they sample neighbouring pixels. Each copied its completed image back to the public final target. All three copies appeared in the 4K Modern House trace.

## Decision

Keep the final image's public identity. Start each eye's post-processing in that image. A filter that actually produces an out-of-place result exchanges the roles of two full-resolution RGBA16F images. Skipped filters leave the roles alone. Dust, bloom, exposure, tone mapping and neural rendering follow the current image or the other image as appropriate. Both images support the dust color attachment.

The existing sRGB and dither pass always writes the public final image. After an odd number of exchanges it reads the other image. After an even number it works in place. Overlay rendering, capture, VR, poster tiles, HUD-less frame generation and presentation then consume the original final target.

## Consequences

The three filter copy-backs are removed without a new full-resolution allocation or a change to effect order. The test covers both sRGB input paths and each filter combination in the PoC. See the [handover](../handover/renderer-frame-output-report.md).
