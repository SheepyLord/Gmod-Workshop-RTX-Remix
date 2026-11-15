/* SPDX-License-Identifier: MIT */
/* The poster (ADR 0226 of the GMod native loader project): d3d9.dll's rtxposter_* exports. A picture several times
   the window's size, path traced in tiles of the window's own size and written as one PNG. Plain C; the loader
   project keeps a byte-identical copy as engine_guard/rtxposter_api.h for the module that calls it. */
#ifndef RTXPOSTER_API_H
#define RTXPOSTER_API_H
#include <stdint.h>
#include <wchar.h>

#define RTXPOSTER_API_VERSION 1u
#define RTXPOSTER_PATH_CHARS 520u
#define RTXPOSTER_DEFAULT_FRAMES 64u   /* frames a tile is traced before it is kept, when framesPerTile is 0 */

#define RTXPOSTER_SAVE_TILES 0x1u      /* also write each tile beside the poster: <name>_tile_<column>_<row>.png */

typedef struct rtxposter_Request {
  uint32_t structSize;                    /* sizeof(rtxposter_Request) */
  uint32_t multiplier;                    /* 1 to 16: the poster is the window's size times this */
  uint32_t framesPerTile;                 /* 4 to 4096 frames per tile; 0 for RTXPOSTER_DEFAULT_FRAMES */
  uint32_t flags;                         /* RTXPOSTER_* */
  wchar_t  path[RTXPOSTER_PATH_CHARS];    /* the PNG to write: an absolute path, written as <path>.part and renamed */
} rtxposter_Request;

enum { RTXPOSTER_STATE_IDLE = 0, RTXPOSTER_STATE_STARTING = 1, RTXPOSTER_STATE_RENDERING = 2, RTXPOSTER_STATE_WRITING = 3,
       RTXPOSTER_STATE_DONE = 4, RTXPOSTER_STATE_FAILED = 5 };

enum { RTXPOSTER_OK = 0, RTXPOSTER_E_VERSION = 1, RTXPOSTER_E_ARGUMENT = 2, RTXPOSTER_E_NO_DEVICE = 3,
       RTXPOSTER_E_BUSY = 4, RTXPOSTER_E_VR = 5, RTXPOSTER_E_SIZE = 6, RTXPOSTER_E_MEMORY = 7, RTXPOSTER_E_MOVED = 8,
       RTXPOSTER_E_RESIZED = 9, RTXPOSTER_E_CAPTURE = 10, RTXPOSTER_E_WRITE = 11, RTXPOSTER_E_CANCELLED = 12 };

typedef struct rtxposter_Status {
  uint32_t structSize;                    /* sizeof(rtxposter_Status) */
  uint32_t state;                         /* RTXPOSTER_STATE_* */
  uint32_t generation;                    /* how many posters were started; 0 before the first */
  int32_t  lastError;                     /* RTXPOSTER_E_* of the last poster that failed; 0 when it did not */
  uint32_t width, height;                 /* the poster's size */
  uint32_t columns, rows;                 /* its tiles across and down */
  uint32_t tilesDone;                     /* tiles traced and kept */
  uint32_t frame, framesPerTile;          /* the current tile's frames so far, and how many it gets */
  uint32_t reserved;
  char     lastErrorText[256];            /* why it failed, in English */
  wchar_t  path[RTXPOSTER_PATH_CHARS];    /* the poster; a file there once the state is DONE */
} rtxposter_Status;

#ifdef __cplusplus
extern "C" {
#endif
typedef uint32_t (*rtxposter_GetApiVersionFn)(void);
typedef int (*rtxposter_StartFn)(const rtxposter_Request*);      /* RTXPOSTER_OK, or why it cannot start */
typedef void (*rtxposter_CancelFn)(void);                         /* ends the poster at its next frame */
typedef int (*rtxposter_GetStatusFn)(rtxposter_Status*);         /* RTXPOSTER_OK or RTXPOSTER_E_ARGUMENT */
#ifdef __cplusplus
}
#endif
#endif
