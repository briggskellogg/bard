#include "WispAudioAtomics.h"
#include <stdatomic.h>
#include <stdlib.h>

struct WispCaptureState {
    uint64_t capacity;
    uint64_t maximum_frames;
    _Atomic uint64_t write_index;
    _Atomic uint64_t read_index;
    _Atomic uint64_t frames;
    /* Bit 0: producer owns a slot. Bit 1: no new producer may enter. */
    _Atomic int gate;
    _Atomic int limit_reached;
    _Atomic int error;
    _Atomic int finishing;
};

WispCaptureState *wisp_capture_create(uint64_t capacity, uint64_t maximum_frames) {
    if (!capacity || !maximum_frames) return NULL;
    WispCaptureState *s = calloc(1, sizeof(*s));
    if (!s) return NULL;
    s->capacity = capacity;
    s->maximum_frames = maximum_frames;
    atomic_init(&s->write_index, 0);
    atomic_init(&s->read_index, 0);
    atomic_init(&s->frames, 0);
    atomic_init(&s->gate, 0);
    atomic_init(&s->limit_reached, 0);
    atomic_init(&s->error, 0);
    atomic_init(&s->finishing, 0);
    if (!atomic_is_lock_free(&s->write_index) || !atomic_is_lock_free(&s->gate)) {
        free(s); return NULL;
    }
    return s;
}

void wisp_capture_destroy(WispCaptureState *s) { free(s); }

void wisp_capture_fail(WispCaptureState *s, int reason) {
    int expected = 0;
    atomic_compare_exchange_strong_explicit(&s->error, &expected, reason, memory_order_acq_rel, memory_order_relaxed);
    atomic_fetch_or_explicit(&s->gate, 2, memory_order_acq_rel);
}

int wisp_capture_begin(WispCaptureState *s, uint32_t requested, uint64_t *slot, uint32_t *accepted) {
    if (!requested) return 0;
    int expected = 0;
    /* Admission and closing modify the same gate, giving them one order. */
    if (!atomic_compare_exchange_strong_explicit(&s->gate, &expected, 1, memory_order_acquire, memory_order_relaxed)) return 0;
    uint64_t write = atomic_load_explicit(&s->write_index, memory_order_relaxed);
    uint64_t read = atomic_load_explicit(&s->read_index, memory_order_acquire);
    if (write - read >= s->capacity) {
        wisp_capture_fail(s, 2);
        atomic_fetch_and_explicit(&s->gate, ~1, memory_order_release);
        return -1;
    }
    uint64_t frames = atomic_load_explicit(&s->frames, memory_order_relaxed);
    uint64_t remaining = s->maximum_frames - frames;
    *slot = write % s->capacity;
    *accepted = (uint32_t)(remaining < requested ? remaining : requested);
    return 1;
}

void wisp_capture_commit(WispCaptureState *s, uint32_t count) {
    uint64_t frames = atomic_fetch_add_explicit(&s->frames, count, memory_order_relaxed) + count;
    if (frames >= s->maximum_frames) {
        atomic_store_explicit(&s->limit_reached, 1, memory_order_release);
        atomic_fetch_or_explicit(&s->gate, 2, memory_order_acq_rel);
    }
    /* Release publishes both PCM bytes and frameLength to the consumer. */
    atomic_fetch_add_explicit(&s->write_index, 1, memory_order_release);
    atomic_fetch_and_explicit(&s->gate, ~1, memory_order_release);
}

int wisp_capture_peek(WispCaptureState *s, uint64_t *slot) {
    uint64_t read = atomic_load_explicit(&s->read_index, memory_order_relaxed);
    uint64_t write = atomic_load_explicit(&s->write_index, memory_order_acquire);
    if (read == write) return 0;
    *slot = read % s->capacity;
    return 1;
}

void wisp_capture_consume(WispCaptureState *s) {
    /* Release permits the producer to reuse this slot only after the write. */
    atomic_fetch_add_explicit(&s->read_index, 1, memory_order_release);
}

int wisp_capture_request_finish(WispCaptureState *s) {
    int expected = 0;
    if (!atomic_compare_exchange_strong_explicit(&s->finishing, &expected, 1, memory_order_acq_rel, memory_order_relaxed)) return 0;
    atomic_fetch_or_explicit(&s->gate, 2, memory_order_acq_rel);
    return 1;
}

int wisp_capture_in_flight(WispCaptureState *s) { return atomic_load_explicit(&s->gate, memory_order_acquire) & 1; }
uint64_t wisp_capture_frames(WispCaptureState *s) { return atomic_load_explicit(&s->frames, memory_order_acquire); }
int wisp_capture_limit_reached(WispCaptureState *s) { return atomic_load_explicit(&s->limit_reached, memory_order_acquire); }
int wisp_capture_error(WispCaptureState *s) { return atomic_load_explicit(&s->error, memory_order_acquire); }
