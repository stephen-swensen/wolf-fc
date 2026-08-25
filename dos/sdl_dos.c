/* sdl_dos.c — a real DOS (DJGPP) implementation of the SDL2 API surface
 * wolf-fc binds (see SDL2/SDL.h in this directory, whose struct layouts and
 * constants this file is the other half of). The FC source and the generated
 * C are untouched: this file simply replaces sdl_stub.c at link time, turning
 * the inert --test-only build into an interactive DOS game.
 *
 * Backend mapping:
 *   window/renderer/texture  -> VGA mode 13h (320x200x8), dynamic palette
 *                               allocation with a 15-bit nearest-color cache;
 *                               Present point-samples the game's supersampled
 *                               ARGB buffer (min scale 2 -> 640x400) down to
 *                               320x200 and blits via _dosmemput after vsync.
 *   events                   -> raw INT 9 keyboard handler (port 0x60 ring
 *                               buffer), scancode set 1 -> SDLK translation
 *                               in SDL_PollEvent, typematic repeats become
 *                               SDL_KEYDOWN with repeat=1, modifier state
 *                               tracked into keysym.mod (SDL KMOD_* layout).
 *   timing                   -> uclock() (PIT-based, ~1.19 MHz) for GetTicks
 *                               and the performance counter; Delay yields.
 *   audio                    -> Sound Blaster 16: 16-bit signed stereo
 *                               auto-init DMA at 8000 Hz, the SB IRQ
 *                               calling the game's SDL-style callback per
 *                               half-buffer (see the audio section below
 *                               for the rate rationale). No SB detected:
 *                               SDL_Init(AUDIO) fails and the game runs
 *                               silent as before.
 *
 * The display is reported as 320x240 (4:3): mode 13h pixels on a CRT are
 * non-square and the physical aspect is 4:3, so wolf-fc's Hor+ logic picks
 * the OG fb_w=320, and pick_scale_factor lands on the minimum scale 2.
 *
 * Cleanup (text mode + keyboard vector restore) runs from DestroyWindow,
 * atexit, and a SIGABRT hook, so FC guard aborts don't strand the console
 * in graphics mode with a dead keyboard.
 */
#include "SDL2/SDL.h"
#include <stddef.h>
#include <string.h>
#include <stdlib.h>
#include <stdio.h>
#include <signal.h>
#include <time.h>
#include <crt0.h>
#include <dpmi.h>
#include <go32.h>
#include <pc.h>
#include <sys/movedata.h>

/* The Sound Blaster ISR calls the game's whole mixer (FC code, music and
 * SFX data), so every page it might touch must be resident. Locking all
 * program memory is the standard DJGPP answer for ISR-heavy programs —
 * CWSDPMI then never pages any of it out. */
int _crt0_startup_flags = _CRT0_FLAG_LOCK_MEMORY;

/* ------------------------------------------------------------------ */
/* Timing                                                              */
/* ------------------------------------------------------------------ */

uint32_t SDL_GetTicks(void) {
    return (uint32_t)(uclock() * 1000 / UCLOCKS_PER_SEC);
}
uint64_t SDL_GetPerformanceCounter(void) { return (uint64_t)uclock(); }
uint64_t SDL_GetPerformanceFrequency(void) { return (uint64_t)UCLOCKS_PER_SEC; }

void SDL_Delay(uint32_t ms) {
    uclock_t end = uclock() + (uclock_t)ms * (UCLOCKS_PER_SEC / 1000);
    while (uclock() < end) __dpmi_yield();
}

/* ------------------------------------------------------------------ */
/* Keyboard: INT 9 handler + scancode ring                             */
/* ------------------------------------------------------------------ */

#define KB_RING 256
static volatile unsigned char kb_ring[KB_RING];
static volatile int kb_head, kb_tail;         /* head=write (IRQ), tail=read */
static _go32_dpmi_seginfo kb_old, kb_new;
static int kb_installed;

static void kb_handler(void) {
    unsigned char sc = inportb(0x60);
    int next = (kb_head + 1) & (KB_RING - 1);
    if (next != kb_tail) {                    /* drop on overflow */
        kb_ring[kb_head] = sc;
        kb_head = next;
    }
    outportb(0x20, 0x20);                     /* EOI */
}
static void kb_handler_end(void) {}           /* lock range marker */

static void kb_install(void) {
    if (kb_installed) return;
    _go32_dpmi_lock_data((void *)kb_ring, sizeof kb_ring);
    _go32_dpmi_lock_data((void *)&kb_head, sizeof kb_head);
    _go32_dpmi_lock_data((void *)&kb_tail, sizeof kb_tail);
    _go32_dpmi_lock_code(kb_handler,
        (unsigned long)((char *)kb_handler_end - (char *)kb_handler));
    _go32_dpmi_get_protected_mode_interrupt_vector(9, &kb_old);
    kb_new.pm_offset = (unsigned long)kb_handler;
    kb_new.pm_selector = _go32_my_cs();
    _go32_dpmi_allocate_iret_wrapper(&kb_new);
    _go32_dpmi_set_protected_mode_interrupt_vector(9, &kb_new);
    kb_installed = 1;
}

static void kb_remove(void) {
    if (!kb_installed) return;
    _go32_dpmi_set_protected_mode_interrupt_vector(9, &kb_old);
    _go32_dpmi_free_iret_wrapper(&kb_new);
    kb_installed = 0;
}

/* Scancode set 1 -> SDLK. Index by scancode & 0x7F; 0 = unmapped.
 * Extended (E0-prefixed) codes handled separately below. */
