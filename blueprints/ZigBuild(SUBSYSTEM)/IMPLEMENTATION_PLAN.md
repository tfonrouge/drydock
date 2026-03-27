# IMPLEMENTATION_PLAN -- ZigBuild (SUBSYSTEM)

## Phase Z.0: Header Dependency Tracking -- DONE

- **Milestone**: `make` correctly rebuilds files when headers change
- **Files touched**: `config/linux/gcc.mk`, `config/linux/clang.mk`, `config/c.mk`, `config/prg.mk`
- **Build verification**: `make clean && make && hbtest` — 4861/4861 passed
- **Commit**: `70d3813` (2026-03-26)

---

## Phase Z.1: Compiler Bootstrap via Zig

- **Milestone**: `zig build` produces a working `drydock` compiler binary from
  pure C sources. The binary compiles `tests/hello.prg` to C output.
- **Depends on**: Zig toolchain installed (0.13+ recommended)
- **Estimated effort**: 1 week

### Steps

- [x] **Z.1.1** Create `build.zig` skeleton with target/optimize options, helper
  functions (`addCLib`), and HARBOUR_CFLAGS constant.
- [x] **Z.1.2** Add `hbcommon` library — 20 C files from `src/common/`.
- [x] **Z.1.3** Add `hbnortl` library — 1 C file from `src/nortl/`.
- [x] **Z.1.4** Add `hbpp` library — 4 C files from `src/pp/` (ppcore, pplib,
  pplib2, pptable). Note: `hbpp.c` is the standalone binary, not part of the
  library. `pptable.c` checked in as pre-generated source.
- [x] **Z.1.5** Add YACC handling — copy `harbour.yyc` → `harboury.c` and
  `harbour.yyh` → `harboury.h` via build system command steps.
- [x] **Z.1.6** Add `hbcplr` library — 23 C files from `src/compiler/` plus
  `harboury.c`. Added `src/compiler` as include path for `harboury.h`.
- [x] **Z.1.7** Add `drydock` executable — `src/main/harbour.c` linked against
  hbcplr, hbpp, hbnortl, hbcommon, plus system libs (`-lm` on POSIX,
  `kernel32/user32/ws2_32/winmm` on Windows).
- [x] **Z.1.8** Verify: `zig-out/bin/drydock -n1 -w3 -es2 tests/hello.prg`
  produces C output without errors.
- [x] **Z.1.9** Verify: output of zig-built drydock matches make-built harbour.
  Only differences: compiler ID string (GCC vs Clang) and output filename in
  symbol names. Semantically identical.
- [x] **Z.1.10** Verify: `zig build -Dtarget=x86_64-windows-gnu` produces
  `drydock.exe` (PE32+ executable).
- [x] **Z.1.11** Update blueprint artifacts: TEST_PLAN results, AUDIT.

### Files created

| File | Lines (est.) | Content |
|------|-------------|---------|
| `build.zig` | ~120 | Bootstrap only (Phase 1 of the build graph) |

### Build verification

```bash
zig build && zig-out/bin/drydock -n1 -w3 -es2 tests/hello.prg
diff <(bin/linux/gcc/drydock -n1 -w3 -es2 -o/tmp/make_hello tests/hello.prg && cat /tmp/make_hello.c) \
     <(zig-out/bin/drydock -n1 -w3 -es2 -o/tmp/zig_hello tests/hello.prg && cat /tmp/zig_hello.c)
```

### Rollback

Delete `build.zig`. No other files are modified. `make` continues to work.

### Risks

| Risk | Mitigation |
|------|------------|
| Zig build API changes between versions | Pin zig version in README. Use stable API surface only. |
| YACC copy step doesn't work cross-platform | Use zig's `std.fs.copyFile` instead of shell `cp` |
| drydock binary needs runtime paths | Set `-I` include path via build.zig `addArg` |

---

## Phase Z.2: Full C Build

- **Milestone**: `zig build` compiles all C libraries (hbvm, hbrtl C files,
  hbmacro, hbrdd, hbcpage, hblang, hbdebug, GT drivers, RDD drivers,
  third-party libs). PRG files not yet compiled.
- **Depends on**: Phase Z.1
- **Estimated effort**: 1 week

### Steps

- [x] **Z.2.1** Add hbvm library (hvmall.c amalgamation + 24 unconditional files).
  Add `-DHB_MT_VM` variant as hbvmmt.
- [x] **Z.2.2** Add hbrtl library (217 C files). Add defines
  `-DHB_HAS_PCRE -DPCRE_STATIC -DHB_HAS_ZLIB`. Add include paths for
  `src/3rd/pcre` and `src/3rd/zlib`.
- [x] **Z.2.3** Add hbmacro library (3 C files + macroy.c pre-generated).
- [x] **Z.2.4** Add hbrdd library (20 C files) and 8 RDD driver sub-libraries
  (rddntx, rddcdx, rddfpt, rddnsx, hbsix, hbhsx, nulsys, usrrdd).
- [x] **Z.2.5** Add hbcpage library (170 C files from Makefile).
- [x] **Z.2.6** Add hblang library (38 C files).
- [x] **Z.2.7** Add hbdebug library (1 C file).
- [x] **Z.2.8** Add third-party libraries: hbpcre (20 files, PCRE_STATIC +
  SUPPORT_UTF + SUPPORT_UCP + HAVE_CONFIG_H + HAVE_STDINT_H),
  hbzlib (15 files, HAVE_UNISTD_H on non-Windows).
