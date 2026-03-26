# DESIGN -- ZigBuild (SUBSYSTEM)

## 1. Current State

### Build Graph

The Harbour build is a two-phase bootstrap:

1. **Phase 1 (C only)**: Build the `harbour` compiler from pure C sources
2. **Phase 2 (C + PRG)**: Use `harbour` to compile `.prg` sources, then compile
   the generated C, then link everything into libraries and binaries

```
hbcommon.a  ← src/common/*.c (20 files)
hbnortl.a   ← src/nortl/nortl.c (1 file)
hbpp.a      ← src/pp/*.c (4 files)
hbcplr.a    ← src/compiler/*.c (23 files) + harbour.y → harboury.c
harbour     ← src/main/harbour.c + hbcplr + hbpp + hbnortl + hbcommon
               │
               ▼ harbour compiler is now available
hbvm.a      ← src/vm/*.c (45 files) + harbinit.prg
hbrtl.a     ← src/rtl/*.c (207 files) + *.prg (74 files)
hbmacro.a   ← src/macro/*.c (3 files) + macro.y
hbrdd.a     ← src/rdd/*.c (20 files) + *.prg (12 files)
  rddntx.a  ← src/rdd/dbfntx/*.c (1 file)
  rddcdx.a  ← src/rdd/dbfcdx/*.c (2 files)
  rddfpt.a  ← src/rdd/dbffpt/*.c (1 file)
  rddnsx.a  ← src/rdd/dbfnsx/*.c (1 file)
  hbsix.a   ← src/rdd/hbsix/*.c (7) + *.prg (3)
  hbhsx.a   ← src/rdd/hsx/*.c (2 files)
  hbusrrdd.a← src/rdd/usrrdd/*.c (1 file)
  nulsys.a  ← src/rdd/nulsys/*.c (1 file)
hbcpage.a   ← src/codepage/*.c (172 files)
hblang.a    ← src/lang/*.c (39 files)
hbdebug.a   ← src/debug/*.c (1 file) + *.prg (13 files)
hbextern.a  ← src/hbextern/hbextern.prg
GT drivers  ← src/rtl/gt*/ (conditional per platform)
3rd party   ← src/3rd/pcre/*.c (34), src/3rd/zlib/*.c (15)
               │
               ▼ full runtime is now available
hbtest      ← utils/hbtest/*.prg (13 files) + all runtime libs
hbmk2       ← utils/hbmk2/hbmk2.prg + all runtime libs
```

### Source File Totals

| Category | C Files | PRG Files | YACC Files |
|----------|---------|-----------|------------|
| Bootstrap (compiler) | 49 | 0 | 1 |
| Runtime | 498 | 101 | 1 |
| Third-party (pcre, zlib) | 49 | 0 | 0 |
| Utilities | 0 | 14 | 0 |
| **Total** | **596** | **115** | **2** |

(Excludes jpeg/png/tiff/hbpmcom which are contrib-level, and 172 codepage files.)

### Current Compiler Flags (Linux/GCC)

```
-I. -I<root>/include     Include paths
-W -Wall                 Warnings
-O3                      Optimization
-MMD -MP                 Dependency tracking (added in Phase Z.0)
-c                       Compile only
-o <output>              Output file
```

Conditional:
```
-g                       Debug mode (HB_BUILD_DEBUG=yes)
-DHB_TR_LEVEL_DEBUG      Debug trace (HB_BUILD_DEBUG=yes)
-DHB_DYNLIB -fPIC        Dynamic library builds
-DHB_MT_VM               Multi-threaded VM variant (hbvmmt only)
```

Third-party library flags:
```
-DPCRE_STATIC -DSUPPORT_UTF -DSUPPORT_UCP     (pcre)
-DHAVE_UNISTD_H                                 (zlib on unix)
-DHB_HAS_PCRE -DHB_HAS_ZLIB                    (rtl, when bundled)
```

### Harbour Compiler Flags (for .prg files)

```
harbour -n1 -q0 -w3 -es2 -kmo -i- -i<root>/include <file.prg>
```

This produces a `.c` file that is then compiled with the C compiler.

### YACC/Bison

Two grammar files require Bison:

| File | Prefix | Output | Used By |
|------|--------|--------|---------|
| `src/compiler/harbour.y` | `hb_comp_yy` | `harboury.c` + `harboury.h` | hbcplr library |
| `src/macro/macro.y` | `hb_macro_yy` | `macroy.c` + `macroy.h` | hbmacro library |