static const int32_t sc_to_sdlk[128] = {
    [0x01] = SDLK_ESCAPE,
    [0x02] = SDLK_1, [0x03] = SDLK_2, [0x04] = SDLK_3, [0x05] = SDLK_4,
    [0x06] = SDLK_5, [0x07] = SDLK_6, [0x08] = SDLK_7, [0x09] = SDLK_8,
    [0x0A] = SDLK_9, [0x0B] = SDLK_0,
    [0x0C] = 45 /* - */, [0x0D] = 61 /* = */,
    [0x0E] = SDLK_BACKSPACE, [0x0F] = SDLK_TAB,
    [0x10] = SDLK_q, [0x11] = SDLK_w, [0x12] = SDLK_e, [0x13] = SDLK_r,
    [0x14] = SDLK_t, [0x15] = SDLK_y, [0x16] = SDLK_u, [0x17] = SDLK_i,
    [0x18] = SDLK_o, [0x19] = SDLK_p,
    [0x1A] = 91 /* [ */, [0x1B] = 93 /* ] */,
    [0x1C] = SDLK_RETURN,
    [0x1E] = SDLK_a, [0x1F] = SDLK_s, [0x20] = SDLK_d, [0x21] = SDLK_f,
    [0x22] = SDLK_g, [0x23] = SDLK_h, [0x24] = SDLK_j, [0x25] = SDLK_k,
    [0x26] = SDLK_l,
    [0x27] = 59 /* ; */, [0x28] = 39 /* ' */, [0x29] = 96 /* ` */,
    [0x2B] = 92 /* \ */,
    [0x2C] = SDLK_z, [0x2D] = SDLK_x, [0x2E] = SDLK_c, [0x2F] = SDLK_v,
    [0x30] = SDLK_b, [0x31] = SDLK_n, [0x32] = SDLK_m,
    [0x33] = 44 /* , */, [0x34] = 46 /* . */, [0x35] = 47 /* / */,
    [0x39] = SDLK_SPACE,
    [0x57] = SDLK_F11,
};

/* Modifier scancodes (make codes). */
#define SC_LSHIFT 0x2A
#define SC_RSHIFT 0x36
#define SC_LCTRL  0x1D
#define SC_LALT   0x38

/* SDL KMOD_* bits (must match what input.fc tests: shift 0x0003, alt 0x0300). */
#define DOS_KMOD_LSHIFT 0x0001
#define DOS_KMOD_RSHIFT 0x0002
#define DOS_KMOD_LCTRL  0x0040
#define DOS_KMOD_RCTRL  0x0080
#define DOS_KMOD_LALT   0x0100
#define DOS_KMOD_RALT   0x0200

static uint16_t kb_mods;
static unsigned char kb_e0;                    /* saw E0 prefix */
/* Down-state tracked by scancode (E0-extended codes offset by 0x80), used
 * to tag typematic repeat makes with repeat=1 the way SDL tags OS repeats. */
static unsigned char sc_down[256];

int32_t SDL_PollEvent(SDL_Event *e) {
    while (kb_tail != kb_head) {
        unsigned char sc = kb_ring[kb_tail];
        kb_tail = (kb_tail + 1) & (KB_RING - 1);

        if (sc == 0xE0) { kb_e0 = 1; continue; }
        if (sc == 0xE1) { kb_e0 = 0; continue; }   /* Pause junk: ignore */

        int ext = kb_e0; kb_e0 = 0;
        int release = sc & 0x80;
        int code = sc & 0x7F;
        int idx = code + (ext ? 0x80 : 0);

        /* Modifiers update state and also report as events where mapped. */
        uint16_t mbit = 0;
        if (!ext && code == SC_LSHIFT) mbit = DOS_KMOD_LSHIFT;
        else if (!ext && code == SC_RSHIFT) mbit = DOS_KMOD_RSHIFT;
        else if (!ext && code == SC_LCTRL) mbit = DOS_KMOD_LCTRL;
        else if (ext && code == SC_LCTRL) mbit = DOS_KMOD_RCTRL;
        else if (!ext && code == SC_LALT) mbit = DOS_KMOD_LALT;
        else if (ext && code == SC_LALT) mbit = DOS_KMOD_RALT;
        if (mbit) {
            if (release) kb_mods &= (uint16_t)~mbit; else kb_mods |= mbit;
        }

        int32_t sym = 0;
        if (ext) {
            switch (code) {                    /* extended keys we map */
            case 0x48: sym = SDLK_UP; break;
            case 0x50: sym = SDLK_DOWN; break;
            case 0x4B: sym = SDLK_LEFT; break;
            case 0x4D: sym = SDLK_RIGHT; break;
            case 0x49: sym = SDLK_PAGEUP; break;
            case 0x51: sym = SDLK_PAGEDOWN; break;
            case 0x1C: sym = SDLK_RETURN; break;   /* keypad enter */
            case SC_LCTRL: sym = SDLK_LCTRL; break;
            case SC_LALT: sym = SDLK_LALT; break;
            default: break;
            }
        } else {
            sym = sc_to_sdlk[code];
            if (code == SC_LSHIFT || code == SC_RSHIFT) sym = SDLK_LSHIFT;
            else if (code == SC_LCTRL) sym = SDLK_LCTRL;
            else if (code == SC_LALT) sym = SDLK_LALT;
        }
        if (!sym) continue;                    /* unmapped key: swallow */

        int repeat = 0;
        if (release) {
            sc_down[idx] = 0;
        } else {
            repeat = sc_down[idx] != 0;        /* typematic make while held */
            sc_down[idx] = 1;
        }

        memset(e, 0, sizeof *e);
        e->type = release ? SDL_KEYUP : SDL_KEYDOWN;
        e->key.type = e->type;
        e->key.repeat = (uint8_t)repeat;
        e->key.keysym.scancode = idx;
        e->key.keysym.sym = sym;
        e->key.keysym.mod = kb_mods;
        return 1;
    }
    return 0;
}

