/* Minimal SDL2 stub for the wolf-fc DOS (djgpp) experiment.
 * wolf-fc's --test mode never touches SDL at runtime; this header + sdl_stub.c
 * exist only so the FC-emitted C compiles and links unchanged. Struct layouts
 * follow the FC extern declarations in src/sdl2.fc (this stub IS the ABI). */
#ifndef SDL_STUB_H
#define SDL_STUB_H
#include <stdint.h>

typedef struct SDL_Rect  { int32_t x, y, w, h; } SDL_Rect;
typedef struct SDL_Point { int32_t x, y; } SDL_Point;

typedef struct SDL_RendererInfo {
    void *name; uint32_t flags; uint32_t num_texture_formats;
    uint32_t texture_formats[16]; int32_t max_texture_width, max_texture_height;
} SDL_RendererInfo;

typedef struct SDL_AudioSpec {
    int32_t freq; uint16_t format; uint8_t channels, silence;
    uint16_t samples, padding; uint32_t size; void *callback; void *userdata;
} SDL_AudioSpec;

typedef struct SDL_Keysym { int32_t scancode, sym; uint16_t mod; } SDL_Keysym;
typedef struct SDL_KeyboardEvent { uint32_t type; uint8_t repeat; SDL_Keysym keysym; } SDL_KeyboardEvent;
typedef struct SDL_WindowEvent {
    uint32_t type, timestamp, windowID; uint8_t event, padding1, padding2, padding3;
    int32_t data1, data2;
} SDL_WindowEvent;
typedef union SDL_Event { uint32_t type; SDL_KeyboardEvent key; SDL_WindowEvent window; } SDL_Event;

#define SDL_INIT_VIDEO 0x20u
#define SDL_INIT_AUDIO 0x10u
#define SDL_WINDOW_SHOWN 0x4u
#define SDL_WINDOW_FULLSCREEN_DESKTOP 0x1001u
#define SDL_WINDOW_ALLOW_HIGHDPI 0x2000u
#define SDL_WINDOW_BORDERLESS 0x10u
#define SDL_WINDOW_RESIZABLE 0x20u
#define SDL_WINDOWPOS_CENTERED 0x2FFF0000
#define SDL_RENDERER_SOFTWARE 1u
#define SDL_RENDERER_ACCELERATED 2u
#define SDL_RENDERER_PRESENTVSYNC 4u
#define SDL_BLENDMODE_NONE 0
#define SDL_BLENDMODE_BLEND 1
#define SDL_BLENDMODE_ADD 2
#define SDL_QUIT 0x100
#define SDL_KEYDOWN 0x300
#define SDL_KEYUP 0x301
#define SDL_WINDOWEVENT 0x200
#define SDL_WINDOWEVENT_SIZE_CHANGED ((uint8_t)6)
#define SDL_PIXELFORMAT_ARGB8888 0x16362004u
#define SDL_TEXTUREACCESS_STREAMING 1
#define AUDIO_S16SYS ((uint16_t)0x8010)

#define SDLK_UP 1073741906
#define SDLK_DOWN 1073741905
#define SDLK_LEFT 1073741904
#define SDLK_RIGHT 1073741903
#define SDLK_ESCAPE 27
#define SDLK_SPACE 32
#define SDLK_RETURN 13
#define SDLK_BACKSPACE 8
#define SDLK_TAB 9
#define SDLK_PAGEUP 1073741899
#define SDLK_PAGEDOWN 1073741902
#define SDLK_LSHIFT 1073742049
#define SDLK_LALT 1073742050
#define SDLK_LCTRL 1073742048
#define SDLK_F11 1073741933
#define SDLK_a 97
#define SDLK_b 98
#define SDLK_c 99
#define SDLK_d 100
#define SDLK_e 101
#define SDLK_f 102
#define SDLK_g 103
#define SDLK_h 104
#define SDLK_i 105
#define SDLK_j 106
#define SDLK_k 107
#define SDLK_l 108
#define SDLK_m 109
#define SDLK_n 110
#define SDLK_o 111
#define SDLK_p 112
#define SDLK_q 113
#define SDLK_r 114
#define SDLK_s 115
#define SDLK_t 116
#define SDLK_u 117
#define SDLK_v 118
#define SDLK_w 119
#define SDLK_x 120
#define SDLK_y 121
#define SDLK_z 122
#define SDLK_0 48
#define SDLK_1 49
#define SDLK_2 50
#define SDLK_3 51
#define SDLK_4 52
#define SDLK_5 53
#define SDLK_6 54
#define SDLK_7 55
#define SDLK_8 56
#define SDLK_9 57

