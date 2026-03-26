# BRIEF -- ZigBuild (SUBSYSTEM)

## Identity

| Field | Value |
|-------|-------|
| **Name** | ZigBuild |
| **Mode** | SUBSYSTEM |
| **Tier** | 0 — Build Infrastructure |
| **Component** | Build system — `config/`, `Makefile`, `utils/hbmk2/` |
| **Status** | PLANNING |

---

## 1. Motivation

The Harbour build system is **26,793 lines of code** across 244 files to
compile 744 C files and 112 PRG files. It is the most complex component in the
project — 1.23x the size of the compiler source code. This complexity is the
#1 barrier to contribution, CI velocity, and cross-platform development.

### The core problems

1. **No header dependency tracking.** Editing `hbapi.h` doesn't trigger
   recompilation of files that include it. Every developer runs
   `make clean && make` as muscle memory. This wastes minutes per cycle.

2. **26,793 lines for a static build graph.** The libraries, sources, and
   dependencies are fixed. The only variables are target platform, C compiler,
   and optional third-party libraries. Yet the build devotes 708 lines to
   compiler detection, 3,200 lines to platform configs, and 16,905 lines to a
   second build system (hbmk2).

3. **Cross-compilation requires per-target configuration.** Each target
   platform needs a directory with 3-5 `.mk` files, plus edits to the
   708-line detection chain in `global.mk`. `zig cc` cross-compiles to any
   target from any host with zero configuration.

4. **~40% of config/ supports dead platforms.** BeOS (2001), Symbian (2013),
   WinCE (2018), OS/2 (2005), HP-UX (2015), Minix — ~1,500 lines of
   untested platform code.

### The proposal

Replace the entire GNU Make + hbmk2 build system with `zig cc` (universal
C compiler) + a single `build.zig` file (~500 lines). This is a **54:1
reduction** in build system code.

See `doc/drydock-build-assessment.md` for the full analysis.

---

## 2. What `zig cc` Provides

`zig cc` is a drop-in replacement for `gcc`/`clang` that cross-compiles from
any host to any target. Single binary (~40MB), zero dependencies, ships with
libc headers for all targets.

```bash
# Native compilation
zig cc -c src/vm/hvm.c -o obj/hvm.o -Iinclude

# Cross-compile to Windows from Linux
zig cc -target x86_64-windows-gnu -c src/vm/hvm.c -o obj/hvm.o -Iinclude

# Cross-compile to ARM Linux
zig cc -target aarch64-linux-gnu -c src/vm/hvm.c -o obj/hvm.o -Iinclude

# Cross-compile to macOS from Linux
zig cc -target x86_64-macos -c src/vm/hvm.c -o obj/hvm.o -Iinclude
```

**Eliminated by `zig cc`:**

| Current Code | Lines |
|-------------|-------|
| Compiler auto-detection (global.mk) | 708 |
| 50+ platform/compiler .mk files | 3,200 |
| Cross-compilation setup (global.mk) | 383 |
| Shell abstraction (globsh.mk, 4 variants) | 346 |
| Platform detection (detplat.mk) | 96 |
| hbmk2 compiler invocation logic | ~3,000 |
| **Total** | **~7,700** |

### What `build.zig` Provides

The Zig build system is a real programming language, not a macro system:

- **Automatic header dependency tracking** — `zig cc` tracks every `#include`;
  change `hbapi.h` and everything that includes it rebuilds.
- **Parallel compilation by default** — every compilation unit runs in
  parallel across all cores; no jobserver hacks.
- **Content-addressed caching** — if the source hasn't changed, the object
  isn't recompiled, even across `clean` builds.
- **Custom build steps** — the `.prg → .c → .o` pipeline is a first-class
  build step, not a shell script.

---

## 3. Build Graph

### Key Insight: `.prg → .c` Is Not Required

The Harbour compiler has a `.hrb` backend (`harbour -gh`) that produces
**identical pcode bytecode** without generating C code. The VM executes the
same bytes regardless of source. The generated C is pure ceremony:

```c
HB_FUNC( MAIN ) {
    static const HB_BYTE pcode[] = { 13,4,0,36,4,0,... };
    hb_vmExecute( pcode, symbols );  /* same call as .hrb loader */
}
```