void SDL_PumpEvents(void) { /* IRQ fills the ring; nothing to do */ }

/* ------------------------------------------------------------------ */
/* Video: mode 13h, dynamic palette, present                           */
/* ------------------------------------------------------------------ */

static int vid_active;                         /* mode 13h entered */
static unsigned char vga_shadow[320 * 200];    /* next frame, palette indices */

/* Dynamic palette, earned by the frame. Colors are allocated DAC slots on
 * first sight (a 15-bit RGB555 cache makes the steady-state per-pixel cost
 * one table lookup); when all 256 are taken, later colors take the nearest
 * allocated slot. First-come-forever allocation alone looks terrible in
 * practice — the boot screens (PG13 / title / menus) claim slots gameplay
 * then can't have, transient blends (damage flash, fades) squat forever,
 * and a plain gameplay frame legitimately draws from more than 256 colors
 * (base palette + the 0.75-dim side-wall twin). So Present histograms the
 * frame as it quantizes, and when too many pixels lack an exact slot for a
 * few consecutive frames, the palette is REBUILT from the frame's 256 most
 * popular colors: the DAC reprogram lands in the same vertical retrace as
 * that frame's blit, so the swap is never visible against stale indices.
 * Hysteresis (miss threshold + streak + cooldown) keeps a stable scene from
 * ever rebuilding, so there is no shimmer in normal play. */
static unsigned char pal_r[256], pal_g[256], pal_b[256];
static int pal_used;
static unsigned char q_lut[32768];        /* key -> DAC slot */
#define Q_EMPTY  0
#define Q_EXACT  1                        /* slot holds this exact color */
#define Q_APPROX 2                        /* nearest match — a "miss" */
static unsigned char q_state[32768];
static uint32_t q_rep[32768];             /* true 8-bit color behind a key */
static uint16_t q_hist[32768];            /* pixel counts, current frame */
static uint16_t q_touched[32768];         /* keys with q_hist != 0 */
static int q_ntouched;
static long q_miss_px;                    /* this frame's APPROX pixels */
static int q_miss_streak;                 /* consecutive over-threshold frames */
static int q_cooldown;                    /* frames until next rebuild allowed */

static int q_dac_dirty;                   /* full DAC write at next retrace */

static void vga_set_dac(int slot, int r, int g, int b) {
    outportb(0x3C8, (unsigned char)slot);
    outportb(0x3C9, (unsigned char)(r >> 2));
    outportb(0x3C9, (unsigned char)(g >> 2));
    outportb(0x3C9, (unsigned char)(b >> 2));
}

static void vga_write_dac_all(void) {
    outportb(0x3C8, 0);
    for (int i = 0; i < 256; i++) {
        outportb(0x3C9, (unsigned char)(pal_r[i] >> 2));
        outportb(0x3C9, (unsigned char)(pal_g[i] >> 2));
        outportb(0x3C9, (unsigned char)(pal_b[i] >> 2));
    }
}

/* count = 1: normal pass (miss accounting). count = 0: the re-quantize
 * pass after a same-frame rebuild — map only, stats frozen. The per-pixel
 * path deliberately does NO histogramming: an early version histogrammed
 * every pixel of every frame and roughly doubled Present's emulated-CPU
 * cost, dragging gameplay from 35 to ~23 fps. The histogram is a separate
 * pass that runs only when a rebuild actually triggers. */
static unsigned char quantize_map(uint32_t argb, int count) {
    int r = (argb >> 16) & 0xFF, g = (argb >> 8) & 0xFF, b = argb & 0xFF;
    int key = ((r >> 3) << 10) | ((g >> 3) << 5) | (b >> 3);
    unsigned char st = q_state[key];
    if (st != Q_EMPTY) {
        if (st == Q_APPROX && count) q_miss_px++;
        return q_lut[key];
    }
    unsigned char idx;
    if (pal_used < 256) {
        idx = (unsigned char)pal_used;
        pal_r[idx] = (unsigned char)r; pal_g[idx] = (unsigned char)g;
        pal_b[idx] = (unsigned char)b;
        vga_set_dac(idx, r, g, b);
        pal_used++;
        st = Q_EXACT;
    } else {
        /* Luma-weighted nearest — the eye resolves green differences far
         * better than blue, so weight the channels accordingly. */
        long best = 0x7FFFFFFF; int bi = 0;
        for (int i = 0; i < 256; i++) {
            int dr = r - pal_r[i], dg = g - pal_g[i], db = b - pal_b[i];
            long d = 3L * dr * dr + 6L * dg * dg + 1L * db * db;
            if (d < best) { best = d; bi = i; }
        }
        idx = (unsigned char)bi;
        st = Q_APPROX;
        if (count) q_miss_px++;
    }
    q_state[key] = st;
    q_lut[key] = idx;
    return idx;
}

static unsigned char quantize(uint32_t argb) { return quantize_map(argb, 1); }

/* Histogram one frame (the same sampling grid Present uses) into
 * q_hist/q_touched/q_rep. Runs ONLY when a rebuild has been decided — the
 * cost lives on rebuild frames, never on the steady-state per-pixel path. */