int32_t SDL_Init(uint32_t flags);
void SDL_Quit(void);
int32_t SDL_SetHint(const char *name, const char *value);
int32_t SDL_GetNumVideoDisplays(void);
int32_t SDL_GetDisplayBounds(int32_t i, SDL_Rect *r);
int32_t SDL_GetDisplayUsableBounds(int32_t i, SDL_Rect *r);
int32_t SDL_GetWindowDisplayIndex(void *w);
int32_t SDL_GetCurrentDisplayMode(int32_t i, void *mode);
char *SDL_GetCurrentVideoDriver(void);
char *SDL_GetError(void);
void *SDL_CreateWindow(const char *t, int32_t x, int32_t y, int32_t w, int32_t h, uint32_t f);
void SDL_DestroyWindow(void *w);
void SDL_SetWindowTitle(void *w, const char *t);
int32_t SDL_SetWindowFullscreen(void *w, uint32_t f);
void SDL_GetWindowSize(void *w, int32_t *ww, int32_t *hh);
void SDL_SetWindowSize(void *w, int32_t ww, int32_t hh);
void SDL_SetWindowPosition(void *w, int32_t x, int32_t y);
void SDL_SetWindowBordered(void *w, int32_t b);
void SDL_SetWindowResizable(void *w, int32_t b);
void SDL_MaximizeWindow(void *w);
void SDL_RestoreWindow(void *w);
int32_t SDL_ShowCursor(int32_t s);
void *SDL_CreateRenderer(void *w, int32_t i, uint32_t f);
void SDL_DestroyRenderer(void *r);
int32_t SDL_GetRendererInfo(void *r, SDL_RendererInfo *info);
int32_t SDL_RenderSetLogicalSize(void *r, int32_t w, int32_t h);
int32_t SDL_GetRendererOutputSize(void *r, int32_t *w, int32_t *h);
int32_t SDL_SetRenderDrawColor(void *r, uint8_t rr, uint8_t g, uint8_t b, uint8_t a);
int32_t SDL_SetRenderDrawBlendMode(void *r, int32_t m);
int32_t SDL_RenderClear(void *r);
int32_t SDL_RenderFillRect(void *r, const SDL_Rect *rc);
int32_t SDL_RenderDrawRect(void *r, const SDL_Rect *rc);
int32_t SDL_RenderDrawLine(void *r, int32_t a, int32_t b, int32_t c, int32_t d);
int32_t SDL_RenderDrawPoint(void *r, int32_t a, int32_t b);
void SDL_RenderPresent(void *r);
void *SDL_CreateTexture(void *r, uint32_t f, int32_t a, int32_t w, int32_t h);
void SDL_DestroyTexture(void *t);
int32_t SDL_UpdateTexture(void *t, void *rc, const void *px, int32_t pitch);
int32_t SDL_RenderCopy(void *r, void *t, void *s, void *d);
void SDL_Delay(uint32_t ms);
uint32_t SDL_GetTicks(void);
uint64_t SDL_GetPerformanceCounter(void);
uint64_t SDL_GetPerformanceFrequency(void);
uint32_t SDL_OpenAudioDevice(void *name, int32_t cap, const SDL_AudioSpec *want, SDL_AudioSpec *have, int32_t chg);
void SDL_PauseAudioDevice(uint32_t dev, int32_t p);
void SDL_CloseAudioDevice(uint32_t dev);
const char *SDL_GetCurrentAudioDriver(void);
int32_t SDL_GetDefaultAudioInfo(void *name, SDL_AudioSpec *spec, int32_t cap);
int32_t SDL_PollEvent(SDL_Event *e);
void SDL_PumpEvents(void);

#endif
