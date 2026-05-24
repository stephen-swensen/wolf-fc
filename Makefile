# Wolf-FC build system. Mirrors the conventions in ../fc-lang/Makefile so
# users who installed `fcc` already recognise the shape (PREFIX / DESTDIR /
# OPT / CC). Build artifacts land in ./build/ — the FC source goes through
# fcc to produce one C file, then through cc to produce the final binary.
# `make check` runs the regression suite against an always-up-to-date
# binary because the suite depends on $(BIN) in the dep graph.

PREFIX  ?= /usr/local
DESTDIR ?=
bindir  := $(PREFIX)/bin
datadir := $(PREFIX)/share

CC      ?= cc
OPT     ?= -O2
CFLAGS   = -std=c11 -Wall -Werror -g $(OPT) $(EXTRA_DEFS)
LIBS     = $(EXTRA_LIBS) -lSDL2 -lm

# Platform-specific binary suffix + libs. Detect Windows two ways: $(OS)
# is "Windows_NT" in most shells, but some MSYS2 / MINGW / UCRT setups
# don't propagate it to make — fall back to looking for "_NT" anywhere
# in `uname -s` (which on every MSYS2-flavour shell returns something
# like MSYS_NT / MINGW64_NT / UCRT64_NT and never matches Linux/Darwin/
# *BSD). Either match flips on the .exe suffix + SDL2main shim.
UNAME_S := $(shell uname -s 2>/dev/null)
IS_WINDOWS := $(if $(filter Windows_NT,$(OS)),1,)$(if $(findstring _NT,$(UNAME_S)),1,)

ifneq ($(IS_WINDOWS),)
    EXE         = .exe
    EXTRA_DEFS  = -Dmain=SDL_main
    EXTRA_LIBS  = -lmingw32 -lSDL2main
    # windres compiles wolf-fc.rc into a COFF object that's linked into
    # the .exe to embed the application icon (Explorer / Alt-Tab / taskbar).
    WIN_RC      = packaging/wolf-fc.rc
    WIN_ICO     = packaging/icon/wolf-fc.ico
endif

# Per-OS build subdirectory. Lets a single source tree shared across two
# operating systems (e.g. WSL Linux + MSYS2 on the same Windows box,
# accessing the WSL filesystem via //wsl.localhost/...) hold both binaries
# without one stomping the other's mtimes — without this, `make` on the
# second OS sees an "up-to-date" binary built for the first OS and refuses
# to rebuild, then `./run.sh` exec's it and dies with "Exec format error".
ifneq ($(IS_WINDOWS),)
    BUILD_OS := windows
else ifeq ($(UNAME_S),Darwin)
    BUILD_OS := macos
else ifeq ($(UNAME_S),Linux)
    BUILD_OS := linux
else
    BUILD_OS := $(UNAME_S)
endif
BUILD_DIR := build/$(BUILD_OS)

# Where `make install` puts the WL6 data files (when ./data/ is present
# at install time). Baked into the binary at build time via $(GEN_FC) so
# the installed `wolf-fc` knows where to look without any wrapper script.
INSTALL_DATA_DIR := $(datadir)/wolf-fc/data

# On Windows the binary's fopen() is a C-runtime call that doesn't know
# about MSYS2's POSIX-style mounts (`/usr/local/...`). Translate the
# baked path to a Windows-style mixed path (`C:/msys64/usr/local/...`)
# via cygpath -m. The translated form is what gets baked into
# install_path.fc; `make install` itself still uses the POSIX path for
# `install -d` / `install -m` (which DO understand the mounts).
ifneq ($(IS_WINDOWS),)
    BAKED_DATA_DIR := $(shell cygpath -m '$(INSTALL_DATA_DIR)' 2>/dev/null || echo '$(INSTALL_DATA_DIR)')
else
    BAKED_DATA_DIR := $(INSTALL_DATA_DIR)
endif

BIN    := $(BUILD_DIR)/wolf-fc$(EXE)
GEN_C  := $(BUILD_DIR)/wolf-fc.c
GEN_FC := $(BUILD_DIR)/install_path.fc
ifneq ($(IS_WINDOWS),)
    WIN_RES := $(BUILD_DIR)/wolf-fc-res.o
endif

# Source list. Order doesn't matter to fcc, but keep main.fc last for
# readability — it's the entry point.
SRCS_FC := sdl2.fc opl2.fc sound.fc png.fc data.fc \
           sfx.fc ui.fc save.fc combat.fc level.fc cutscenes.fc \
           menu.fc player.fc render.fc main.fc

# Stdlib resolution: derive from `fcc`'s install prefix on PATH (same logic
# the old run.sh used). Override with FCC_STDLIB if your layout is unusual.
ifeq ($(strip $(FCC_STDLIB)),)
    FCC_BIN     := $(shell command -v fcc 2>/dev/null)
    FCC_PREFIX  := $(patsubst %/bin,%,$(patsubst %/,%,$(dir $(FCC_BIN))))
    STDLIB_DIR  := $(FCC_PREFIX)/share/fcc/stdlib
