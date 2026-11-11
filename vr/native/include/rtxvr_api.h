// SPDX-License-Identifier: MIT
#pragma once
#include <stdint.h>
#include <wchar.h>

#ifdef __cplusplus
extern "C" {
#endif

#define RTXVR_API_VERSION 3u

typedef struct rtxvr_Matrix34 { float m[3][4]; } rtxvr_Matrix34;      /* OpenVR's HmdMatrix34_t layout */

typedef struct rtxvr_Eye {
  float tanLeft, tanRight, tanTop, tanBottom;   /* IVRSystem::GetProjectionRaw, as OpenVR returns them */
  rtxvr_Matrix34 eyeToHead;                     /* IVRSystem::GetEyeToHeadTransform, full rotation and translation */
} rtxvr_Eye;

typedef void* (*rtxvr_GetGenericInterfaceFn)(const char* interfaceVersion, int* error);

typedef struct rtxvr_StartInfo {
  uint32_t structSize;                          /* sizeof(rtxvr_StartInfo) */
  uint32_t apiVersion;                          /* RTXVR_API_VERSION */
  rtxvr_GetGenericInterfaceFn getGenericInterface;  /* openvr_api.dll's VR_GetGenericInterface, session initialised */
  uint32_t eyeWidth, eyeHeight;                 /* IVRSystem::GetRecommendedRenderTargetSize */
  float    refreshHz;                           /* Prop_DisplayFrequency_Float */
  float    worldUnitsPerMetre;                  /* game units in a metre, for the eye offset */
  rtxvr_Eye eyes[2];                            /* 0 left, 1 right */
  float    renderScale;                         /* the preset's scale on eyeWidth x eyeHeight; 1 = as recommended */
  uint32_t flags;                               /* RTXVR_START_* */
} rtxvr_StartInfo;

#define RTXVR_START_NO_SUBMIT   0x1u   /* render and warp, hand nothing to the compositor (tests without SteamVR) */
#define RTXVR_START_RENDER_PACING 0x4u /* render thread owns Submit/WaitGetPoses; module predicts without waiting */
#define RTXVR_START_NO_MIRROR   0x2u   /* leave the game's own target alone */

typedef struct rtxvr_FramePose {
  uint32_t structSize;
  uint32_t flags;                               /* RTXVR_POSE_* */
  uint64_t sequence;                            /* the module's frame number, rising */
  rtxvr_Matrix34 hmdToTracking;                 /* the head pose this frame is rendered for */
  float cameraOrigin[3];                        /* the game camera the add-on set for it: world units */
  float cameraAngles[3];                        /* pitch, yaw, roll in degrees, Source's convention */
  double sampleTimeSeconds;                    /* QPC seconds, when the module sampled tracking */
  double predictedDisplayTimeSeconds;          /* same clock, prediction target */
  double baseSecondsToPhotons;                 /* next vsync + vsync-to-photons, excluding measured pipeline */
} rtxvr_FramePose;

#define RTXVR_POSE_SCRIPTED     0x1u   /* a test pose: submit without a pose (the compositor uses its own) */

typedef struct rtxvr_Status {
  uint32_t structSize;
  uint32_t state;                               /* RTXVR_STATE_* */
  int32_t  lastError;                           /* RTXVR_E_*; 0 when none */
  char     lastErrorText[256];                  /* UTF-8, for the page and the log; names a missing extension */
  uint32_t centreWidth, centreHeight;           /* the centre view's output size */
  uint32_t renderWidth, renderHeight;           /* what is path traced before upscaling */
  uint32_t eyeWidth, eyeHeight;                 /* the eye images submitted */
  uint64_t framesRendered, framesSubmitted, submitErrors;
  int32_t  lastSubmitError;                     /* EVRCompositorError of the last failed Submit */
  uint64_t posesMatched, posesUnmatched;        /* frames whose camera matched a pushed pose, and those that did not */
  float    gpuMsTotal, gpuMsPathTrace, gpuMsUpscale, gpuMsWarp, gpuMsOther;   /* GPU time of the last frame by pass */
  float    cpuMsSubmit;                         /* time inside the two Submit calls, last frame */
  uint32_t overlaysBound;                       /* overlay sources that found their render target */
  uint64_t overlayUpdates;
  uint64_t timingSamples, renderWaitCalls;
  double poseAgeMs, predictionErrorMs, pipelineIntervals;
  float renderWaitMs, renderWaitMaxMs;
  uint64_t lastPoseSequence;
  uint64_t focusLossIntervals, waitFailures;    /* skipped focus intervals and other WaitGetPoses errors */
} rtxvr_Status;

enum { RTXVR_STATE_OFF = 0, RTXVR_STATE_STARTING = 1, RTXVR_STATE_RUNNING = 2, RTXVR_STATE_FAILED = 3 };
enum { RTXVR_OK = 0, RTXVR_E_VERSION = 1, RTXVR_E_ARGUMENT = 2, RTXVR_E_NO_DEVICE = 3, RTXVR_E_ALREADY = 4,
       RTXVR_E_NOT_RUNNING = 5, RTXVR_E_EXTENSION = 6, RTXVR_E_INTERFACE = 7, RTXVR_E_RESOURCES = 8 };

uint32_t rtxvr_GetApiVersion(void);
int  rtxvr_Start(const rtxvr_StartInfo* info);
void rtxvr_Stop(void);
int  rtxvr_UpdateEyes(const rtxvr_Eye eyes[2]);                       /* the IPD or the projection changed */
int  rtxvr_PushFramePose(const rtxvr_FramePose* pose);
int  rtxvr_SetOverlaySource(uint64_t overlayHandle, uint32_t width, uint32_t height);   /* 0 x 0 removes it */
int  rtxvr_Capture(const wchar_t* folder, uint32_t what);             /* RTXVR_CAPTURE_*: the next frame's images as PNG */
int  rtxvr_GetStatus(rtxvr_Status* status);

#define RTXVR_CAPTURE_EYES     0x1u   /* left.png, right.png: what is submitted */
#define RTXVR_CAPTURE_CENTRE   0x2u   /* centre.png and centre_depth.png */
#define RTXVR_CAPTURE_OVERLAYS 0x4u   /* overlay_<handle>.png */
#define RTXVR_CAPTURE_MIRROR   0x8u   /* mirror.png: the game window's picture */

#ifdef __cplusplus
}
#endif