The C compiler does zero optimization of Harbour logic — it just packages
bytes into a native function wrapper. All symbol resolution happens at VM
runtime via `hb_dynsymFind()`, not at C link time.

**Consequence**: the build has two modes.

### Development Mode (default): `.prg → .hrb`

```
Phase 1: Build harbour compiler + VM + RTL (pure C — zig cc)
  hbcommon.a ← src/common/*.c (23 files)
  hbnortl.a  ← src/nortl/nortl.c
  hbpp.a     ← src/pp/*.c (4 files) → links hbcommon, hbnortl
  hbcplr.a   ← src/compiler/*.c (39 files) + harbour.y → links hbpp, hbcommon
  harbour    ← src/main/harbour.c → links hbcplr, hbpp, hbnortl, hbcommon
  hbvm.a     ← src/vm/*.c (50 files) → links hbcommon
  hbrtl.a    ← src/rtl/*.c (217 files) → links hbvm, hbcommon
  hbmacro.a  ← src/macro/*.c (4 files) + macro.y
  hbrdd.a    ← src/rdd/*.c (19 files)
  hbcpage.a  ← src/codepage/*.c (170+ files)
  hblang.a   ← src/lang/*.c (42 files)
  hbdebug.a  ← src/debug/*.c (1 file)
  GT drivers ← src/rtl/gt*/ (conditional per platform)
  RDD drivers← src/rdd/*/ (rddntx, rddcdx, rddfpt, etc.)

Phase 2: Compile .prg → .hrb (harbour -gh, NO C compiler needed)
  src/rtl/*.prg (76 files)     → obj/hrb/*.hrb
  src/vm/harbinit.prg          → obj/hrb/harbinit.hrb
  src/rdd/*.prg (12 files)     → obj/hrb/*.hrb
  src/debug/*.prg (13 files)   → obj/hrb/*.hrb
  src/hbextern/hbextern.prg    → obj/hrb/hbextern.hrb

Phase 3: Build shared library + embed .hrb files
  libharbour.so ← all C static libs merged + .hrb files as embedded resources
  (VM loads embedded .hrb at startup via hb_hrbLoad())

Phase 4: Utilities (compile .prg → .hrb, link with VM)
  hbmk2   ← utils/hbmk2/hbmk2.prg → .hrb, loaded by launcher
  hbtest  ← utils/hbtest/*.prg → .hrb, loaded by launcher
  hbi18n  ← utils/hbi18n/hbi18n.prg → .hrb, loaded by launcher
```

**Build speed**: Phase 1 (C compilation) is the slow part. Phase 2 is
milliseconds — `harbour -gh` just emits pcode, no C compiler involved.
Changing a `.prg` file only re-runs Phase 2 (instant) instead of
`.prg → .c → zig cc → .o → link` (seconds).

### Release Mode (`-Drelease`): `.prg → .c → .o`

```
Same as Development Phase 1, PLUS:

Phase 2: Compile .prg → .c → .o (harbour -gc0, then zig cc)
  src/rtl/*.prg (76 files)     → .c → .o (statically linked)
  src/vm/harbinit.prg          → .c → .o
  src/rdd/*.prg (12 files)     → .c → .o
  src/debug/*.prg (13 files)   → .c → .o
  src/hbextern/hbextern.prg    → .c → .o

Phase 3: Link standalone binaries
  harbour, hbmk2, hbtest, hbi18n ← all .o files + all .a libraries
  libharbour.so ← all static libs merged
```

This is the current behavior — standalone executables without runtime
dependency. Used for release builds and distribution only.

### Phase 5: Contribs

```
Each contrib package: .hbp → parsed → build.zig fragment or standalone build
```

---

## 4. `build.zig` Structure

The build description is a single file organized into helper functions:

```zig
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Phase 1: Bootstrap
    const hbcommon = addLib(b, "hbcommon", "src/common", &COMMON_SRCS, ...);
    const hbpp    = addLib(b, "hbpp", "src/pp", &PP_SRCS, ...);
    const hbcplr  = addLib(b, "hbcplr", "src/compiler", &COMPILER_SRCS, ...);
    const harbour = addCompilerExe(b, hbcplr, hbpp, hbcommon, ...);

    // Phase 2: Runtime C libraries (no .prg compilation needed)
    const hbvm  = addLib(b, "hbvm", "src/vm", &VM_C_SRCS, ...);
    const hbrtl = addLib(b, "hbrtl", "src/rtl", &RTL_C_SRCS, ...);
    // ... each C library is 3-5 lines

    // Phase 3: Compile .prg → .hrb (development) or .prg → .c → .o (release)
    const release = b.option(bool, "release-prg", "Use C path for .prg") orelse false;
    if (release) {
        // .prg → .c → .o (standalone executables)
        const prg_objs = addPrgToCObjects(b, harbour, &ALL_PRG_SOURCES);
        hbrtl.addObjectFiles(prg_objs);
    } else {
        // .prg → .hrb (fast dev builds, loaded by VM at startup)
        const hrb_step = addPrgToHrb(b, harbour, &ALL_PRG_SOURCES);
        // .hrb files embedded as resources or installed alongside binary
    }

    // Phase 4: Binaries
    const hbmk2  = addHarbourExe(b, harbour, "hbmk2", ...);
    const hbtest = addHarbourExe(b, harbour, "hbtest", ...);

    // Phase 4: Shared library
    const dynlib = addDynLib(b, ALL_LIBS, ...);

    // Tests
    const test_step = b.step("test", "Run hbtest");
    test_step.dependOn(&b.addRunArtifact(hbtest).step);
}

// Helper: add a static library from C sources
fn addLib(b, name, root, sources, target, optimize, deps) -> *std.Build.Step.Compile {
    const lib = b.addStaticLibrary(.{ .name = name, .target = target, .optimize = optimize });
    lib.addCSourceFiles(.{ .root = b.path(root), .files = sources, .flags = &HARBOUR_CFLAGS });
    lib.addIncludePath(b.path("include"));
    for (deps) |dep| lib.linkLibrary(dep);
    return lib;
}

// Helper: compile .prg files using the harbour compiler, then add to library
fn addPrgStep(b, harbour_exe, prg_file) -> std.Build.LazyPath {
    const run = b.addRunArtifact(harbour_exe);
    run.addFileArg(b.path(prg_file));
    run.addArg("-n");   // no implicit startup
    run.addArg("-w3");  // all warnings
    run.addArg("-es2"); // exit on warnings
    run.addArg("-q");   // quiet
    return run.addOutputFileArg(outputName(prg_file));
}
```

**Estimated size: ~400-600 lines** including all source file lists, platform
conditionals for GT drivers, and optional third-party library detection.

---

## 5. Platform-Specific Handling

### GT Drivers (conditional per platform)

```zig
// Platform-specific GT drivers
if (target.result.os.tag == .windows) {
    const gtwin = addLib(b, "gtwin", "src/rtl/gtwin", ...);
    const gtwvt = addLib(b, "gtwvt", "src/rtl/gtwvt", ...);
    const gtgui = addLib(b, "gtgui", "src/rtl/gtgui", ...);
}
if (target.result.os.tag == .linux or target.result.os.tag == .freebsd) {
    const gttrm = addLib(b, "gttrm", "src/rtl/gttrm", ...);
    if (b.option(bool, "x11", "Build X11 GT driver") orelse true) {
        const gtxwc = addLib(b, "gtxwc", "src/rtl/gtxwc", ...);
        gtxwc.linkSystemLibrary("X11");
    }
}
// Always built:
const gtstd = addLib(b, "gtstd", "src/rtl/gtstd", ...);
const gtcgi = addLib(b, "gtcgi", "src/rtl/gtcgi", ...);
const gtpca = addLib(b, "gtpca", "src/rtl/gtpca", ...);
```

Normal if/else in a typed language. Not 50+ `.mk` files.

### Third-Party Libraries

```zig
// Optional third-party libraries
const use_system_zlib = b.option(bool, "system-zlib", "Use system zlib") orelse false;
if (use_system_zlib) {
    hbrtl.linkSystemLibrary("z");
} else {
    const hbzlib = addLib(b, "hbzlib", "src/3rd/zlib", &ZLIB_SRCS, ...);
    hbrtl.linkLibrary(hbzlib);
}

const use_system_pcre = b.option(bool, "system-pcre", "Use system PCRE") orelse false;
if (use_system_pcre) {
    hbrtl.linkSystemLibrary("pcre");
} else {
    const hbpcre = addLib(b, "hbpcre", "src/3rd/pcre", &PCRE_SRCS, ...);
    hbrtl.linkLibrary(hbpcre);
}
```