static void palette_histogram(const uint32_t *src, int stride, int xstep, int ystep) {
    for (int i = 0; i < q_ntouched; i++) q_hist[q_touched[i]] = 0;
    q_ntouched = 0;
    for (int y = 0; y < 200; y++) {
        const uint32_t *row = src + (size_t)(y * ystep) * stride;
        for (int x = 0; x < 320; x++) {
            uint32_t c = row[x * xstep];
            int key = (((int)(c >> 16) & 0xFF) >> 3 << 10) |
                      (((int)(c >> 8) & 0xFF) >> 3 << 5) |
                      (((int)c & 0xFF) >> 3);
            if (q_hist[key]++ == 0) {
                q_touched[q_ntouched++] = (uint16_t)key;
                q_rep[key] = c;
            }
        }
    }
}

/* Rebuild the palette from the just-collected frame histogram: its 256
 * most popular colors get exact DAC slots (any spare slots stay
 * allocatable for colors that appear later). The caller re-quantizes the
 * same frame against the fresh palette, so the DAC write lands in the
 * retrace of the frame quantized with it. */
static int q_item_cmp(const void *a, const void *b) {
    uint32_t x = *(const uint32_t *)a, y = *(const uint32_t *)b;
    return x < y ? 1 : x > y ? -1 : 0;   /* descending */
}

static void palette_rebuild(void) {
    static uint32_t items[32768];        /* count << 15 | key (count < 2^17) */
    int n = q_ntouched;
    for (int i = 0; i < n; i++) {
        uint16_t key = q_touched[i];
        items[i] = ((uint32_t)q_hist[key] << 15) | key;
    }
    qsort(items, (size_t)n, sizeof items[0], q_item_cmp);
    int slots = n < 256 ? n : 256;
    memset(q_state, 0, sizeof q_state);
    for (int i = 0; i < slots; i++) {
        int key = (int)(items[i] & 0x7FFF);
        uint32_t c = q_rep[key];
        pal_r[i] = (unsigned char)((c >> 16) & 0xFF);
        pal_g[i] = (unsigned char)((c >> 8) & 0xFF);
        pal_b[i] = (unsigned char)(c & 0xFF);
        q_state[key] = Q_EXACT;
        q_lut[key] = (unsigned char)i;
    }
    pal_used = slots;
    q_dac_dirty = 1;
}

static void vga_wait_vsync(void) {
    /* Timeout at ~1.5 refresh periods: the audio ISR (a few ms of mixing)
     * can eclipse the ~0.6 ms retrace pulse entirely — without a bound the
     * poll would then spin a whole extra frame waiting for a pulse it
     * already missed. */
    uclock_t limit = uclock() + (uclock_t)(UCLOCKS_PER_SEC / 47);
    int spin = 0;
    while (inportb(0x3DA) & 0x08)
        if ((++spin & 63) == 0 && uclock() > limit) return;
    while (!(inportb(0x3DA) & 0x08))
        if ((++spin & 63) == 0 && uclock() > limit) return;
}

static void set_mode(int mode) {
    __dpmi_regs r;
    memset(&r, 0, sizeof r);
    r.x.ax = (unsigned short)mode;
    __dpmi_int(0x10, &r);
}

static void sb_shutdown(void);
static void sb_parse_blaster(void);
static int sb_reset(void);
static int sb_present;

/* Opt-in perf accounting ($WOLFDOS_STATS=1): shares of the emulated CPU
 * spent in Present vs the audio ISR, plus rebuild counts. rdtsc under
 * DOSBox counts emulated cycles — exactly the budget being shared. Dumped
 * to STATS.TXT at cleanup. */
static unsigned long long st_t0, st_present, st_isr;
static long st_frames, st_reb_now, st_reb_def, st_isr_calls;
static uclock_t st_u0;
static int st_on;
static unsigned long long rdtsc(void);
/* Accumulate a timing delta, discarding garbage: DOSBox's rdtsc is
 * derived from the emulated cycle counter, and with cycles=max the
 * auto-tuning can rescale it so a later read comes out BEHIND an
 * earlier one — one wrapped (negative) delta then dwarfs the real
 * total. Skip anything negative or absurdly large (>1s of cycles). */
static void st_add(unsigned long long *acc, unsigned long long t_in) {
    long long d = (long long)(rdtsc() - t_in);
    if (d >= 0 && d < 1000000000LL) *acc += (unsigned long long)d;
}

static unsigned long long rdtsc(void) {
    unsigned long lo, hi;
    __asm__ __volatile__ ("rdtsc" : "=a" (lo), "=d" (hi));
    return ((unsigned long long)hi << 32) | lo;
}
static void st_dump(void) {
    if (!st_on || !st_frames) return;
    FILE *f = fopen("STATS.TXT", "w");
    if (!f) return;
    unsigned long long total = rdtsc() - st_t0;
    double wall_s = (double)(uclock() - st_u0) / UCLOCKS_PER_SEC;
    fprintf(f, "frames=%ld rebuilds_now=%ld rebuilds_deferred=%ld isr_calls=%ld\n",
            st_frames, st_reb_now, st_reb_def, st_isr_calls);
    fprintf(f, "wall=%.1fs present_fps=%.1f\n", wall_s,
            wall_s > 0.0 ? st_frames / wall_s : 0.0);
    fprintf(f, "present_share=%.1f%% isr_share=%.1f%% (of emulated cycles)\n",
            100.0 * (double)st_present / (double)total,
            100.0 * (double)st_isr / (double)total);
    fprintf(f, "present_avg_kcyc=%.0f isr_avg_kcyc=%.0f\n",
            st_frames ? (double)st_present / st_frames / 1000.0 : 0.0,
            st_isr_calls ? (double)st_isr / st_isr_calls / 1000.0 : 0.0);
    fclose(f);
}

