/* Inert definitions for the SDL2 stub — wolf-fc --test mode never calls these.
 * Anything that could be a divisor or get printed returns a safe value. */
#include "SDL2/SDL.h"
#include <stddef.h>

int32_t SDL_Init(uint32_t flags) { (void)flags; return -1; }
void SDL_Quit(void) {}
int32_t SDL_SetHint(const char *n, const char *v) { (void)n; (void)v; return 0; }
int32_t SDL_GetNumVideoDisplays(void) { return 0; }
int32_t SDL_GetDisplayBounds(int32_t i, SDL_Rect *r) { (void)i; (void)r; return -1; }
int32_t SDL_GetDisplayUsableBounds(int32_t i, SDL_Rect *r) { (void)i; (void)r; return -1; }
int32_t SDL_GetWindowDisplayIndex(void *w) { (void)w; return 0; }
int32_t SDL_GetCurrentDisplayMode(int32_t i, void *m) { (void)i; (void)m; return -1; }
char *SDL_GetCurrentVideoDriver(void) { return (char *)"dos-stub"; }
char *SDL_GetError(void) { return (char *)"sdl stubbed out (dos)"; }
void *SDL_CreateWindow(const char *t, int32_t x, int32_t y, int32_t w, int32_t h, uint32_t f) {
    (void)t;(void)x;(void)y;(void)w;(void)h;(void)f; return NULL; }
void SDL_DestroyWindow(void *w) { (void)w; }
void SDL_SetWindowTitle(void *w, const char *t) { (void)w; (void)t; }
int32_t SDL_SetWindowFullscreen(void *w, uint32_t f) { (void)w; (void)f; return -1; }
void SDL_GetWindowSize(void *w, int32_t *ww, int32_t *hh) { (void)w; if (ww) *ww = 0; if (hh) *hh = 0; }
void SDL_SetWindowSize(void *w, int32_t ww, int32_t hh) { (void)w;(void)ww;(void)hh; }
void SDL_SetWindowPosition(void *w, int32_t x, int32_t y) { (void)w;(void)x;(void)y; }
void SDL_SetWindowBordered(void *w, int32_t b) { (void)w;(void)b; }
void SDL_SetWindowResizable(void *w, int32_t b) { (void)w;(void)b; }
void SDL_MaximizeWindow(void *w) { (void)w; }
void SDL_RestoreWindow(void *w) { (void)w; }
int32_t SDL_ShowCursor(int32_t s) { (void)s; return 0; }
void *SDL_CreateRenderer(void *w, int32_t i, uint32_t f) { (void)w;(void)i;(void)f; return NULL; }
void SDL_DestroyRenderer(void *r) { (void)r; }
int32_t SDL_GetRendererInfo(void *r, SDL_RendererInfo *info) { (void)r;(void)info; return -1; }
int32_t SDL_RenderSetLogicalSize(void *r, int32_t w, int32_t h) { (void)r;(void)w;(void)h; return -1; }
int32_t SDL_GetRendererOutputSize(void *r, int32_t *w, int32_t *h) {
    (void)r; if (w) *w = 0; if (h) *h = 0; return -1; }
int32_t SDL_SetRenderDrawColor(void *r, uint8_t rr, uint8_t g, uint8_t b, uint8_t a) {
    (void)r;(void)rr;(void)g;(void)b;(void)a; return 0; }
int32_t SDL_SetRenderDrawBlendMode(void *r, int32_t m) { (void)r;(void)m; return 0; }
int32_t SDL_RenderClear(void *r) { (void)r; return 0; }
int32_t SDL_RenderFillRect(void *r, const SDL_Rect *rc) { (void)r;(void)rc; return 0; }
int32_t SDL_RenderDrawRect(void *r, const SDL_Rect *rc) { (void)r;(void)rc; return 0; }
int32_t SDL_RenderDrawLine(void *r, int32_t a, int32_t b, int32_t c, int32_t d) { (void)r;(void)a;(void)b;(void)c;(void)d; return 0; }
int32_t SDL_RenderDrawPoint(void *r, int32_t a, int32_t b) { (void)r;(void)a;(void)b; return 0; }
void SDL_RenderPresent(void *r) { (void)r; }
void *SDL_CreateTexture(void *r, uint32_t f, int32_t a, int32_t w, int32_t h) {
    (void)r;(void)f;(void)a;(void)w;(void)h; return NULL; }
void SDL_DestroyTexture(void *t) { (void)t; }
int32_t SDL_UpdateTexture(void *t, void *rc, const void *px, int32_t pitch) {
    (void)t;(void)rc;(void)px;(void)pitch; return 0; }
int32_t SDL_RenderCopy(void *r, void *t, void *s, void *d) { (void)r;(void)t;(void)s;(void)d; return 0; }
void SDL_Delay(uint32_t ms) { (void)ms; }
uint32_t SDL_GetTicks(void) { return 0; }
uint64_t SDL_GetPerformanceCounter(void) { return 0; }
uint64_t SDL_GetPerformanceFrequency(void) { return 1000000; }
uint32_t SDL_OpenAudioDevice(void *n, int32_t c, const SDL_AudioSpec *w, SDL_AudioSpec *h, int32_t g) {
    (void)n;(void)c;(void)w;(void)h;(void)g; return 0; }
void SDL_PauseAudioDevice(uint32_t d, int32_t p) { (void)d;(void)p; }
void SDL_CloseAudioDevice(uint32_t d) { (void)d; }
const char *SDL_GetCurrentAudioDriver(void) { return NULL; }
int32_t SDL_GetDefaultAudioInfo(void *n, SDL_AudioSpec *s, int32_t c) { (void)n;(void)s;(void)c; return -1; }
int32_t SDL_PollEvent(SDL_Event *e) { (void)e; return 0; }
void SDL_PumpEvents(void) {}