else
    STDLIB_DIR  := $(FCC_STDLIB)
endif
SRCS_STDLIB := $(addprefix $(STDLIB_DIR)/,io.fc text.fc sys.fc math.fc random.fc)

.PHONY: all dev clean install uninstall check help print-bin print-version icon icon-check-deps installer

all: $(BIN)

# Echo the binary path. run.sh and tests/run-tests.sh use this so they
# don't have to replicate the OS-detection logic — `make print-bin`
# returns build/<os>/wolf-fc[.exe] for whichever OS Make was invoked on.
print-bin:
	@echo $(BIN)

# Version derived from the latest commit's UTC date + half-seconds-since-
# midnight: yy.mm.dd.SS where SS = (commit_unixtime % 86400) / 2. The /2
# keeps the final part under 65535 so it fits the Windows FILEVERSION
# quad-int format. Falls back to 0.0.0.0 outside a git checkout (e.g.
# tarball builds) so the installer can still tag the artifact.
VERSION := $(shell ts=$$(git log -1 --format=%ct HEAD 2>/dev/null); \
  if [ -n "$$ts" ]; then \
    printf '%s.%d' "$$(date -u -d @$$ts +%y.%m.%d)" $$(( (ts % 86400) / 2 )); \
  else \
    echo '0.0.0.0'; \
  fi)

print-version:
	@echo $(VERSION)

$(BIN): $(GEN_C) $(WIN_RES)
	$(CC) $(CFLAGS) -o $@ $(GEN_C) $(WIN_RES) $(LIBS)

ifneq ($(IS_WINDOWS),)
# windres's default preprocessor (gcc -E) is spawned via cmd.exe, which
# doesn't support UNC cwd (typical when MSYS2 builds against a WSL-side
# checkout) and re-roots itself to C:\Windows. cygpath -am gives absolute
# paths so the preprocessor and the -I include lookup both find their
# files regardless of cwd. The "UNC paths are not supported" warning
# still prints but the build completes.
#
# $(WIN_ICO) is an order-only prerequisite: existence-checked, not
# mtime-checked. The .ico is committed to the repo and the regular build
# path must not pull in rsvg-convert / ImageMagick; only `make icon`
# regenerates it. (See the MAKECMDGOALS gate around the icon rules below
# — that's what keeps make from chasing the inner SVG→PNG→ICO chain when
# fresh-clone mtime skew makes a prereq look newer than the .ico.)
$(WIN_RES): $(WIN_RC) | $(BUILD_DIR) $(WIN_ICO)
	windres -I "$$(cygpath -am packaging)" \
	        "$$(cygpath -am $(WIN_RC))" \
	        -O coff -o $@
endif

$(GEN_C): $(SRCS_FC) $(GEN_FC) | $(BUILD_DIR)
	@command -v fcc >/dev/null 2>&1 || { \
		echo "error: 'fcc' not found on PATH." >&2; \
		echo "Install from ../fc-lang/ with 'make && sudo make install'" >&2; \
		echo "(or 'make install PREFIX=\$$HOME/.local' for a user-local install)." >&2; \
		exit 1; \
	}
	@[ -d "$(STDLIB_DIR)" ] || { \
		echo "error: FC stdlib not found at '$(STDLIB_DIR)'." >&2; \
		echo "Reinstall fcc, or set FCC_STDLIB to the directory holding io.fc/text.fc/etc." >&2; \
		exit 1; \
	}
	fcc $(SRCS_FC) $(GEN_FC) $(SRCS_STDLIB) -o $@

# Bake the resolved install data dir into a generated FC module so the
# binary can fall back to it at run time. Depends on FORCE so the recipe
# always runs (Make can't track command-line PREFIX changes); the cmp +
# mv pattern keeps the file's mtime stable when the value hasn't actually
# changed, so downstream targets don't churn.
.PHONY: FORCE
FORCE:

$(GEN_FC): FORCE | $(BUILD_DIR)
	@printf 'module install_path =\n    let data_dir = "%s"\n' \
		"$(BAKED_DATA_DIR)" > $@.tmp
	@if cmp -s $@.tmp $@ 2>/dev/null; then rm $@.tmp; else mv $@.tmp $@; fi

$(BUILD_DIR):
	@mkdir -p $@

# `make dev` produces a no-optimisation debug build for fast iteration and
# clearer stack traces. Forces a clean first because Make can't track
# command-line OPT changes — without the clean you'd link new -O0 objects
# against stale -O2 ones (well, we have only one .o, but the principle
# holds for the .c emitted by fcc).
dev:
	@$(MAKE) clean
	@$(MAKE) OPT=-O0

