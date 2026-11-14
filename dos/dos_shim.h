/* DJGPP compatibility shim for wolf-fc's emitted C, force-included ahead of
 * the translation unit (-include). Fills the POSIX/C11 gaps DJGPP 2.05 has:
 * struct timespec + timespec_get + clock_gettime(CLOCK_MONOTONIC) +
 * nanosleep, C99 fmin/fmax, and glibc's __errno_location accessor (DJGPP's
 * errno is a plain extern int). All static inline: no link-time collisions
 * if a future DJGPP grows them. */
#ifndef DOS_SHIM_H
#define DOS_SHIM_H
#include <time.h>
#include <errno.h>
#include <stdint.h>
#include <unistd.h>

struct timespec { time_t tv_sec; long tv_nsec; };

#ifndef TIME_UTC
#define TIME_UTC 1
#endif

/* The wall clock (sys.time_ms/time_ns), from gettimeofday. */
static inline int timespec_get(struct timespec *ts, int base) {
    struct timeval tv;
    if (base != TIME_UTC || gettimeofday(&tv, NULL) != 0) return 0;
    ts->tv_sec = tv.tv_sec;
    ts->tv_nsec = tv.tv_usec * 1000L;
    return base;
}

typedef int clockid_t;
#define CLOCK_MONOTONIC 1

/* The monotonic clock (sys.monotonic_ms/monotonic_ns), from uclock(): the
 * PIT at 1193180 Hz, ~838 ns a tick, counting from uclock's first call. */
static inline int clock_gettime(clockid_t id, struct timespec *ts) {
    if (id != CLOCK_MONOTONIC) { errno = EINVAL; return -1; }
    uclock_t u = uclock();
    ts->tv_sec = (time_t)(u / UCLOCKS_PER_SEC);
    ts->tv_nsec = (long)((u % UCLOCKS_PER_SEC) * 1000000000LL / UCLOCKS_PER_SEC);
    return 0;
}

/* Whole seconds and the rest separately, so a long sleep can't overflow
 * usleep's unsigned microseconds; the rest rounds up so the sleep is never
 * short. Nothing interrupts it, so rem is never written. */
static inline int nanosleep(const struct timespec *req, struct timespec *rem) {
    (void)rem;
    if (req->tv_sec < 0 || req->tv_nsec < 0 || req->tv_nsec > 999999999L) {
        errno = EINVAL;
        return -1;
    }
    if (req->tv_sec > 0) sleep((unsigned)req->tv_sec);
    usleep((unsigned)((req->tv_nsec + 999L) / 1000L));
    return 0;
}

static inline double fmin(double a, double b) { return a < b ? a : b; }
static inline double fmax(double a, double b) { return a > b ? a : b; }

static inline int32_t *__errno_location(void) { return (int32_t *)&errno; }

#endif
