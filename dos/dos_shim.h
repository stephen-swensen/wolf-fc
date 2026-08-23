/* DJGPP compatibility shim for wolf-fc's emitted C, force-included ahead of
 * the translation unit (-include). Fills the POSIX/C11 gaps DJGPP 2.05 has:
 * struct timespec + timespec_get + nanosleep, C99 fmin/fmax, and glibc's
 * __errno_location accessor (DJGPP's errno is a plain extern int). All
 * static inline: no link-time collisions if a future DJGPP grows them. */
#ifndef DOS_SHIM_H
#define DOS_SHIM_H
#include <time.h>
#include <errno.h>
#include <stdint.h>
#include <unistd.h>

struct timespec { time_t tv_sec; long tv_nsec; };

static inline int timespec_get(struct timespec *ts, int base) {
    ts->tv_sec = time(NULL);
    ts->tv_nsec = 0;
    return base;
}

static inline int nanosleep(const struct timespec *req, struct timespec *rem) {
    (void)rem;
    usleep((unsigned)(req->tv_sec * 1000000L + req->tv_nsec / 1000L));
    return 0;
}

static inline double fmin(double a, double b) { return a < b ? a : b; }
static inline double fmax(double a, double b) { return a > b ? a : b; }

static inline int32_t *__errno_location(void) { return (int32_t *)&errno; }

#endif
