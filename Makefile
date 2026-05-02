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
endif

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

BIN    := build/wolf-fc$(EXE)
GEN_C  := build/wolf-fc.c
GEN_FC := build/install_path.fc

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

.PHONY: all dev clean install uninstall check help

all: $(BIN)

$(BIN): $(GEN_C)
	$(CC) $(CFLAGS) -o $@ $< $(LIBS)

$(GEN_C): $(SRCS_FC) $(GEN_FC) | build
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

$(GEN_FC): FORCE | build
	@printf 'module install_path =\n    let data_dir = "%s"\n' \
		"$(BAKED_DATA_DIR)" > $@.tmp
	@if cmp -s $@.tmp $@ 2>/dev/null; then rm $@.tmp; else mv $@.tmp $@; fi

build:
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

help:
	@echo "Targets:"
	@echo "  all (default) - build the binary at $(BIN)"
	@echo "  dev           - clean rebuild at -O0 with debug symbols"
	@echo "  clean         - remove build/"
	@echo "  install       - install binary to \$$(PREFIX)/bin and (if present) data/*.WL6 to \$$(PREFIX)/share/wolf-fc/data/"
	@echo "  uninstall     - remove the installed binary and data tree"
	@echo "  check         - build the binary if needed, then run tests/run-tests.sh"
	@echo ""
	@echo "Variables:"
	@echo "  PREFIX        install root (default: /usr/local)"
	@echo "  DESTDIR       staging root for package builds (default: empty)"
	@echo "  OPT           optimization flags (default: -O2; 'make dev' uses -O0)"
	@echo "  CC            C compiler (default: cc)"
	@echo "  FCC_STDLIB    override the FC stdlib directory (default: derived from \$$(fcc) install prefix)"
