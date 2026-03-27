# BRIEF -- HRBModern (FEATURE)

## Identity

| Field | Value |
|-------|-------|
| **Name** | HRBModern |
| **Mode** | FEATURE |
| **Tier** | 0 — Build Infrastructure |
| **Component** | Compiler — `src/compiler/genhrb.c`, VM — `src/vm/runner.c`, CLI — `src/main/` |
| **Status** | PLANNING |

---

## 1. Motivation

The Harbour compiler has a `.hrb` bytecode backend (`harbour -gh`) that
produces **identical pcode** to the C backend — without generating or
compiling any C code. The VM (`hb_vmExecute`) cannot tell the difference:
both paths deliver the same byte stream and symbol table.

**Confirmed by testing:**
- `harbour -gh hello.prg` → 65-byte `.hrb` file (vs. 3,990 bytes of `.c`)
- `hbrun hello.hrb` → runs correctly (classes, closures, code blocks all work)
- `hbrun hello.prg` → compiles in-memory and runs (no C at all)
- The generated C is pure ceremony: `static const HB_BYTE pcode[] = {...}; hb_vmExecute(pcode, symbols);`

**But `.hrb` is treated as a second-class citizen.** It has format bugs, no
bundling support, and no way to produce standalone executables. This forces
the entire build system through the `.prg → .c → gcc → .o → link` pipeline
even though the C step adds zero value for development builds.

Making `.hrb` first-class unlocks:
- **Sub-second development builds** — change a `.prg`, run `harbour -gh`, done
- **Simpler build system** — `zig build` only compiles C; `.prg` goes straight to `.hrb`
- **Faster CI** — 112 `.prg` files compile to `.hrb` in milliseconds vs. seconds through C
- **Portable distribution** — `.hrb` files run on any platform with the Harbour VM

---

## 2. Current `.hrb` Format

Binary format from `src/compiler/genhrb.c` (171 lines):

```
[0:4]   Signature: 0xC0 'H' 'R' 'B'
[4:6]   Version: 2 (uint16 LE)
[6:10]  Symbol count (uint32 LE)
[10:?]  Symbol table:
          name (null-terminated string)
          scope (1 byte) ← TRUNCATED: upper byte stripped
          type (1 byte): SYM_NOLINK | SYM_FUNC | SYM_EXTERN | SYM_DEFERRED
[?:?]   Function count (uint32 LE)
[?:EOF] Function data:
          name (null-terminated string)
          size (uint32 LE)
          pcode bytes (raw)
```

### Known Bugs

1. **Scope truncation** (`genhrb.c:94-99`): the upper byte of the symbol
   scope is stripped during serialization. The code has a `FIXME` comment:
   > "this conversion strips upper byte from symbol scope. Now we added
   > workaround for it [...] but we should create new format for .hrb files"

2. **No INIT/EXIT section markers**: `.hrb` files don't encode INIT/EXIT
   procedures. They only execute when explicitly called via `hb_hrbDo()`.
   In the C path, `HB_INIT_SYMBOLS_BEGIN` handles this automatically.

3. **No module metadata**: no source file path, no compilation timestamp,
   no pcode version, no compiler version. Makes debugging difficult.

---

## 3. Proposed Changes

### Phase H.1: Fix `.hrb` Format (3 days)

Bump `.hrb` version from 2 to 3. Add:

| Field | Size | Purpose |
|-------|------|---------|
| Scope (full) | 2 bytes (uint16) | Fix truncation — store complete `HB_FS_*` flags |
| INIT/EXIT flags | 1 byte per symbol | Mark INIT/EXIT procedures for auto-execution on load |
| Module name | null-terminated string | Source file path for debugging |
| Pcode version | 2 bytes (uint16) | `HB_PCODE_VER` for compatibility checking |
| Compiler version | null-terminated string | Build provenance |

**Backward compatibility**: `runner.c` already checks the version field.
Version 2 files continue to load with the existing truncation workaround.
Version 3 files use the new full-scope format.