Replaces `config/detect.mk` (143 lines) + `config/detfun.mk` (156 lines).

### System Libraries

```zig
if (target.result.os.tag == .windows) {
    for (&.{ "kernel32", "user32", "gdi32", "winmm", "winspool", "ws2_32" }) |lib| {
        harbour.linkSystemLibrary(lib);
    }
} else {
    harbour.linkSystemLibrary("m");
    harbour.linkSystemLibrary("dl");
    harbour.linkSystemLibrary("pthread");
}
```

---

## 6. Phased Migration

### Phase Z.0: Immediate Fix (1 day) — DONE (2026-03-26, `70d3813`)

Added `-MMD -MP` to `config/linux/gcc.mk` and `config/linux/clang.mk`,
and `-include` for `.d` files in `config/c.mk` and `config/prg.mk`.
1,367 dependency files generated. Incremental rebuild after touching
`hbapi.h`: 0.5s. No-op core build: 0.28s. hbtest 4861/4861 passed.

### Phase Z.1: Compiler Bootstrap via Zig (1 week)

Add `build.zig` that builds the `harbour` compiler binary. Phase 1 only
(pure C, no .prg). Keep Make for everything else.

**Verification**: `zig build` produces a working `harbour` binary.
`harbour -n -w3 -es2 tests/hello.prg` compiles without error and produces
`hello.c`. (Full `hbtest` requires the runtime, which is Phase Z.2+.)

**Coexistence**: both `make` and `zig build` work. Developers choose.

### Phase Z.2: Full C Build (1 week)

Extend `build.zig` to build all C libraries: hbvm, hbrtl (C files only),
hbmacro, hbrdd, hbcpage, hblang, hbdebug, all GT drivers, all RDD drivers,
third-party libs.

**Still missing**: `.prg` compilation — those libraries are incomplete.

### Phase Z.3: .prg Compilation — Two Modes (1 week)

Add `.prg` compilation step with two modes:

**Development mode (default)**: `harbour -gh` compiles `.prg → .hrb`.
No C compiler involved for `.prg` files. The `.hrb` files are loaded by
the VM at startup via `hb_hrbLoad()`. Changing a `.prg` file only re-runs
`harbour -gh` (milliseconds), not the full C pipeline.

**Release mode** (`-Drelease-prg`): `harbour -gc0` compiles `.prg → .c`,
then `zig cc` compiles to `.o`, linked into standalone binaries. This is
the traditional pipeline, used for distribution.

**Verification**: `zig build && zig build test` passes hbtest 4861/4861.
`zig build -Drelease-prg && zig build test` produces identical results.

**Key milestone**: Make is now optional for the core build.

### Phase Z.4: Contrib Migration (2 weeks)

Port 74 contrib packages. Each gets a small `build.zig` (5-15 lines) or is
built via a shared helper. The `.hbc` format is preserved as metadata; a
translator generates zig build fragments from `.hbc` files.

### Phase Z.5: Make Removal (1 week)

- Delete `config/` directory (121 .mk files, 7,545 lines)
- Delete all 60 `Makefile` files (2,343 lines)
- Update CI/CD to use `zig build`
- Keep minimal Make fallback for niche platforms (if any users exist)
- Shrink hbmk2 to project-tool role (~3,000 lines)

### Phase Z.6: hbmk2 Simplification (2-3 weeks)

Rewrite hbmk2 as a modular tool:

| Module | Lines (est.) | Responsibility |
|--------|-------------|----------------|
| `hbmk2_core.prg` | ~800 | Entry point, context, main loop |
| `hbmk2_project.prg` | ~600 | .hbp/.hbc parsing |
| `hbmk2_zig.prg` | ~400 | Translate .hbp to zig build invocations |
| `hbmk2_deps.prg` | ~500 | Dependency resolution |
| `hbmk2_plugin.prg` | ~400 | Plugin loading |
| `hbmk2_util.prg` | ~300 | File/path utilities |
| **Total** | **~3,000** | vs. 16,905 today |

---

## 7. Affected Files

### Deleted

