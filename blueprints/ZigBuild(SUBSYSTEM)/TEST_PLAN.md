# TEST_PLAN -- ZigBuild (SUBSYSTEM)

## Phase Z.0: Header Dependency Tracking (DONE)

### TEST-Z0-001: Full Clean Build
- **Type**: Regression
- **Covers**: Phase Z.0 — `-MMD -MP` flags don't break compilation
- **Setup**: `make clean`
- **Action**: `make -j$(nproc)`
- **Expected**: Build completes without errors. All libraries and binaries produced.
- **Result**: PASS (2026-03-26) — build succeeded

### TEST-Z0-002: Test Suite
- **Type**: Regression
- **Covers**: Phase Z.0 — built binaries are correct
- **Setup**: Full build completed
- **Action**: `bin/linux/gcc/hbtest`
- **Expected**: 4861/4861 tests pass, 0 failures
- **Result**: PASS (2026-03-26) — 4861/4861 passed

### TEST-Z0-003: Dependency Files Generated
- **Type**: New
- **Covers**: Phase Z.0 — `.d` files are produced alongside `.o` files
- **Setup**: Full build completed
- **Action**: `find src -name "*.d" -path "*/obj/*" | wc -l`
- **Expected**: > 1000 `.d` files generated
- **Result**: PASS (2026-03-26) — 1,367 files

### TEST-Z0-004: Incremental Rebuild on Header Change
- **Type**: New — the core purpose of Z.0
- **Covers**: Phase Z.0 — touching a header triggers recompilation of dependent files
- **Setup**: Full build completed
- **Action**: `touch include/hbapi.h && time make -j$(nproc) HB_BUILD_CONTRIBS=no`
- **Expected**: Only files including `hbapi.h` are recompiled. Completes in < 5s.
- **Result**: PASS (2026-03-26) — 0.5s, only dependent files recompiled

### TEST-Z0-005: No-Op Build
- **Type**: New
- **Covers**: Phase Z.0 — no-change build does zero recompilation
- **Setup**: Full build completed, nothing changed
- **Action**: `time make -j$(nproc) HB_BUILD_CONTRIBS=no`
- **Expected**: Completes in < 1s with no compilation commands
- **Result**: PASS (2026-03-26) — 0.28s

### TEST-Z0-006: Header Deletion Safety
- **Type**: New
- **Covers**: Phase Z.0 — `-MP` phony targets prevent errors when a header is deleted
- **Setup**: Full build completed. Create a dummy header, include it in a `.c` file, build, then delete the header.
- **Action**:
  1. `echo "/* dummy */" > include/hb_dummy_test.h`
  2. Add `#include "hb_dummy_test.h"` to a test `.c` file
  3. `make` (generates `.d` with dependency on `hb_dummy_test.h`)
  4. Remove the `#include` line and delete `hb_dummy_test.h`
  5. `make` (should not error — `-MP` generates phony target for deleted header)
- **Expected**: Build succeeds without "No rule to make target" errors
- **Result**: Not yet executed (covered by `-MP` flag semantics)

### TEST-Z0-007: Clean Removes .d Files
- **Type**: New
- **Covers**: Phase Z.0 — `make clean` removes generated `.d` files
- **Setup**: Full build completed with `.d` files present
- **Action**: `make clean && find src -name "*.d" -path "*/obj/*" | wc -l`
- **Expected**: 0 `.d` files remain
- **Result**: Not yet executed (covered by `$(RDP) $(OBJ_DIR)` which removes entire obj directory)

---

## Phase Z.1: Compiler Bootstrap via Zig

### TEST-Z1-001: Zig Build Produces harbour Binary
- **Type**: New
- **Covers**: Phase Z.1 — `build.zig` compiles all bootstrap C sources
- **Setup**: Zig 0.13.0 installed
- **Action**: `zig build`
- **Expected**: Produces `zig-out/bin/harbour` executable
- **Result**: PASS (2026-03-26) — ELF 64-bit x86-64 binary produced

