# TEST_PLAN -- HRBModern (FEATURE)

## Phase H.1: Fix .hrb Format (v3)

### TEST-H1-001: v3 .hrb Generates Successfully
- **Type**: New
- **Covers**: H.1 — `harbour -gh` produces v3 format
- **Setup**: Zig-built or Make-built harbour
- **Action**: `harbour -gh tests/hello.prg -o /tmp/hello.hrb`
- **Expected**: File created, starts with signature `\xC0HRB`, version field = 3

### TEST-H1-002: v3 .hrb Runs Correctly
- **Type**: New
- **Covers**: H.1 — v3 format loads and executes
- **Setup**: Build complete with v3 support
- **Action**: `hbrun /tmp/hello.hrb`
- **Expected**: Prints "Hello, world!"

### TEST-H1-003: Scope Preservation
- **Type**: New — the core purpose of H.1
- **Covers**: H.1 — full 16-bit scope survives round-trip
- **Setup**: Build complete with v3 support
- **Action**: Compile a `.prg` with INIT/EXIT/STATIC/PUBLIC/LOCAL functions
  to `.hrb`, then load and check scope flags are intact
- **Expected**: `HB_FS_PCODEFUNC`, `HB_FS_LOCAL`, `HB_FS_DEFERRED` flags
  preserved (not truncated to low byte)
- **Verification**: Hex dump first 100 bytes; verify scope field is 2 bytes
  and contains correct flag values

### TEST-H1-004: v2 Backward Compatibility
- **Type**: Regression
- **Covers**: H.1 — old v2 .hrb files still load
- **Setup**: Generate a v2 .hrb (from current/make-built harbour), save it.
  Then rebuild harbour with v3 support.
- **Action**: `hbrun old_v2_file.hrb`
- **Expected**: Runs correctly with v2 truncation workaround

### TEST-H1-005: Module Name in v3
- **Type**: New
- **Covers**: H.1 — module name field is written and readable
- **Setup**: Build complete with v3 support
- **Action**: `harbour -gh tests/hello.prg -o /tmp/hello.hrb && xxd /tmp/hello.hrb | head -5`
- **Expected**: Module name (source path) visible in hex dump after pcode version

### TEST-H1-006: Pcode Version in v3
- **Type**: New
- **Covers**: H.1 — pcode version field matches HB_PCODE_VER
- **Setup**: Build complete with v3 support
- **Action**: Check bytes at offset 6-7 in generated .hrb
- **Expected**: Matches current `HB_PCODE_VER` value

### TEST-H1-007: hbtest Passes
- **Type**: Regression
- **Covers**: H.1 — no regression in test suite
- **Setup**: Full build with v3 support
- **Action**: `hbtest`
- **Expected**: 4861/4861 tests pass

### TEST-H1-008: Classes and Closures Work via .hrb
- **Type**: Regression
- **Covers**: H.1 — complex features work through .hrb path
- **Setup**: Build complete
- **Action**: `hbrun tests/overload.prg` (uses classes, operator overloading)
- **Expected**: Runs without errors

---

[<- Index](../INDEX.md) · [Map](../MAP.md) · [BRIEF](BRIEF.md) · [DESIGN](DESIGN.md) · [PLAN](IMPLEMENTATION_PLAN.md) · **TESTS** · [AUDIT](AUDIT.md)