| Path | Lines | Notes |
|------|-------|-------|
| `config/*.mk` (121 files) | 7,545 | All platform/compiler configuration |
| `Makefile` (60 files) | 2,343 | All recursive makefiles |
| **Subtotal deleted** | **9,888** | |

### Modified

| Path | Lines | Change |
|------|-------|--------|
| `utils/hbmk2/hbmk2.prg` | 16,905 | Rewritten to ~3,000 lines (Phase Z.6) |

### Created

| Path | Lines (est.) | Notes |
|------|-------------|-------|
| `build.zig` | ~500 | Single build description |
| **Subtotal created** | **~500** | |

### Net Change

**Deleted**: ~23,800 lines (config + Makefiles + hbmk2 rewrite savings)
**Created**: ~500 lines
**Net reduction**: **~23,300 lines** removed from the project

---

## 8. Compatibility Stance

**Build output must be identical.** The compiler, libraries, and binaries
produced by `zig build` must be byte-for-byte equivalent to `make` output
(within the normal variance of different C compilers).

- All existing `.hbp` and `.hbc` files continue to work via hbmk2
- No source code changes to any `.c` or `.prg` file
- No header changes
- No API changes
- The change is purely in how compilation is invoked, not what is compiled

**Platform support reduction:**
- Dropped: BeOS, Symbian, WinCE, OS/2, HP-UX, Minix, MS-DOS, SunOS
- Kept: Linux, Windows, macOS, BSD, Android, QNX (all via zig)
- This is a **deliberate decision** — maintaining dead platforms has a cost

## 9. Performance Stance

**Build speed must improve.**

- Automatic parallelism across all cores (vs. fragile jobserver)
- Content-addressed caching (vs. no cache)
- Correct incremental builds (vs. stale objects requiring clean)
- Single-pass compilation for shared libs (vs. double compilation)
- Expected improvement: **2-5x faster** clean builds, **10-50x faster**
  incremental builds

## 10. Dependencies

| Dependency | Status | Notes |
|------------|--------|-------|
| *(none)* | — | ZigBuild is independent of all compiler/VM workstreams |

**Does not block and is not blocked by** any Tier 1-3 workstream. The build
system migration is orthogonal to compiler modernization. Both can proceed
in parallel.

**Enables**: Faster development velocity for all other workstreams. Correct
incremental builds mean faster iteration on RefactorHvm, ScalarClasses, etc.

## 11. Risks

| Risk | Severity | Mitigation |
|------|----------|------------|
| Zig not 1.0 yet | Medium | `zig cc` is stable and battle-tested (Uber, Bun, Tigerbeetle). Build API may change between versions — migrations are mechanical. Pin zig version in CI. |
| Team must learn build.zig | Low | ~500 lines, straightforward API. No Zig language knowledge needed beyond build system. |
| Loss of MSVC support | Medium | `zig cc` targets Windows via MinGW-w64. If MSVC-specific features needed, keep minimal MSVC path. In practice, MinGW-w64 produces equivalent binaries. |
| Contrib .hbc backward compat | Low | .hbc is declarative config — parsed and translated to zig build invocations. Format preserved. |
| Niche platform users | Low | Keep minimal Make fallback for any platform with actual users. |
| Zig binary size (~40MB) | Low | Comparable to GCC/Clang. Single download vs. toolchain installation. |

## 12. Estimated Scope

| Phase | Effort | Can Ship Independently |
|-------|--------|----------------------|
| ~~Z.0: Add `-MMD` to Make~~ | ~~1 day~~ | **DONE** (2026-03-26) |
| Z.1: Compiler bootstrap via zig | 1 week | Yes |
| Z.2: Full C build | 1 week | Yes (after Z.1) |
| Z.3: Two-phase bootstrap (.prg) | 1 week | Yes (after Z.2) |
| Z.4: Contrib migration | 2 weeks | Yes (after Z.3) |
| Z.5: Make removal | 1 week | Yes (after Z.3) |
| Z.6: hbmk2 simplification | 2-3 weeks | Yes (independent) |
| **Total** | **8-10 weeks** | |

Phases Z.0-Z.3 (4 weeks) deliver a working parallel build path. Phases Z.4-Z.6
are cleanup that can happen at any pace.

---

[<- Index](../INDEX.md) · [Map](../MAP.md) · **BRIEF**