static void dos_cleanup(void) {
    sb_shutdown();
    kb_remove();
    if (vid_active) { set_mode(0x03); vid_active = 0; }
    st_dump();
}

static void on_abort(int sig) {
    (void)sig;
    dos_cleanup();
    signal(SIGABRT, SIG_DFL);
    raise(SIGABRT);
}

/* ------------------------------------------------------------------ */
/* SDL surface                                                         */
/* ------------------------------------------------------------------ */

static int dummy_window, dummy_renderer;
static struct { const void *pixels; int32_t pitch, w, h; int live; } tex0;

int32_t SDL_Init(uint32_t flags) {
    if (flags == SDL_INIT_AUDIO) {
        sb_parse_blaster();
        sb_present = sb_reset();
        return sb_present ? 0 : -1;            /* no SB: game runs silent */
    }
    static int hooked;
    if (!hooked) {
        atexit(dos_cleanup); signal(SIGABRT, on_abort); hooked = 1;
        const char *sv = getenv("WOLFDOS_STATS");
        if (sv && *sv == '1') { st_on = 1; st_t0 = rdtsc(); st_u0 = uclock(); }
    }
    return 0;
}
void SDL_Quit(void) { dos_cleanup(); }
int32_t SDL_SetHint(const char *n, const char *v) { (void)n; (void)v; return 0; }
char *SDL_GetError(void) { return (char *)"dosvga: no further detail"; }

/* Display: report 4:3 (mode 13h on a CRT), so Hor+ picks fb_w = 320. */
int32_t SDL_GetNumVideoDisplays(void) { return 1; }
int32_t SDL_GetDisplayBounds(int32_t i, SDL_Rect *r) {
    (void)i; r->x = 0; r->y = 0; r->w = 320; r->h = 240; return 0;
}
int32_t SDL_GetDisplayUsableBounds(int32_t i, SDL_Rect *r) {
    return SDL_GetDisplayBounds(i, r);
}
int32_t SDL_GetWindowDisplayIndex(void *w) { (void)w; return 0; }
int32_t SDL_GetCurrentDisplayMode(int32_t i, void *mode) {
    (void)i;
    struct { uint32_t format; int32_t w, h, refresh_rate; void *driverdata; } m =
        { 0, 320, 240, 70, NULL };             /* mode 13h refreshes at 70 Hz */
    memcpy(mode, &m, sizeof m);
    return 0;
}
char *SDL_GetCurrentVideoDriver(void) { return (char *)"dosvga"; }

void *SDL_CreateWindow(const char *t, int32_t x, int32_t y, int32_t w, int32_t h, uint32_t f) {
    (void)t; (void)x; (void)y; (void)w; (void)h; (void)f;
    kb_install();
    set_mode(0x13);
    vid_active = 1;
    pal_used = 0;
    memset(q_state, 0, sizeof q_state);
    memset(vga_shadow, 0, sizeof vga_shadow);
    q_ntouched = 0; q_miss_px = 0; q_miss_streak = 0;
    q_cooldown = 0; q_dac_dirty = 0;
    quantize(0xFF000000u);                     /* slot 0 = black */
    return &dummy_window;
}
void SDL_DestroyWindow(void *w) { (void)w; dos_cleanup(); }
void SDL_SetWindowTitle(void *w, const char *t) { (void)w; (void)t; }
int32_t SDL_SetWindowFullscreen(void *w, uint32_t f) { (void)w; (void)f; return 0; }
void SDL_GetWindowSize(void *w, int32_t *ww, int32_t *hh) {
    (void)w; if (ww) *ww = 320; if (hh) *hh = 240;
}
void SDL_SetWindowSize(void *w, int32_t ww, int32_t hh) { (void)w; (void)ww; (void)hh; }
void SDL_SetWindowPosition(void *w, int32_t x, int32_t y) { (void)w; (void)x; (void)y; }
void SDL_SetWindowBordered(void *w, int32_t b) { (void)w; (void)b; }
void SDL_SetWindowResizable(void *w, int32_t b) { (void)w; (void)b; }
void SDL_MaximizeWindow(void *w) { (void)w; }
void SDL_RestoreWindow(void *w) { (void)w; }
int32_t SDL_ShowCursor(int32_t s) { (void)s; return 0; }