**Files**: `src/compiler/genhrb.c` (writer), `src/vm/runner.c` (reader),
`include/hbvmpub.h` (version constant).

### Phase H.2: `.hrb` Bundling (3 days)

Combine multiple `.hrb` files into a single `.hrb` archive:

```bash
# Compile multiple .prg to .hrb
harbour -gh src/rtl/tscalar.prg -o obj/hrb/
harbour -gh src/rtl/typefile.prg -o obj/hrb/
# ... 76 files

# Bundle into single archive
harbour --hrb-bundle obj/hrb/*.hrb -o lib/hbrtl.hrb
```

Archive format: simple concatenation with a table of contents header.
Each entry is a complete `.hrb` v3 file. The TOC maps module names to
offsets for O(1) lookup.

```
[0:4]   Signature: 0xC0 'H' 'B' 'L'  (HRB Library)
[4:8]   Entry count (uint32 LE)
[8:?]   TOC entries:
          module name (null-terminated)
          offset (uint32 LE)
          size (uint32 LE)
[?:EOF] Concatenated .hrb v3 files
```

The VM loads a bundle with a single `hb_hrbLoad()` call, registering all
modules' symbols at once.

**New CLI flag**: `harbour --hrb-bundle <files> -o <output.hrb>`

### Phase H.3: `.hrb` Embedding (3 days)

Embed `.hrb` bytecode in a C source file as a static byte array — but
without the `HB_FUNC()` wrappers. The launcher loads embedded bytecode at
startup via `hb_hrbLoad()`:

```bash
# Generate embedding .c file from .hrb bundle
harbour --hrb-embed lib/hbrtl.hrb -o src/rtl/hbrtl_hrb.c
```

Generates:
```c
/* Auto-generated — do not edit */
#include "hbapi.h"
static const HB_BYTE s_hbrtl_hrb[] = {
    0xC0, 0x48, 0x42, 0x4C, /* ... bundle bytes ... */
};
const HB_BYTE * hb_hbrtl_hrb_data( HB_SIZE * pnSize ) {
    *pnSize = sizeof( s_hbrtl_hrb );
    return s_hbrtl_hrb;
}
```

The VM startup code calls `hb_hbrtl_hrb_data()` and feeds it to
`hb_hrbLoad()`. Result: standalone executable with embedded `.hrb`
bytecode, **no per-function C wrappers**.

**Comparison with current C path:**
- Current: 76 `.prg` → 76 `.c` files (130+ lines each) → 76 `.o` files → archive
- Proposed: 76 `.prg` → 76 `.hrb` → 1 bundle → 1 `.c` embedding file → 1 `.o`

The C compiler processes ONE small file instead of 76 generated ones.

### Phase H.4: Compiler CLI Enhancements (2 days)

Add flags to `harbour` for development workflow:

| Flag | Output | Purpose |
|------|--------|---------|
| `-ast` | stdout or file | Dump the expression tree (requires PersistentAST, Phase E) |
| `-dp` | stdout or file | Disassemble pcode to human-readable opcodes |
| `-ge2` or `-gejson` | stderr | JSON-formatted error/warning output for LSP/IDE |
| `--hrb-bundle` | `.hrb` archive | Bundle multiple `.hrb` into one (Phase H.2) |
| `--hrb-embed` | `.c` file | Generate C embedding from `.hrb` bundle (Phase H.3) |

The `-dp` (disassemble pcode) flag outputs:

```
MAIN:
  0000  LINE          5
  0003  PUSHSYM       QOUT
  0006  PUSHSTRSHORT  "Hello, world!"
  0013  FUNCTIONSHORT 1
  0016  LINE          7
  0019  ENDPROC
```

This is invaluable for compiler development, optimization work, and
debugging. Currently there is no way to inspect what the compiler generates
without reading raw hex bytes.

