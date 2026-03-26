# Harbour Build System — Deep Analysis & Modernization Assessment

**Date**: 2026-03-26
**Context**: Analysis of the GNU Make + hbmk2 dual build system in the
Harbour compiler fork under the Drydock modernization initiative.

---

## 1. Executive Summary

The Harbour build system is **26,793 lines of code** to compile **744 C files
and 112 PRG files**. That's a 1.23:1 ratio — more build infrastructure than
compiler source code. The system is split between GNU Make (primary, for
bootstrapping) and hbmk2 (secondary, for user projects and contribs), with
significant logic duplication between the two.

The build system supports 18 platforms and 20+ compilers, but at least 8 of
those platforms are defunct. The complexity serves a portability matrix that
no longer exists in practice.

This document catalogues what's wrong, then proposes replacing the entire
system with `zig cc` + a single `build.zig` file — a 54:1 reduction.

---

## 2. Architecture Overview

```
Makefile (top-level, 55 lines)
  → config/global.mk (2,065 lines — the brain)
    → config/detplat.mk (96 lines) — platform detection
    → config/detect.mk (143 lines) — 3rd-party library detection
    → config/detfun.mk (156 lines) — detection template function
    → config/[platform]/global.mk — platform defaults (18 dirs)
    → config/[platform]/[compiler].mk — compiler flags (50+ files)
  → config/dir.mk (73 lines) — recursive directory traversal
  → config/lib.mk (174 lines) / bin.mk (174 lines) — target templates
  → config/c.mk / prg.mk — C and Harbour compilation rules
  → config/globsh.mk (234 lines) — 4 shell implementations (sh/nt/os2/dos)
  → config/instsh.mk (112 lines) — 4 install implementations

hbmk2.prg (16,905 lines — monolithic)
  → parses .hbp project files
  → parses .hbc config files
  → invokes compilers directly
  → used for contrib/ builds after bootstrap
```

### Weight Breakdown

| Component | Lines | Files | % of Total |
|-----------|-------|-------|------------|
| `config/*.mk` | 7,545 | 121 | 28.2% |
| Makefiles (all) | 2,343 | 60 | 8.7% |
| `hbmk2.prg` | 16,905 | 1 | 63.1% |
| **Total** | **26,793** | **182** | **100%** |

### What It Actually Produces

| Output | Count | Notes |
|--------|-------|-------|
| Static libraries | 50+ | hbcommon, hbpp, hbcplr, hbvm, hbrtl, hbrdd, + GT drivers, + RDD drivers |
| Shared library | 1 | `libharbour.so` / `harbour.dll` — all 50 libs merged |
| Binaries | 4 | `harbour` (compiler), `hbmk2` (build tool), `hbtest`, `hbi18n` |
| Contrib packages | 74 | Built via hbmk2 after bootstrap |

The entire build graph is **static**: libraries, their sources, and their
dependencies do not change at runtime. The only variables are: which C
compiler, which target platform, and which optional third-party libraries.

---

## 3. Critical Deficiencies

### 3.1 No Header Dependency Tracking

The #1 bug. There are **no `.d` files generated**. No `-MMD` flag. No
automatic dependency scanning anywhere. If you edit `hbapi.h` (included by
hundreds of files), nothing recompiles unless you run `make clean`.

The only dependencies are hand-coded:

```makefile
YACC_HEADERS := hbcomp.h hbcompdf.h hbsetup.h ...
YACC_DEPEND := complex.c
```

For a codebase with 151 headers and 744 C files, this guarantees stale-object
bugs. Every developer's muscle memory is `make clean && make`, which destroys
any incremental build benefit and costs minutes per cycle.

### 3.2 `global.mk` Is Unmaintainable (2,065 lines)

708 lines (34% of the file) are nested if/else chains for compiler
auto-detection, 18-20 levels deep. The same MinGW detection logic appears
4 times. There are no helper functions, no data tables, no abstraction:

```makefile
ifneq ($(HB_COMP_PATH),)          # depth 4
   HB_COMPILER := mingwarm
else                               # depth 4
   HB_COMP_PATH := $(call find_in_path,i386-mingw32ce-gcc)
   ifneq ($(HB_COMP_PATH),)       # depth 5
      HB_COMPILER := mingw
   else                            # depth 5
      # ... continues for 400 more lines ...
```