void *SDL_CreateRenderer(void *w, int32_t i, uint32_t f) {
    (void)w; (void)i; (void)f; return &dummy_renderer;
}
void SDL_DestroyRenderer(void *r) { (void)r; }
int32_t SDL_GetRendererInfo(void *r, SDL_RendererInfo *info) {
    (void)r;
    memset(info, 0, sizeof *info);
    info->name = (void *)"dosvga";
    info->flags = SDL_RENDERER_SOFTWARE;
    return 0;
}
int32_t SDL_RenderSetLogicalSize(void *r, int32_t w, int32_t h) {
    (void)r; (void)w; (void)h; return 0;
}
int32_t SDL_GetRendererOutputSize(void *r, int32_t *w, int32_t *h) {
    (void)r; if (w) *w = 320; if (h) *h = 200; return 0;
}
int32_t SDL_SetRenderDrawColor(void *r, uint8_t rr, uint8_t g, uint8_t b, uint8_t a) {
    (void)r; (void)rr; (void)g; (void)b; (void)a; return 0;
}
int32_t SDL_SetRenderDrawBlendMode(void *r, int32_t m) { (void)r; (void)m; return 0; }
int32_t SDL_RenderClear(void *r) {
    (void)r; memset(vga_shadow, 0, sizeof vga_shadow); return 0;
}
int32_t SDL_RenderFillRect(void *r, const SDL_Rect *rc) { (void)r; (void)rc; return 0; }
int32_t SDL_RenderDrawRect(void *r, const SDL_Rect *rc) { (void)r; (void)rc; return 0; }
int32_t SDL_RenderDrawLine(void *r, int32_t a, int32_t b, int32_t c, int32_t d) {
    (void)r; (void)a; (void)b; (void)c; (void)d; return 0;
}
int32_t SDL_RenderDrawPoint(void *r, int32_t a, int32_t b) { (void)r; (void)a; (void)b; return 0; }

void *SDL_CreateTexture(void *r, uint32_t f, int32_t a, int32_t w, int32_t h) {
    (void)r; (void)f; (void)a;
    tex0.w = w; tex0.h = h; tex0.pixels = NULL; tex0.pitch = 0; tex0.live = 1;
    return &tex0;
}
void SDL_DestroyTexture(void *t) { (void)t; tex0.live = 0; tex0.pixels = NULL; }
int32_t SDL_UpdateTexture(void *t, void *rc, const void *px, int32_t pitch) {
    (void)t; (void)rc;
    tex0.pixels = px;                          /* dbuf persists between frames */
    tex0.pitch = pitch;
    return 0;
}
int32_t SDL_RenderCopy(void *r, void *t, void *s, void *d) {
    (void)r; (void)t; (void)s; (void)d; return 0;
}

void SDL_RenderPresent(void *r) {
    (void)r;
    if (!vid_active || !tex0.live || !tex0.pixels || tex0.w <= 0 || tex0.h <= 0)
        return;
    unsigned long long st_in = st_on ? rdtsc() : 0;
    q_miss_px = 0;
    /* Point-sample the game's screen_w x screen_h ARGB buffer down to
     * 320x200 (identity at scale 1). */
    int xstep = tex0.w / 320;  if (xstep < 1) xstep = 1;
    int ystep = tex0.h / 200;  if (ystep < 1) ystep = 1;
    int stride = tex0.pitch / 4;
    const uint32_t *src = (const uint32_t *)tex0.pixels;
    unsigned char *dst = vga_shadow;
    for (int y = 0; y < 200; y++) {
        const uint32_t *row = src + (size_t)(y * ystep) * stride;
        for (int x = 0; x < 320; x++)
            *dst++ = quantize(row[x * xstep]);
    }
    /* Rebuild policy, two regimes:
     *
     * Wholesale change (> 12.5% of pixels missed — only a full-screen
     * blend does that: damage flash, death stipple, a fade): rebuild
     * from THIS frame's histogram right now and re-quantize the frame
     * against its own fresh palette, so even the first frame of a flash
     * displays with colors chosen for it — no one-frame lag, no rainbow
     * speckle. The threshold is deliberately high: the immediate path
     * costs a double quantize plus a full DAC reprogram (768 port
     * writes — expensive under emulation), and a lower cut once let
     * muzzle flashes and door reveals trip it many times a second in
     * combat, starving the audio ISR of emulated CPU. Moderate changes
     * belong to the drift path below — their few distinct sprite-art
     * colors land in spare slots or match closely, unlike a blend's
     * thousands of fresh colors.
     *
     * Drift (> ~1.5% for 3 consecutive frames, 16-frame cooldown): the
     * gentle deferred path for scene changes. A stable scene that fits
     * the palette never trips either regime. */
    if (q_cooldown > 0) q_cooldown--;
    int rebuild = 0;
    if (q_miss_px > (320L * 200L) / 8) {
        st_reb_now++;
        rebuild = 1;                   /* wholesale change: no cooldown */
        q_miss_streak = 0;
        q_cooldown = 0;
    } else if (q_miss_px > (320L * 200L) / 64) {
        if (++q_miss_streak >= 3 && q_cooldown == 0) {
            st_reb_def++;
            rebuild = 1;               /* sustained drift */
            q_miss_streak = 0;
            q_cooldown = 16;
        }
    } else {
        q_miss_streak = 0;
    }
    if (rebuild) {
        palette_histogram(src, stride, xstep, ystep);
        palette_rebuild();
        dst = vga_shadow;
        for (int y = 0; y < 200; y++) {
            const uint32_t *row = src + (size_t)(y * ystep) * stride;
            for (int x = 0; x < 320; x++)
                *dst++ = quantize_map(row[x * xstep], 0);
        }
    }
    if (st_on) {
        st_add(&st_present, st_in);
        st_frames++;
        if ((st_frames & 255) == 0) st_dump();   /* survive unclean exits */
    }
    vga_wait_vsync();
    if (q_dac_dirty) {
        vga_write_dac_all();
        q_dac_dirty = 0;
    }
    dosmemput(vga_shadow, sizeof vga_shadow, 0xA0000);
}

/* ------------------------------------------------------------------ */
/* Audio: absent by design (wolf-fc runs silent when driver == NULL)   */
/* ------------------------------------------------------------------ */

