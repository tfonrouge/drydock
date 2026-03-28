# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What Is This

This is a fork of the [Harbour compiler](https://github.com/harbour/core) under
the **Drydock** modernization initiative. Upstream: `https://github.com/harbour/core`.

Harbour is a multi-platform, multi-threading, object-oriented compiler and runtime
for the xBase/Clipper language family. It compiles `.prg` source files to pcode
(bytecode), then generates C code that links against the Harbour VM and runtime
libraries. See `doc/drydock/vision.md` for the modernization plan.

## Build Commands

```bash
# Zig build (recommended — produces drydock compiler + all C libraries)
zig build

# Zig build with cross-compilation
zig build -Dtarget=x86_64-windows-gnu

# Legacy Make build (full build including contribs)
make

# Make: compiler only (no contrib/RTL)
make HB_BUILD_PARTS=compiler

# Make: clean
make clean

# Make: debug build
make HB_BUILD_DEBUG=yes

# Make: build a specific subdirectory
cd src/rtl && make

# Make: build a specific contrib package
cd contrib && ddmake make.hb <name> [clean]

# Create drydock symlinks after Make build
bin/create-symlinks.sh
```

On Windows use `win-make`, on DOS use `dos-make`, on OS/2 use `os2-make`.

## Running Tests

```bash
# Run the test suite (after building)
bin/linux/gcc/ddtest

# Show all results (not just failures)
bin/linux/gcc/ddtest -all

# Compile and run a single .prg test
bin/linux/gcc/ddmake tests/hello.prg
```

The path `bin/linux/gcc/` varies by platform and compiler.

## Code Formatting

```bash
# C/H files — uses 3-space indentation, BSD-style braces
uncrustify -c bin/harbour.ucf <file.c>

# Harbour .prg/.hb/.ch files
bin/linux/gcc/ddformat <file.prg>

# Pre-commit validation (encoding, whitespace, filenames)
ddrun bin/check.hb
```

## Compilation Pipeline

```
.prg source
  → Preprocessor (src/pp/) — expands #command, #translate, #define from .ch headers
  → Parser (src/compiler/harbour.y) — LALR(1) Bison grammar
  → Pcode generation — bytecode emitted during parsing (no separate AST)
  → Optimizer (src/compiler/hbopt.c, hbdead.c) — peephole + dead code elimination
  → C code generator (src/compiler/genc.c) — outputs .c with embedded pcode arrays
  → C compiler (gcc/clang/msvc) → object files
  → Linker — links with VM + RTL + RDD libraries → executable
```

Alternative backend: `genhrb.c` produces portable `.hrb` bytecode files.

## Architecture

### Core Components (src/)

- **compiler/** — Harbour-to-C compiler. Grammar in `harbour.y`, lexer in `complex.c`, code generators in `genc.c`/`gencc.c`/`genhrb.c`, optimizer in `hbopt.c`.
- **vm/** — Stack-based virtual machine. `hvm.c` (12K lines) is the main execution loop — a giant switch over ~181 pcode opcodes. `classes.c` implements the OO system (multiple inheritance, operator overloading, scoping, delegation). `garbage.c` is mark-and-sweep GC. `itemapi.c` manages the `HB_ITEM` tagged union that represents all Harbour values.
- **rtl/** — Runtime library (~300 files). Built-in functions, file I/O, console, GT (General Terminal) drivers for different platforms.
- **rdd/** — Replaceable Database Drivers. Pluggable database backends (DBFNTX, DBFCDX, DBFFPT) behind a uniform API with `SELF_*` dispatch macros.
- **pp/** — Preprocessor. Handles `#command`, `#translate`, `#define`, `#include` directives.
- **macro/** — Runtime macro compiler. Compiles Harbour expressions to pcode at runtime.

### Key Data Structures

- **`HB_ITEM`** (`include/hbapi.h`) — Tagged union representing every Harbour value. Type field (`HB_TYPE`) + union of structs for each type (string, integer, long, double, array, hash, block, symbol, etc.). Check types with `HB_IS_STRING(p)`, `HB_IS_NUMERIC(p)`, etc.
- **`HB_BASEARRAY`** — Internal array/object representation. Objects are arrays with `uiClass != 0`.
- **`CLASS`/`METHOD`** (`src/vm/classes.c`) — Class registry with method dispatch tables, scoping, operator overloading symbols.
- **Pcode opcodes** (`include/hbpcode.h`) — `HB_P_*` constants for all VM instructions.

### How Objects Work

Objects are arrays tagged with a class ID (`HB_BASEARRAY.uiClass`). `HB_IS_OBJECT(p)` checks `HB_IS_ARRAY(p) && uiClass != 0`. Method dispatch goes through `hb_objGetMethod()` which looks up the class's method table via hash. The class system supports EXPORTED/PROTECTED/HIDDEN scoping, SYNC methods with mutex, delegation, and operator overloading via `__OP*` messages.

### How Operators Work in the VM

Each operator (e.g., `hb_vmPlus()` in `hvm.c`) is a cascade of type checks: integer fast path → numeric → string → datetime → object operator overload (`hb_objOperatorCall`) → error. There are 30 overloadable operators defined in `include/hbapicls.h`.

## Documentation

| Document | Purpose |
|----------|---------|
| `README.md` | Project overview, quick start, binary names |
| `doc/drydock/vision.md` | Drydock vision, workstreams, compatibility covenant |
| `doc/drydock/analysis.md` | Technical deep dive, code analysis, fracture map |
| `doc/drydock/oo-spec.md` | OO system spec — current features, gaps, target state, universal protocols |
| `doc/codestyl.txt` | Full C coding standards (summarized below) |
| `doc/vm.txt` | VM architecture reference |
| `doc/pcode.txt` | Pcode bytecode model |
| `blueprints/` | Per-workstream detailed blueprints (when created) |

## Coding Conventions

- **Memory:** Always use `hb_xgrab()`/`hb_xfree()`/`hb_xrealloc()`, never raw `malloc`/`free`.
- **Strings:** Binary-safe — use length property, never `strlen()`. Never use `strncat()`.
- **Naming:** Hungarian notation (`pPtr`, `nCount`, `cString`, `lFlag`). Static vars prefixed `s_`. Globals prefixed `hb_`. Macros/types prefixed `HB_`/`PHB_`.
- **Style:** 3-space indentation. BSD-style braces. C-style comments only (`/* */`), never `//`. Use `HB_TRUE`/`HB_FALSE`/`NULL`.
- **Functions given resource pointers should NOT free them** unless that is the documented purpose.
- **User-level C functions** use `HB_FUNC( FUNCNAME )` macro, uppercase names. Extensions to Clipper are prefixed `HB_`.

## Versioning

Drydock has its own version (`DD_VER_*`) separate from the Harbour compatibility
level (`HB_VER_*`). Both are defined in `include/hbver.h`.

- **Drydock version**: `DD_VER_MAJOR.DD_VER_MINOR.DD_VER_RELEASE` + `DD_VER_STATUS`
- **Harbour compat**: `HB_VER_MAJOR.HB_VER_MINOR` — do NOT change unless merging upstream
- **`__DRYDOCK__`**: macro for conditional compilation of Drydock-specific code
- **`__HARBOUR__`**: kept at `0x030200` for external code feature detection
- **Binaries**: all display "Drydock X.Y.Z (Harbour N.N compatible)"
- **`ENABLE TYPE CLASS ALL`**: deprecated — all scalar methods are built into the VM

## Key Environment Variables

| Variable | Purpose |
|----------|---------|
| `HB_PLATFORM` | Target OS (linux, win, darwin, dos, os2, bsd, etc.) |
| `HB_COMPILER` | C compiler (gcc, clang, msvc, mingw, watcom, etc.) |
| `HB_BUILD_DEBUG` | `yes` for debug build |
| `HB_BUILD_PARTS` | `all`, `compiler`, or `lib` |
| `HB_BUILD_SHARED` | `yes` to build shared libraries |
| `HB_INSTALL_PREFIX` | Installation target directory |
| `HB_WITH_*` | Path to 3rd-party dependency headers (e.g., `HB_WITH_CURL`, `HB_WITH_MYSQL`) |

## Build System

GNU Make based. `config/global.mk` is the master config (~5800 lines). Platform configs in `config/<platform>/`. The `hbmk2` tool (`utils/hbmk2/hbmk2.prg`) is the preferred build tool for Harbour projects — it uses `.hbp` project files. Contrib modules each have a `.hbp` + `.hbc` + `.hbx` triplet.

## Contrib Modules (contrib/)

70+ optional libraries: database drivers (hbmysql, hbpgsql, hbfbird, hbodbc), networking (hbcurl, hbssl, hbhttpd), graphics (hbcairo, hbgd), UI terminals (gtwvg, gtwvw, gtqtc), compression (hbmzip, hbbz2), data formats (hbjson, hbmxml), and more. Each follows the pattern: `.hbp` project file, C/PRG sources, `.hbx` exports.