Pre-generated `.yyc` / `.yyh` files are checked in as fallbacks when
`HB_REBUILD_PARSER` is not set. The build copies `.yyc` → `.c` and `.yyh` → `.h`.

---

## 2. Proposed Changes

### 2.1 build.zig Structure

A single `build.zig` file organized into:

```zig
const std = @import("std");

// -- Source file lists (const arrays) --
const COMMON_SRCS = [_][]const u8{ "expropt1.c", "expropt2.c", ... };
const PP_SRCS     = [_][]const u8{ "hbpp.c", "ppcore.c", "pplib.c", "pplib2.c" };
const COMPILER_SRCS = [_][]const u8{ "cmdcheck.c", "compi18n.c", ... };
// ... one array per library

// -- C compilation flags --
const HARBOUR_CFLAGS = [_][]const u8{ "-W", "-Wall" };
const HARBOUR_DEFINES = [_][]const u8{ };

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Phase 1: Bootstrap (pure C)
    const hbcommon = addCLib(b, "hbcommon", "src/common", &COMMON_SRCS, target, optimize);
    const hbnortl  = addCLib(b, "hbnortl", "src/nortl", &.{"nortl.c"}, target, optimize);
    const hbpp     = addCLib(b, "hbpp", "src/pp", &PP_SRCS, target, optimize);
    const hbcplr   = addCLib(b, "hbcplr", "src/compiler", &COMPILER_SRCS, target, optimize);
    // harbour.y: use pre-generated harboury.c (copy from .yyc)
    const harbour  = addExe(b, "harbour", "src/main/harbour.c",
                            &.{hbcplr, hbpp, hbnortl, hbcommon}, target, optimize);

    // Phase 2: Runtime (needs harbour for .prg → .c)
    const hbvm   = addLibWithPrg(b, harbour, "hbvm", ...);
    const hbrtl  = addLibWithPrg(b, harbour, "hbrtl", ...);
    // ... each library

    // Phase 3: Binaries
    const hbtest = addHarbourExe(b, harbour, "hbtest", ...);

    // Test step
    const test_step = b.step("test", "Run hbtest");
    test_step.dependOn(&b.addRunArtifact(hbtest).step);
}
```

### 2.2 Helper Functions

```zig
fn addCLib(b: *std.Build, name: []const u8, root: []const u8,
           srcs: []const []const u8, target: anytype, optimize: anytype)
    *std.Build.Step.Compile
{
    const lib = b.addStaticLibrary(.{
        .name = name,
        .target = target,
        .optimize = optimize,
    });
    lib.addCSourceFiles(.{
        .root = b.path(root),
        .files = srcs,
        .flags = &HARBOUR_CFLAGS,
    });
    lib.addIncludePath(b.path("include"));
    return lib;
}

fn addPrgToC(b: *std.Build, harbour_exe: *std.Build.Step.Compile,
             prg_path: []const u8) std.Build.LazyPath
{
    const run = b.addRunArtifact(harbour_exe);
    run.addArgs(&.{ "-n1", "-q0", "-w3", "-es2", "-kmo", "-i-" });
    run.addArg("-i");
    run.addDirectoryArg(b.path("include"));
    run.addFileArg(b.path(prg_path));
    // harbour outputs .c in same directory as input by default
    return run.captureStdOut(); // or addOutputFileArg
}
```

### 2.3 Platform Conditionals

```zig
const os = target.result.os.tag;

// GT drivers — conditional
if (os == .windows) {
    _ = addCLib(b, "gtwin", "src/rtl/gtwin", &.{"gtwin.c"}, target, optimize);
    _ = addCLib(b, "gtwvt", "src/rtl/gtwvt", &.{"gtwvt.c"}, target, optimize);
}
if (os == .linux) {
    _ = addCLib(b, "gttrm", "src/rtl/gttrm", &.{"gttrm.c"}, target, optimize);
    if (b.option(bool, "x11", "Build gtxwc (X11)") orelse true) {
        const gtxwc = addCLib(b, "gtxwc", "src/rtl/gtxwc", &.{"gtxwc.c"}, target, optimize);
        gtxwc.linkSystemLibrary("X11");
    }
}
// Always built:
_ = addCLib(b, "gtstd", "src/rtl/gtstd", &.{"gtstd.c"}, target, optimize);
_ = addCLib(b, "gtcgi", "src/rtl/gtcgi", &.{"gtcgi.c"}, target, optimize);
_ = addCLib(b, "gtpca", "src/rtl/gtpca", &.{"gtpca.c"}, target, optimize);
```

### 2.4 Third-Party Libraries

