#ifndef WISP_AUDIO_ATOMICS_H
#define WISP_AUDIO_ATOMICS_H
#include <stdint.h>

typedef struct WispCaptureState WispCaptureState;
WispCaptureState *wisp_capture_create(uint64_t capacity, uint64_t maximum_frames);
void wisp_capture_destroy(WispCaptureState *state);
/* Exactly one producer may own a slot between begin and commit. */
int wisp_capture_begin(WispCaptureState *state, uint32_t requested_frames,
                       uint64_t *slot, uint32_t *accepted_frames);
void wisp_capture_commit(WispCaptureState *state, uint32_t frames);
/* Exactly one consumer owns the published slot until consume. */
int wisp_capture_peek(WispCaptureState *state, uint64_t *slot);
void wisp_capture_consume(WispCaptureState *state);
void wisp_capture_fail(WispCaptureState *state, int reason);
int wisp_capture_request_finish(WispCaptureState *state);
int wisp_capture_in_flight(WispCaptureState *state);
uint64_t wisp_capture_frames(WispCaptureState *state);
int wisp_capture_limit_reached(WispCaptureState *state);
int wisp_capture_error(WispCaptureState *state);
#endif