/* Sound Blaster 16, 16-bit signed stereo auto-init DMA at 8000 Hz.
 *
 * Rate: the game asks the backend for its preferred rate (via
 * SDL_GetDefaultAudioInfo) and runs its whole mixer at whatever we say.
 * The OPL2 music emulator costs ~18 us of emulated CPU per sample under
 * DOSBox (measured with --test audiobench:), so 8000 Hz keeps the mix at
 * ~15% of the CPU — 44100 would eat more than all of it.
 *
 * Delivery: a 2-half auto-init DMA loop in DOS memory. The DSP raises the
 * SB IRQ at each half-buffer boundary; the ISR calls the game's SDL-style
 * callback to synthesize the next half (~2-3 ms every 16 ms) and copies it
 * into the finished half while the other one plays. The callback is
 * designed for exactly this (it is the sole mutator of audio state; the
 * main loop only posts to a lock-free command ring), so no locking beyond
 * the ISR context itself is needed. Pausing keeps the DMA loop running and
 * feeds it silence — simpler than stopping the DSP, and restart-glitch-free. */

#define SB_RATE        8000
#define SB_HALF_FRAMES 128                       /* 16 ms per half */
#define SB_HALF_BYTES  (SB_HALF_FRAMES * 4)      /* s16 stereo */

static int sb_base = 0x220, sb_irq = 7, sb_dma16 = 5;
static int sb_opened, sb_started, sb_paused = 1;   /* sb_present declared above */
static void (*sb_cb)(void *, unsigned char *, int32_t);
static void *sb_ud;
static int sb_dos_sel = -1;                      /* DOS-memory selector */
static unsigned long sb_phys;                    /* DMA buffer physical addr */
static int sb_half;                              /* half to refill next */
static unsigned char sb_mix[SB_HALF_BYTES];
static _go32_dpmi_seginfo sb_old_isr, sb_new_isr;
static int sb_isr_installed;

static void sb_dsp_write(int v) {
    for (int t = 0; t < 65536 && (inportb(sb_base + 0xC) & 0x80); t++) ;
    outportb(sb_base + 0xC, (unsigned char)v);
}

static int sb_reset(void) {
    outportb(sb_base + 0x6, 1);
    for (volatile int i = 0; i < 200; i++) ;     /* >= 3 us */
    outportb(sb_base + 0x6, 0);
    for (int t = 0; t < 65536; t++)
        if (inportb(sb_base + 0xE) & 0x80)
            return inportb(sb_base + 0xA) == 0xAA;
    return 0;
}

/* BLASTER=A220 I7 D1 H5 T6 — DOSBox exports it; real installs set it too.
 * We need A (base), I (IRQ), and H (16-bit DMA channel). */
static void sb_parse_blaster(void) {
    const char *e = getenv("BLASTER");
    if (!e) return;
    for (; *e; e++) {
        if (*e == 'A' || *e == 'a') sb_base = (int)strtol(e + 1, NULL, 16);
        else if (*e == 'I' || *e == 'i') sb_irq = (int)strtol(e + 1, NULL, 10);
        else if (*e == 'H' || *e == 'h') sb_dma16 = (int)strtol(e + 1, NULL, 10);
    }
}

static void sb_fill_half(int half) {
    if (sb_paused || !sb_cb) memset(sb_mix, 0, sizeof sb_mix);
    else sb_cb(sb_ud, sb_mix, (int32_t)sizeof sb_mix);
    dosmemput(sb_mix, sizeof sb_mix, sb_phys + (unsigned long)half * SB_HALF_BYTES);
}

static void sb_isr(void) {
    outportb(sb_base + 0x4, 0x82);               /* mixer: IRQ status reg */
    if (inportb(sb_base + 0x5) & 0x02) {         /* 16-bit DMA IRQ = ours */
        inportb(sb_base + 0xF);                  /* ack 16-bit transfer */
        /* The game's mixer is f64-heavy FC code, and the iret wrapper
         * saves only the integer registers — without saving the x87
         * state too, the mixer's float instructions corrupt whatever
         * f64 computation the interrupt landed in (the raycaster works
         * column-at-a-time, so the symptom is transient vertical glitch
         * stripes). fnsave stores the interrupted context's full FPU
         * state AND reinitializes the FPU, handing the callback a clean
         * stack; frstor puts the interrupted math back exactly as it
         * was. ISRs don't nest (IF stays clear), so one static save
         * area is enough. */
        static unsigned char sb_fpu[112];
        unsigned long long st_in = st_on ? rdtsc() : 0;
        __asm__ __volatile__ ("fnsave %0" : "=m" (sb_fpu) :: "memory");
        sb_fill_half(sb_half);
        sb_half ^= 1;
        __asm__ __volatile__ ("frstor %0" : : "m" (sb_fpu) : "memory");
        if (st_on) { st_add(&st_isr, st_in); st_isr_calls++; }
    }
    if (sb_irq >= 8) outportb(0xA0, 0x20);
    outportb(0x20, 0x20);
}