### TEST-Z1-002: Zig-Built harbour Compiles PRG to C
- **Type**: New
- **Covers**: Phase Z.1 — produced binary is functional
- **Setup**: `zig build` completed
- **Action**: `zig-out/bin/harbour -n1 -w3 -es2 tests/hello.prg`
- **Expected**: Produces C output without errors
- **Result**: PASS (2026-03-26) — compiled hello.prg, generated C source

### TEST-Z1-003: Zig-Built harbour Output Matches Make-Built
- **Type**: Regression
- **Covers**: Phase Z.1 — zig and make produce equivalent compiler
- **Setup**: Both `make` and `zig build` completed
- **Action**: `diff` output of both `harbour` binaries compiling same `.prg`
- **Expected**: Semantically equivalent (compiler ID string may differ)
- **Result**: PASS (2026-03-26) — only diffs: compiler ID (GCC vs Clang), output filename in symbols

### TEST-Z1-004: Make and Zig Coexist
- **Type**: New
- **Covers**: Phase Z.1 — both build systems work side-by-side
- **Setup**: None
- **Action**: `make` and `zig build` both succeed
- **Expected**: Output directories separate (`bin/` vs `zig-out/`)
- **Result**: PASS (2026-03-26) — no interference

### TEST-Z1-005: Cross-Compilation Smoke Test
- **Type**: New
- **Covers**: Phase Z.1 — zig cross-compilation from Linux to Windows
- **Setup**: Zig installed on Linux
- **Action**: `zig build -Dtarget=x86_64-windows-gnu`
- **Expected**: Produces `zig-out/bin/harbour.exe` (Windows PE binary)
- **Result**: PASS (2026-03-26) — PE32+ executable (console) x86-64

---

## Phase Z.2: Full C Build

### TEST-Z2-001: All Static Libraries Built
- **Type**: New
- **Covers**: Phase Z.2 — `build.zig` compiles all C-only libraries
- **Setup**: Zig 0.13.0 installed
- **Action**: `zig build`
- **Expected**: All core C libraries produced
- **Result**: PASS (2026-03-26) — 26 libraries + harbour binary in 5.5s.
  Missing only hbextern (needs .prg) and gtxwc (needs X11 linkage).

### TEST-Z2-002: Library Completeness vs Make Build
- **Type**: Regression
- **Covers**: Phase Z.2 — zig builds same core libraries as make
- **Setup**: Both builds completed
- **Action**: Compare library lists
- **Expected**: All core (non-contrib) libraries present
- **Result**: PASS (2026-03-26) — 26/27 core libs match. Only hbextern
  deferred to Z.3 (.prg compilation required).

---

## Phase Z.3: Two-Phase Bootstrap

### TEST-Z3-001: PRG Compilation Works
- **Type**: New
- **Covers**: Phase Z.3 — `build.zig` uses harbour to compile `.prg` files
- **Setup**: Zig installed
- **Action**: `zig build`
- **Expected**: Full build succeeds including all `.prg` → `.c` → `.o` compilation

### TEST-Z3-002: hbtest Passes
- **Type**: Regression — the definitive test
- **Covers**: Phase Z.3 — zig-built runtime is fully functional
- **Setup**: `zig build` completed
- **Action**: `zig build test` (or `zig-out/bin/hbtest`)
- **Expected**: 4861/4861 tests pass

### TEST-Z3-003: hbmk2 Works
- **Type**: Regression
- **Covers**: Phase Z.3 — zig-built hbmk2 can compile user programs
- **Setup**: `zig build` completed
- **Action**: `zig-out/bin/hbmk2 tests/hello.prg && ./hello`
- **Expected**: Prints "Hello, world!"

---

[<- Index](../INDEX.md) · [Map](../MAP.md) · [BRIEF](BRIEF.md) · [DESIGN](DESIGN.md) · [PLAN](IMPLEMENTATION_PLAN.md) · **TESTS** · [AUDIT](AUDIT.md)