- [x] **Z.2.9** Add GT drivers — gtstd, gtcgi, gtpca (always), gttrm (Linux/BSD),
  gtwin + gtwvt + gtgui (Windows). Platform-conditional with install.
- [x] **Z.2.10** Verify: `zig build` compiles 26 libraries + drydock binary
  in 5.5 seconds. All core libraries match Make output (missing only
  hbextern which needs .prg, and gtxwc which needs X11).
- [x] **Z.2.11** Update blueprint artifacts.

### Build verification

```bash
zig build
# Compare library contents
for lib in hbcommon hbpp hbcplr hbvm hbrtl hbmacro hbrdd; do
    echo "=== $lib ==="
    diff <(ar t lib/linux/gcc/lib${lib}.a | sort) \
         <(ar t zig-out/lib/lib${lib}.a | sort)
done
```

### Rollback

Revert `build.zig` to Z.1 state. Make continues to work.

---

## Phase Z.3: Two-Phase Bootstrap

- **Milestone**: `zig build` compiles `.prg` files using the harbour compiler
  built in Phase 1, then compiles the generated C. Full build works end-to-end.
  `zig build test` runs hbtest and passes 4861/4861.
- **Depends on**: Phase Z.2
- **Estimated effort**: 1 week

### Steps

- [x] **Z.3.1** Implement `compilePrg` helper — uses `bin/prg2c.sh` +
  `captureStdOut()` + `cp` rename to produce `.c` files with correct extension.
- [x] **Z.3.2** Add PRG files to hbvm (1 file: harbinit.prg).
- [x] **Z.3.3** Add PRG files to hbrtl (74 files).
- [x] **Z.3.4** Add PRG files to hbrdd (12 files) and hbsix (3 files).
- [x] **Z.3.5** Add PRG files to hbdebug (13 files).
- [x] **Z.3.6** Add hbextern (1 PRG file, empty C source list + PRG).
- [x] **Z.3.7** Build ddtest (13 PRG files + rt_miscc.c) linked against runtime libs.
  Note: `gtsys.c` removed from hbrtl to avoid duplicate symbol with PRG REQUEST stubs.
- [ ] **Z.3.8** Build ddmake — deferred (requires full runtime, complex hbmk2.prg).
- [x] **Z.3.9** Add `zig build test` step that runs ddtest.
- [x] **Z.3.10** Verify: ddtest runs. Minor error format divergence on 1 test
  (Array(-1) error message includes extra args). 4860/4861 equivalent.
- [ ] **Z.3.11** Deferred — ddmake not yet built by zig.
- [x] **Z.3.12** Update blueprint artifacts.

### Key milestone

Make is now optional for the core build (except ddmake/contribs). The zig
build produces `drydock` compiler + 27 libraries + `ddtest` executable.

### Build verification

```bash
zig build                     # produces drydock + ddtest + 27 libraries
zig-out/bin/ddtest            # runs test suite
```

### Rollback

Revert `build.zig` to Z.2 state. Make continues to work.

---

## Phase Z.4: Contrib Migration

- **Milestone**: All 74 contrib packages build via `zig build`.
- **Depends on**: Phase Z.3
- **Estimated effort**: 2 weeks

### Approach

Each contrib has a `.hbp` project file (declarative). Write a translator or
manual `build.zig` fragments for each. Group into:

1. Pure PRG contribs (no external deps) — mechanical
2. C+PRG contribs with bundled 3rd-party — straightforward
3. C+PRG contribs with system dependencies (curl, mysql, pgsql, etc.) — need
   `linkSystemLibrary` + optional detection

### Rollback

Contrib builds can remain on hbmk2 indefinitely. This phase is incremental.

---

## Phase Z.5: Make Removal

- **Milestone**: `config/` directory deleted. All `Makefile` files deleted.
  CI uses `zig build` exclusively.
- **Depends on**: Phase Z.3 (core) + Z.4 (contribs, can be partial)
- **Estimated effort**: 1 week

### Steps

- [ ] Delete `config/` (121 .mk files, 7,545 lines)
- [ ] Delete all `Makefile` files (60 files, 2,343 lines)
- [ ] Delete `win-make.exe`, `dos-make.exe`, `os2-make.exe`
- [ ] Update README.md build instructions
- [ ] Update CLAUDE.md build commands
- [ ] Update CI configuration

### Rollback

`git revert`. The deleted files are in git history.

---

## Phase Z.6: hbmk2 Simplification

- **Milestone**: hbmk2 reduced from 16,905 lines to ~3,000 lines. Functions as
  a project tool that invokes `zig build` rather than driving compilation itself.
- **Depends on**: Phase Z.3
- **Estimated effort**: 2-3 weeks

### Rollback

Keep old hbmk2 in a branch. The `.hbp` format is preserved.

---

## Risk Register

| Risk | Phase | Severity | Mitigation |
|------|-------|----------|------------|
| Zig API breaks between versions | All | Medium | Pin version in CI; use stable API surface only |
| PRG→C output path differs from expected | Z.3 | High | Test with multiple .prg files; capture stdout vs file output |
| Contrib system deps not detected | Z.4 | Medium | Fall back to hbmk2 for affected contribs |
| Team resistance to new tool | Z.5 | Low | Long coexistence period (Z.1-Z.4); both systems work |
| Generated C from drydock contains absolute paths | Z.3 | Medium | Verify with diff; strip paths if needed |

---

[<- Index](../INDEX.md) · [Map](../MAP.md) · [BRIEF](BRIEF.md) · [DESIGN](DESIGN.md) · **PLAN** · [TESTS](TEST_PLAN.md) · [AUDIT](AUDIT.md)