Adding a new compiler means navigating this maze and inserting into the right
nesting level. Getting it wrong silently falls through to the wrong compiler.

### 3.3 hbmk2.prg Is a 16,905-Line Monolith

Zero modularization. The core function `__hbmk()` spans ~6,300 lines. The
context is a 130+ field array passed everywhere. It parses command lines in
**two separate passes** with duplicated CASE statements. Platform/compiler
checks are scattered across 95+ inline conditionals. There are no unit tests.

This is the tool that builds all 74 contrib packages. Any change risks
breaking all of them, with no way to test in isolation.

### 3.4 Dead Platform Support (~40% of config/ code)

| Platform | Status | Last Real Use | Lines of Config |
|----------|--------|---------------|-----------------|
| BeOS | Dead since 2001 | Never, in practice | ~50 |
| Symbian | Dead since 2013 | ~2012 | ~80 |
| Windows CE | Dead since 2018 | ~2015 | ~120 |
| OS/2 | Dead since 2005 | ~2010 | ~100 |
| HP-UX | EOL 2015 | ~2014 | ~80 |
| MS-DOS | Legacy niche | Niche | ~100 |
| VxWorks | Niche embedded | Unknown | ~80 |
| Minix | Educational only | Never | ~60 |
| QNX | Niche embedded | Unknown | ~80 |
| SunOS/Solaris | EOL 2022 | ~2020 | ~80 |

~830 lines of platform config for platforms nobody builds on, plus ~300 lines
of corresponding conditionals in `global.mk` and ~500 lines in hbmk2. Total
dead platform weight: **~1,500-2,000 lines**.

### 3.5 Double Compilation for Shared Libraries

When `HB_BUILD_DYN != no`, every C file compiles **twice**: once for the
static library, once with `-fPIC` for the dynamic library. This doubles C
compilation time. Modern practice: compile once with `-fPIC` (negligible
overhead on x86-64) or use thin archives.

### 3.6 Manual Library Linking Order

Libraries are linked in explicit order with **repetition** to handle circular
dependencies:

```makefile
HB_LIBS_TPL = hbextern hbdebug $(_HB_VM) hbrtl hblang hbcpage \
              $(HB_GT_LIBS) $(_HB_RDD) hbrtl $(_HB_VM) \
              hbmacro hbcplr hbpp hbcommon
#                                   ^^^       ^^^
#                              repeated twice!
```

If you add a new library or change a dependency, you must manually figure out
where in the list to insert it. Get it wrong and you get linker errors that
only manifest on some platforms.

### 3.7 Parser Regeneration Is Opt-In

The Bison grammar (`harbour.y`) is only regenerated when
`HB_REBUILD_PARSER=yes` is set. Otherwise, a pre-built `.yyc` file is copied.
If someone edits the grammar and forgets the flag, the old parser is silently
used. This is a correctness bug waiting to happen.

### 3.8 No Build Cache

No ccache integration, no sccache, no content-addressed cache. CI/CD
rebuilds from scratch every time.

### 3.9 Four Shell Implementations

Every build operation (mkdir, cp, rm, install) has **four implementations** in
`globsh.mk`: one for Unix (`sh`), Windows (`nt`), OS/2 (`os2`), and DOS
(`dos`). 4x the code, 4x the bugs, 4x the testing surface.

### 3.10 Recursive Make with Implicit Dependencies

The build uses recursive `$(MAKE) -C subdir` with a custom fragment notation:

```makefile
DIRS = 3rd common nortl pp{common,nortl} compiler{pp} vm{pp} ...
```

This is parsed by `$(eval)` into Make prerequisites. It works, but the
dependency graph is flat (no transitive closure), the syntax is undocumented,
and parallel builds can race if fragments are incomplete.

---

## 4. Structural Weaknesses

### 4.1 Two Build Systems That Partially Overlap

GNU Make handles the core build. hbmk2 handles contribs and user projects.
Both contain:

- Compiler detection logic (~708 lines in Make, ~3,000 lines in hbmk2)
- Platform-specific flag composition
- Library search and dependency resolution
- Cross-compilation support

The same knowledge is encoded twice, in different languages, with different
bugs. When a new compiler is supported, both systems need updating.

### 4.2 No Incremental Harbour Compilation

C files get (broken) incremental builds. But `.prg` files always recompile
through the full pipeline: `.prg` → `.c` → `.o`. There's no mechanism to
skip the `.prg` → `.c` step if the `.prg` hasn't changed.

### 4.3 Contrib Packages Have No Versioning

74 packages, each with `.hbp` + `.hbc` + `.hbx`, but no version constraints
between them. No way to express "hbcurl 1.2+ requires hbssl 1.1+". No
dependency solver. No lock file.

### 4.4 Variable Cascading Is Opaque

`global.mk` uses a multi-level variable cascade:

```
User/env vars → auto-detection → platform defaults → computed vars → exports
```

Debugging "why is `CFLAGS` set to X?" requires tracing through 2,065 lines
of conditionals. There's no `--verbose` or `--trace` mode that shows the
cascade. The `_DET_*` temporary variables pollute the global namespace.

---

## 5. What Works (Don't Lose These)

1. **Out-of-source builds** — `obj/platform/compiler/` keeps the source tree
   clean. Any replacement must preserve this.
2. **Platform-specific GT drivers** — conditional inclusion of `gtwin` (Windows
   only), `gtxwc` (X11 only), etc. The build correctly handles optional
   platform-specific components.
3. **The `.hbc` config format** — declarative package configs
   (`sources=`, `libs=`, `cflags=`, `{win}syslibs=`) are well-designed.
   Worth preserving as a Harbour package description format.
4. **Two-phase bootstrap** — the build correctly handles the chicken-and-egg:
   build compiler (C only) → use compiler to build PRG sources.
5. **Unified dynlib** — merging 50+ static libs into one shared library is a
   real user requirement. The `harbour.def` export file works.

---

## 6. The Proposal: `zig cc` + `build.zig`

### 6.1 `zig cc` as Universal C Compiler

`zig cc` is a drop-in replacement for `gcc`/`clang` that cross-compiles from
any host to any target out of the box. Single binary (~40MB), zero
dependencies, ships with libc headers for every platform.

```bash
# Native (works today, no setup)
zig cc -c src/vm/hvm.c -o obj/hvm.o -Iinclude

# Cross-compile to Windows from Linux (works today, no setup)
zig cc -target x86_64-windows-gnu -c src/vm/hvm.c -o obj/hvm.o

# Cross-compile to ARM Linux (works today, no setup)
zig cc -target aarch64-linux-gnu -c src/vm/hvm.c -o obj/hvm.o

# Cross-compile to macOS from Linux (works today, no setup)
zig cc -target x86_64-macos -c src/vm/hvm.c -o obj/hvm.o
```

What this eliminates:

| Current Code | Lines | Status |
|-------------|-------|--------|
| Compiler auto-detection (global.mk) | 708 | Gone |
| 50+ platform/compiler .mk files | 3,200 | Gone |
| Cross-compilation setup | 383 | Gone |
| Shell abstraction (sh/nt/os2/dos) | 346 | Gone |
| Platform detection (detplat.mk) | 96 | Gone |
| hbmk2 compiler invocation logic | ~3,000 | Gone |
| **Total eliminated** | **~7,700** | |

One binary replaces 20+ compilers, 18 platform configs, and all
cross-compilation setup. The concept of "which compiler do I have?" disappears.

### 6.2 `build.zig` as Single Build File

Instead of 60 Makefiles, 121 .mk files, and 16,905 lines of hbmk2 — one file
in a real programming language, ~400-600 lines:

```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Core libraries — each is 5-10 lines
    const hbcommon = addHarbourLib(b, "hbcommon", "src/common",
        &.{ "hbdate.c", "hbstr.c", "hbhash.c", /* ... 23 files */ },
        target, optimize, &.{});

    const hbpp = addHarbourLib(b, "hbpp", "src/pp",
        &.{ "ppcore.c", "pplib.c", "pplib2.c", "pptable.c" },
        target, optimize, &.{hbcommon});

    const hbcplr = addHarbourLib(b, "hbcplr", "src/compiler",
        &COMPILER_SOURCES,
        target, optimize, &.{ hbpp, hbcommon });

    const hbvm = addHarbourLib(b, "hbvm", "src/vm",
        &VM_SOURCES,
        target, optimize, &.{hbcommon});

    // Compiler binary
    const harbour = b.addExecutable(.{ .name = "harbour", .target = target });
    harbour.addCSourceFile(.{ .file = b.path("src/main/harbour.c") });
    harbour.linkLibrary(hbcplr);
    harbour.linkLibrary(hbpp);
    harbour.linkLibrary(hbcommon);
    b.installArtifact(harbour);

    // Phase 2: use harbour to compile .prg files
    const prg_step = addPrgCompilation(b, harbour, &PRG_SOURCES);
    // ... rest of build
}
```

### 6.3 What This Gives You

| Feature | GNU Make (current) | `zig build` (proposed) |
|---------|-------------------|----------------------|
| Header dep tracking | None (stale objects) | Automatic |
| Parallel builds | Fragile (recursive + jobserver) | Native (full graph upfront) |
| Cross-compilation | 383 lines of setup per target | `-Dtarget=` flag |
| Build cache | None | Content-addressed, automatic |
| Incremental rebuild | Broken | Correct by construction |
| Add a source file | Edit Makefile, worry about deps | Add to source list |
| Add a platform | Create dir, 3-5 .mk files, edit global.mk | Nothing — zig handles it |
| CI setup | Install compiler + Make + configure env | `curl zig && zig build` |
| Lines of build code | 26,793 | ~500 |
| Build files | 244 | 1 |
| Debug/Release | `HB_BUILD_DEBUG=yes` env var | `-Doptimize=Debug` flag |

### 6.4 Platform Coverage

| Platform | Zig Support | Harbour Status |
|----------|------------|----------------|
| Linux (x86, x64, ARM, RISC-V) | Native | Active |
| Windows (x86, x64) | Native | Active |
| macOS (x64, ARM64) | Native | Active |
| FreeBSD, NetBSD, OpenBSD | Native | Active |
| Android | Native | Active |
| WASM | Native | Future opportunity |
| MS-DOS | No | Dead — drop |
| OS/2 | No | Dead — drop |
| BeOS | No | Dead — drop |
| Symbian | No | Dead — drop |
| Windows CE | No | Dead — drop |
| HP-UX, AIX, VxWorks | No | Niche — minimal Make fallback |

For the 2-3 niche platforms Zig doesn't target, keep a **minimal** GNU Make
fallback — ~200 lines for a single platform, not 26,000 for everything.

### 6.5 The Bootstrap Problem

The chicken-and-egg: you need `harbour` to compile `.prg` files, but `harbour`
is what you're building.

**Solution: two-phase build in `build.zig`.**

```
Phase 1: Build harbour compiler (pure C — no .prg needed)
  hbcommon.a ← src/common/*.c
  hbpp.a     ← src/pp/*.c
  hbcplr.a   ← src/compiler/*.c
  harbour    ← src/main/harbour.c + above libs

Phase 2: Use harbour to compile .prg → .c, then build everything else
  src/rtl/*.prg → *.c → hbrtl.a
  src/vm/harbinit.prg → *.c → hbvm.a
  src/rdd/*.prg → *.c → hbrdd.a
  etc.
```

Zig's build system handles this natively — it understands "build tool A, then
use A to generate sources for B."

### 6.6 hbmk2's Remaining Role

hbmk2 doesn't die — it **shrinks**. It stops being a build system and becomes
a **user-facing project tool**:

| Current hbmk2 (16,905 lines) | New hbmk2 (~3,000 lines) |
|-------------------------------|--------------------------|
| Compiler detection | Gone — `zig cc` |
| Platform detection | Gone — target flag |
| C compilation invocation | Gone — `zig build` |
| .hbp/.hbc parsing | Kept — user project format |
| Dependency resolution | Kept — wraps zig package manager |
| Plugin system | Kept |
| Contrib orchestration | Simplified — each contrib gets a build.zig |