```zig
// PCRE — bundled by default
const hbpcre = addCLib(b, "hbpcre", "src/3rd/pcre", &PCRE_SRCS, target, optimize);
hbpcre.defineCMacro("PCRE_STATIC", null);
hbpcre.defineCMacro("SUPPORT_UTF", null);
hbpcre.defineCMacro("SUPPORT_UCP", null);

// ZLIB — bundled by default
const hbzlib = addCLib(b, "hbzlib", "src/3rd/zlib", &ZLIB_SRCS, target, optimize);
if (os != .windows) hbzlib.defineCMacro("HAVE_UNISTD_H", null);
```

### 2.5 System Libraries

```zig
if (os == .windows) {
    for (&.{ "kernel32", "user32", "gdi32", "winmm", "winspool", "ws2_32" }) |lib| {
        harbour.linkSystemLibrary(lib);
    }
} else {
    harbour.linkSystemLibrary("m");
    harbour.linkSystemLibrary("dl");
    harbour.linkSystemLibrary("pthread");
    harbour.linkSystemLibrary("rt");
}
```

### 2.6 YACC Handling

For Phase Z.1, we use the pre-generated `.yyc` files (checked into the repo).
No Bison dependency required at build time.

```zig
// Copy pre-generated parser source
const copy_parser = b.addSystemCommand(&.{ "cp" });
copy_parser.addFileArg(b.path("src/compiler/harboury.yyc"));
const parser_c = copy_parser.addOutputFileArg("harboury.c");
// Also copy header
const copy_header = b.addSystemCommand(&.{ "cp" });
copy_header.addFileArg(b.path("src/compiler/harboury.yyh"));
_ = copy_header.addOutputFileArg("harboury.h");

hbcplr.addCSourceFileFromLazyPath(parser_c, &HARBOUR_CFLAGS);
hbcplr.step.dependOn(&copy_header.step);
```

---

## 3. Memory Layout Impact

None. `build.zig` is a build system change. No C struct, header, or source
file is modified. The output binaries are compiled from the same source with
the same flags.

---

## 4. Coexistence Strategy

Both `make` and `zig build` work side-by-side throughout the migration:

| Phase | `make` | `zig build` | Output Dir |
|-------|--------|-------------|------------|
| Z.0 (done) | Full build | N/A | `bin/`, `lib/`, `obj/` |
| Z.1 | Full build | Compiler only | `zig-out/bin/` |
| Z.2 | Full build | All C libs | `zig-out/lib/` |
| Z.3 | Full build | Full build | `zig-out/` |
| Z.4 | Full + contribs | Full + contribs | `zig-out/` |
| Z.5 | Removed | Full + contribs | `zig-out/` |

Output directories are separate. No interference.

---

## 5. Estimated build.zig Size

| Section | Lines (est.) |
|---------|-------------|
| Source file list constants | ~150 |
| Helper functions (addCLib, addPrgToC, addExe) | ~80 |
| Phase 1: Bootstrap | ~20 |
| Phase 2: Runtime libraries | ~60 |
| Phase 2: GT drivers (conditional) | ~30 |
| Phase 2: RDD drivers | ~20 |
| Phase 2: Third-party libs | ~20 |
| Phase 3: Binaries | ~15 |
| System library linking | ~15 |
| Build options and test step | ~20 |
| **Total** | **~430** |

---

## 6. Alternatives Considered

### Alternative A: CMake

Widely used, good IDE integration. Rejected because:
- Does not provide a C compiler (still needs GCC/Clang/MSVC installed)
- Cross-compilation requires toolchain files per target
- `CMakeLists.txt` would be ~800-1200 lines (vs ~430 for build.zig)
- No content-addressed caching

### Alternative B: Meson + Ninja

Modern, fast. Rejected because:
- Python dependency for Meson
- No built-in C compiler
- Cross-compilation requires cross files
- Two tools instead of one

### Alternative C: Keep Make, just fix dependency tracking

This is what Phase Z.0 did. It solves the stale-object problem but not:
- Cross-compilation complexity (50+ .mk files)
- Dead platform configs (~1,500 lines)
- hbmk2 complexity (16,905 lines)
- Build parallelism correctness (fragile jobserver)

Phase Z.0 is the right short-term fix. Zig is the right long-term replacement.

---

[<- Index](../INDEX.md) · [Map](../MAP.md) · [BRIEF](BRIEF.md) · **DESIGN** · [PLAN](IMPLEMENTATION_PLAN.md) · [TESTS](TEST_PLAN.md) · [AUDIT](AUDIT.md)