clean:
	rm -rf build

install: $(BIN)
	install -d $(DESTDIR)$(bindir)
	install -m 755 $(BIN) $(DESTDIR)$(bindir)/wolf-fc$(EXE)
	@if ls data/*.WL6 >/dev/null 2>&1; then \
		install -d $(DESTDIR)$(INSTALL_DATA_DIR); \
		install -m 644 data/*.WL6 $(DESTDIR)$(INSTALL_DATA_DIR)/; \
		echo "installed data files to $(DESTDIR)$(INSTALL_DATA_DIR)/"; \
	else \
		echo "note: no ./data/*.WL6 found — install data manually to $(INSTALL_DATA_DIR)/"; \
		echo "      or set WOLF_FC_DATA_DIR at run time"; \
	fi

uninstall:
	rm -f $(DESTDIR)$(bindir)/wolf-fc$(EXE)
	rm -rf $(DESTDIR)$(datadir)/wolf-fc

check: $(BIN)
	bash tests/run-tests.sh

# ----------------------------------------------------------------------------
# Icon regeneration (runs only when packaging/icon/*.svg changes).
#
# Two SVG sources: wolf-fc.svg drives 48/64/128/256 (stacked "WOLF"/"FC"),
# wolf-fc-small.svg drives 16/32 (single-line "WFC" since the four-letter
# stacked mark smears at small raster sizes). The six PNGs are checked in
# alongside the multi-res .ico — contributors who don't change the icon
# never need rsvg-convert or imagemagick.
#
# Use ImageMagick 6 (`convert`) or 7 (`magick`), whichever is on PATH.
# ----------------------------------------------------------------------------

ICON_DIR        := packaging/icon
ICON_SVG        := $(ICON_DIR)/wolf-fc.svg
ICON_SVG_SMALL  := $(ICON_DIR)/wolf-fc-small.svg
ICON_ICO        := $(ICON_DIR)/wolf-fc.ico
ICON_PNGS       := $(ICON_DIR)/wolf-fc-16.png  $(ICON_DIR)/wolf-fc-32.png \
                   $(ICON_DIR)/wolf-fc-48.png  $(ICON_DIR)/wolf-fc-64.png \
                   $(ICON_DIR)/wolf-fc-128.png $(ICON_DIR)/wolf-fc-256.png

# The icon-generation rules are defined ONLY when `make icon` is explicitly
# requested. The .ico and PNGs are committed to the repo; the regular build
# path and `make installer` reference $(ICON_ICO) as an order-only
# prerequisite, but order-only blocks only the *outer* mtime comparison —
# if the .ico's own rule (and the PNGs' own rules) exist, make still walks
# them and re-runs imagemagick/rsvg-convert whenever a fresh clone's mtime
# skew makes a prereq look "newer". Hiding the rules behind MAKECMDGOALS
# means the regular build sees the .ico as a static checked-in file with
# no recipe, exactly as intended.
ifneq ($(filter icon,$(MAKECMDGOALS)),)

icon: icon-check-deps $(ICON_ICO)

icon-check-deps:
	@command -v rsvg-convert >/dev/null 2>&1 || { \
		echo "error: 'rsvg-convert' not found (apt install librsvg2-bin)" >&2; \
		exit 1; \
	}
	@command -v magick >/dev/null 2>&1 || command -v convert >/dev/null 2>&1 || { \
		echo "error: ImageMagick not found (apt install imagemagick)" >&2; \
		exit 1; \
	}

$(ICON_DIR)/wolf-fc-16.png: $(ICON_SVG_SMALL)
	rsvg-convert -w 16 -h 16 $< -o $@
$(ICON_DIR)/wolf-fc-32.png: $(ICON_SVG_SMALL)
	rsvg-convert -w 32 -h 32 $< -o $@
$(ICON_DIR)/wolf-fc-48.png: $(ICON_SVG)
	rsvg-convert -w 48 -h 48 $< -o $@
$(ICON_DIR)/wolf-fc-64.png: $(ICON_SVG)
	rsvg-convert -w 64 -h 64 $< -o $@
$(ICON_DIR)/wolf-fc-128.png: $(ICON_SVG)
	rsvg-convert -w 128 -h 128 $< -o $@
$(ICON_DIR)/wolf-fc-256.png: $(ICON_SVG)
	rsvg-convert -w 256 -h 256 $< -o $@

$(ICON_ICO): $(ICON_PNGS)
	$(if $(shell command -v magick 2>/dev/null),magick,convert) $(ICON_PNGS) $@

endif

# ----------------------------------------------------------------------------
# Windows installer build (MSYS2 UCRT64 only).
#
#   make installer
#     Builds wolf-fc.exe (transitively), then runs Inno Setup's iscc.exe
#     against packaging/wolf-fc.iss to produce dist/wolf-fc-setup-<ver>.exe.
#
# Inputs picked up automatically:
#   $(VERSION)  - timestamped from the latest commit (see print-version).
#   SDL2.dll    - the file shipped by mingw-w64-ucrt-x86_64-SDL2.
#                 Override with SDL2_DLL=/abs/path to a different copy.
#   iscc.exe    - default-installed by `winget install JRSoftware.InnoSetup`.
#                 Override with ISCC=/c/.../ISCC.exe if installed elsewhere.
# ----------------------------------------------------------------------------

ifneq ($(IS_WINDOWS),)

ISCC ?= /c/Program Files (x86)/Inno Setup 6/ISCC.exe
SDL2_DLL := $(shell pacman -Ql mingw-w64-ucrt-x86_64-SDL2 2>/dev/null \
            | awk '/SDL2\.dll$$/{print $$2; exit}')

DIST_DIR  := dist
INSTALLER := $(DIST_DIR)/wolf-fc-setup-$(VERSION).exe

installer: $(INSTALLER)

$(INSTALLER): $(BIN) packaging/wolf-fc.iss LICENSE README.md | $(DIST_DIR) $(ICON_ICO)
	@[ -n "$(SDL2_DLL)" ] || { \
		echo "error: SDL2.dll not found via pacman (install mingw-w64-ucrt-x86_64-SDL2 or set SDL2_DLL=)" >&2; \
		exit 1; \
	}
	@[ -x "$(ISCC)" ] || { \
		echo "error: ISCC.exe not found at $(ISCC)" >&2; \
		echo "Install Inno Setup ('winget install JRSoftware.InnoSetup') or set ISCC=/path/to/ISCC.exe" >&2; \
		exit 1; \
	}
	@# Pass paths via env vars (read in the .iss with GetEnv()) rather than
	@# /D defines: /D values get C-string-parsed by iscc, so backslashes in
	@# UNC paths (\\wsl.localhost\...) or native paths with \U etc. would
	@# need to be doubled. Env vars come through verbatim. Three small
	@# Windows / MSYS2 quirks to work around:
	@#   * MSYS2_ARG_CONV_EXCL='*' stops MSYS2 from path-mangling args
	@#     passed to native Windows binaries.
	@#   * The .iss positional must not begin with '/' (iscc reads it as
	@#     an unknown switch), so cygpath -w (backslashes) for that path.
	@#   * cygpath -w for the env-var values too, so iscc gets a form it
	@#     recognises as absolute (UNC or drive-letter, never POSIX).
	WOLFFC_VERSION='$(VERSION)' \
	WOLFFC_BIN="$$(cygpath -w $(abspath $(BIN)))" \
	WOLFFC_SDL2_DLL="$$(cygpath -w $(SDL2_DLL))" \
	MSYS2_ARG_CONV_EXCL='*' \
	"$(ISCC)" /Q "$$(cygpath -w $(abspath packaging/wolf-fc.iss))"

$(DIST_DIR):
	@mkdir -p $@

else

# Non-Windows stub so `make installer` on Linux/macOS prints a useful
# message instead of make's silent "Nothing to be done for 'installer'"
# (the target is .PHONY unconditionally, but the real recipe above is
# gated to MSYS2 UCRT64).
installer:
	@echo "error: 'make installer' is Windows-only — run from an MSYS2 UCRT64 shell." >&2
	@exit 1

endif

help:
	@echo "Targets:"
	@echo "  all (default) - build the binary at $(BIN)"
	@echo "  dev           - clean rebuild at -O0 with debug symbols"
	@echo "  clean         - remove build/ (every OS subdirectory)"
	@echo "  install       - install binary to \$$(PREFIX)/bin and (if present) data/*.WL6 to \$$(PREFIX)/share/wolf-fc/data/"
	@echo "  uninstall     - remove the installed binary and data tree"
	@echo "  check         - build the binary if needed, then run tests/run-tests.sh"
	@echo "  print-bin     - echo the per-OS binary path (used by run.sh / run-tests.sh)"
	@echo "  print-version - echo VERSION (yy.mm.dd.SS, derived from the latest commit)"
	@echo "  icon          - regenerate packaging/icon/*.png + wolf-fc.ico from the SVGs"
	@echo "  installer     - (MSYS2 UCRT64) build dist/wolf-fc-setup-\$$VERSION.exe via Inno Setup"
	@echo ""
	@echo "Variables:"
	@echo "  PREFIX        install root (default: /usr/local)"
	@echo "  DESTDIR       staging root for package builds (default: empty)"
	@echo "  OPT           optimization flags (default: -O2; 'make dev' uses -O0)"
	@echo "  CC            C compiler (default: cc)"
	@echo "  FCC_STDLIB    override the FC stdlib directory (default: derived from \$$(fcc) install prefix)"