static void sb_start(void) {
    /* Prime both halves, then arm the DMA loop and the DSP. */
    sb_fill_half(0);
    sb_fill_half(1);
    sb_half = 0;
    int ch = sb_dma16 & 3;                       /* channel on the 2nd 8237 */
    int abase = 0xC0 + ch * 4;
    int pagereg = ch == 1 ? 0x8B : ch == 2 ? 0x89 : 0x8A;
    unsigned waddr = (unsigned)((sb_phys >> 1) & 0xFFFF);
    unsigned words = SB_HALF_FRAMES * 2 * 2 - 1; /* both halves, 16-bit words - 1 */
    outportb(0xD4, 0x04 | ch);                   /* mask channel */
    outportb(0xD8, 0);                           /* clear flip-flop */
    outportb(0xD6, 0x58 | ch);                   /* single, auto-init, playback */
    outportb(abase, waddr & 0xFF);
    outportb(abase, (waddr >> 8) & 0xFF);
    outportb(pagereg, (unsigned char)((sb_phys >> 16) & 0xFF));
    outportb(abase + 2, words & 0xFF);
    outportb(abase + 2, (words >> 8) & 0xFF);
    outportb(0xD4, ch);                          /* unmask */
    sb_dsp_write(0x41);                          /* set output rate */
    sb_dsp_write((SB_RATE >> 8) & 0xFF);
    sb_dsp_write(SB_RATE & 0xFF);
    sb_dsp_write(0xB6);                          /* 16-bit auto-init DAC, FIFO */
    sb_dsp_write(0x30);                          /* mode: signed stereo */
    unsigned blk = SB_HALF_FRAMES * 2 - 1;       /* IRQ block: one half, in words */
    sb_dsp_write(blk & 0xFF);
    sb_dsp_write((blk >> 8) & 0xFF);
    sb_started = 1;
}

static void sb_shutdown(void) {
    if (sb_started) {
        sb_reset();                              /* stops DSP + IRQs */
        outportb(0xD4, 0x04 | (sb_dma16 & 3));   /* mask DMA channel */
        sb_started = 0;
    }
    if (sb_isr_installed) {
        int vec = sb_irq < 8 ? 8 + sb_irq : 0x70 + (sb_irq - 8);
        _go32_dpmi_set_protected_mode_interrupt_vector(vec, &sb_old_isr);
        _go32_dpmi_free_iret_wrapper(&sb_new_isr);
        sb_isr_installed = 0;
    }
    if (sb_dos_sel >= 0) {
        __dpmi_free_dos_memory(sb_dos_sel);
        sb_dos_sel = -1;
    }
    sb_opened = 0;
}

uint32_t SDL_OpenAudioDevice(void *n, int32_t c, const SDL_AudioSpec *want, SDL_AudioSpec *have, int32_t g) {
    (void)n; (void)c; (void)g;
    if (!sb_present || sb_opened || !want || !want->callback) return 0;
    /* DMA buffer in DOS memory. 16-bit DMA must not cross a 128 KB bank;
     * allocate double and use whichever aligned half fits (the buffer is
     * only 1 KB, so one of them always does). */
    int sel = 0;
    int seg = __dpmi_allocate_dos_memory((2 * SB_HALF_BYTES * 2 + 15) / 16, &sel);
    if (seg < 0) return 0;
    sb_dos_sel = sel;
    sb_phys = (unsigned long)seg << 4;
    unsigned long in_bank = sb_phys & 0x1FFFF;
    if (in_bank + 2 * SB_HALF_BYTES > 0x20000)
        sb_phys += 0x20000 - in_bank;
    /* SB IRQ handler (iret wrapper, same pattern as the keyboard hook). */
    int vec = sb_irq < 8 ? 8 + sb_irq : 0x70 + (sb_irq - 8);
    _go32_dpmi_get_protected_mode_interrupt_vector(vec, &sb_old_isr);
    sb_new_isr.pm_offset = (unsigned long)sb_isr;
    sb_new_isr.pm_selector = _go32_my_cs();
    if (_go32_dpmi_allocate_iret_wrapper(&sb_new_isr) != 0) {
        __dpmi_free_dos_memory(sb_dos_sel); sb_dos_sel = -1;
        return 0;
    }
    _go32_dpmi_set_protected_mode_interrupt_vector(vec, &sb_new_isr);
    sb_isr_installed = 1;
    /* Unmask at the PIC (and the cascade for slave IRQs). */
    if (sb_irq < 8) {
        outportb(0x21, inportb(0x21) & ~(1 << sb_irq));
    } else {
        outportb(0xA1, inportb(0xA1) & ~(1 << (sb_irq - 8)));
        outportb(0x21, inportb(0x21) & ~(1 << 2));
    }
    sb_cb = (void (*)(void *, unsigned char *, int32_t))want->callback;
    sb_ud = want->userdata;
    if (have) {
        have->freq = SB_RATE;
        have->format = AUDIO_S16SYS;
        have->channels = 2;
        have->silence = 0;
        have->samples = SB_HALF_FRAMES;
        have->padding = 0;
        have->size = SB_HALF_BYTES;
        have->callback = want->callback;
        have->userdata = want->userdata;
    }
    sb_paused = 1;                               /* SDL devices open paused */
    sb_opened = 1;
    return 2;                                    /* SDL device ids start at 2 */
}

void SDL_PauseAudioDevice(uint32_t d, int32_t p) {
    (void)d;
    if (!sb_opened) return;
    sb_paused = p ? 1 : 0;
    if (!sb_paused && !sb_started) sb_start();
}

void SDL_CloseAudioDevice(uint32_t d) { (void)d; sb_shutdown(); }

const char *SDL_GetCurrentAudioDriver(void) {
    return sb_present ? "dossb16" : NULL;
}

int32_t SDL_GetDefaultAudioInfo(void *n, SDL_AudioSpec *s, int32_t c) {
    (void)n; (void)c;
    if (!sb_present || !s) return -1;
    memset(s, 0, sizeof *s);
    s->freq = SB_RATE;
    s->format = AUDIO_S16SYS;
    s->channels = 2;
    return 0;
}