---

## 7. Migration Path

Not a big-bang rewrite. Progressive adoption:

**Week 1**: Add `build.zig` that builds just the compiler binary (`harbour`).
Keep Make for everything else. Developers can choose either path.

**Week 2**: Extend `build.zig` to build VM and RTL (C files only). `.prg`
files still use Make's harbour invocation.

**Week 3**: Add two-phase bootstrap — `build.zig` builds `harbour`, then
uses it to compile `.prg` files. Make becomes optional for the core build.

**Week 4**: Port contrib packages. Each gets a small `build.zig` (5-15 lines)
replacing its `.hbp`/Makefile.

**Week 5**: Delete Make. Ship zig as the build dependency.

---

## 8. Risk Assessment

| Risk | Severity | Mitigation |
|------|----------|------------|
| Zig is not 1.0 yet | Medium | `zig cc` (the C compiler) is stable and battle-tested; used by Uber, Bun, etc. The build system API may change between Zig versions, but migrations are mechanical. |
| Team must learn Zig build syntax | Low | `build.zig` is ~500 lines of straightforward code. No Zig language knowledge needed beyond the build API. |
| Loss of MSVC support | Medium | `zig cc` targets Windows via MinGW-w64, not MSVC. If MSVC-specific features are needed, keep a minimal MSVC path. In practice, MinGW-w64 produces equivalent binaries. |
| Contrib .hbc backward compatibility | Low | .hbc files are declarative config — can be parsed by the new hbmk2 and translated to zig build invocations. |
| CI/CD pipeline changes | Low | Replace "install gcc + make" with "install zig" — simpler, not harder. |
| Niche platform users | Low | Keep minimal Make fallback for platforms zig doesn't support. |

---

## 9. Comparison with Other Options

### 9.1 CMake

The conventional choice. Better than Make, but:

- CMakeLists.txt syntax is its own DSL with surprising semantics
- Still requires a system C compiler — doesn't solve cross-compilation
- No built-in build cache (needs ccache separately)
- Generator step (CMake → Ninja/Make) adds complexity
- Would still need 50+ lines per platform for toolchain files

CMake would be a **5:1 reduction** (26,793 → ~5,000 lines). Zig gives **54:1**.

### 9.2 Meson

Cleaner than CMake, Python-based:

- Better syntax (Python-like, not CMake DSL)
- Ninja backend is fast
- Good cross-compilation via cross files
- Still requires system C compiler
- Would be ~3,000-4,000 lines

Meson is a solid choice but doesn't solve the compiler detection problem.

### 9.3 Self-Hosting (Harbour builds itself)

Rewrite hbmk2 as the only build system, bootstrap via tiny C stub:

- Elegant (Rust, Go, Zig all do this)
- But hbmk2 IS the problem — 16,905 lines of unmaintainable code
- Rewriting it cleanly would take longer than adopting zig build
- Still doesn't solve cross-compilation

### 9.4 Plain Makefile + `-MMD`

The minimal fix: add `-MMD` for header deps, drop dead platforms, clean up
global.mk. This is the "stay on Make" option:

- Fixes stale-object bugs (biggest pain point)
- Doesn't fix: cross-compilation, no caching, shell duplication, hbmk2 monolith
- Estimated effort: 2 weeks for meaningful improvement
- Estimated result: 26,793 → ~15,000 lines (dead platform removal + cleanup)

This is the **safe option** — recommended if the zig approach feels too radical.

---

## 10. Recommendation

**Short-term (do now)**: Add `-MMD` to `config/c.mk`. Two lines. Fixes the
#1 build bug immediately regardless of which direction is chosen.

**Medium-term (this quarter)**: Add `build.zig` as a parallel build path.
Prove it works for the compiler binary. Let developers opt in.

**Long-term (next quarter)**: Extend `build.zig` to full coverage. Deprecate
Make. Shrink hbmk2 to a project-tool wrapper.

The build system should be invisible. Today it's the most complex component in
the project. With zig, it becomes a file.