### Phase H.5: Auto-Execute INIT/EXIT in `.hrb` (1 day)

When `runner.c` loads a v3 `.hrb` file, automatically execute symbols
marked with `HB_FS_INIT` after registration, and queue `HB_FS_EXIT`
symbols for cleanup. This matches the behavior of the C path where
`HB_INIT_SYMBOLS_BEGIN` handles INIT/EXIT via `#pragma startup` or
data segment initialization.

---

## 4. Affected Files

| File | Lines | Change |
|------|-------|--------|
| `src/compiler/genhrb.c` | 171 | H.1: full scope, metadata. H.2: bundling writer |
| `src/vm/runner.c` | ~600 | H.1: v3 reader. H.2: bundle loader. H.3: embedding loader. H.5: INIT/EXIT |
| `src/compiler/cmdcheck.c` | ~300 | H.4: new CLI flags (`-dp`, `-gejson`, `--hrb-bundle`, `--hrb-embed`) |
| `src/compiler/hbmain.c` | 4,526 | H.4: pcode disassembler, JSON error formatter |
| `include/hbvmpub.h` | ~200 | H.1: version constant, embedding API |
| `src/main/harbour.c` | ~100 | H.4: dispatch new CLI commands |

## 5. Compatibility Stance

**Target: 100% backward compatibility.**

- `.hrb` v2 files continue to load — `runner.c` dispatches by version
- No change to `.c` generation or C path behavior
- New CLI flags are additive — no existing flag changes meaning
- The C path remains available for release/distribution builds
- `.hrb` v3 is a strict superset of v2 (adds fields, doesn't remove any)

## 6. Performance Stance

**Must improve build speed. No runtime regression.**

- `.prg → .hrb` is faster than `.prg → .c` (less output to write)
- `.hrb` loading via `hb_hrbLoad()` has negligible overhead (~1ms for
  typical module sizes) — already proven by `hbrun`
- Bundled `.hrb` loading is a single `mmap()` or `read()` instead of
  opening 76 separate `.hrb` files
- Embedded `.hrb` has zero file I/O — bytes are in the executable's
  data segment

## 7. Dependencies

| Dependency | Status | Notes |
|------------|--------|-------|
| *(none)* | — | H.1-H.3, H.5 are independent of all other workstreams |
| PersistentAST (Phase E) | PLANNING | H.4 `-ast` flag requires retained AST; other H.4 flags are independent |

**Enables:**
- ZigBuild Phase Z.3 — `.hrb`-first build mode eliminates C compilation of `.prg` files
- LSPServer (Phase I) — JSON error output provides structured diagnostics

**Does not block and is not blocked by** Tier 1 workstreams (RefactorHvm,
ScalarClasses, etc.). Can proceed in parallel.

## 8. Risks

| Risk | Severity | Mitigation |
|------|----------|------------|
| `.hrb` v3 format breaks third-party `.hrb` loaders | Low | Version field gating; v2 continues to work |
| INIT/EXIT ordering differs from C path | Medium | Document ordering; match C path behavior exactly |
| Embedded `.hrb` increases executable size | Low | Pcode is compact (~10x smaller than equivalent `.o`); net size decrease vs. current C path |
| Bundle format not future-proof | Low | Simple format with version field; easy to extend |

## 9. Estimated Scope

| Phase | Effort | Can Ship Independently |
|-------|--------|----------------------|
| H.1: Fix `.hrb` format (v3) | 3 days | Yes |
| H.2: `.hrb` bundling | 3 days | Yes (after H.1) |
| H.3: `.hrb` embedding | 3 days | Yes (after H.2) |
| H.4: CLI enhancements (`-dp`, `-gejson`, etc.) | 2 days | Yes (independent) |
| H.5: Auto INIT/EXIT in `.hrb` | 1 day | Yes (after H.1) |
| **Total** | **~2 weeks** | |

---

[<- Index](../INDEX.md) · [Map](../MAP.md) · **BRIEF**
