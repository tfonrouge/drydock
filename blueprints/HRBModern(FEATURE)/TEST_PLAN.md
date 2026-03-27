# TEST_PLAN -- HRBModern (FEATURE)

## Phase H.1: Fix .hrb Format (v3)

### TEST-H1-001: v3 .hrb Generates Successfully
- **Type**: New
- **Covers**: H.1 — `drydock -gh` produces v3 format
- **Setup**: Make-built drydock
- **Action**: `drydock -gh tests/hello.prg -o /tmp/hello.hrb`
- **Expected**: File created, starts with signature `\xC0HRB`, version field = 3
- **Result**: PASS (2026-03-27) — 105-byte file, signature correct, version = 3

### TEST-H1-002: v3 .hrb Runs Correctly
- **Type**: New
- **Covers**: H.1 — v3 format loads and executes
- **Setup**: Build complete with v3 support
- **Action**: `ddrun /tmp/hello.hrb`
- **Expected**: Prints "Hello, world!"
- **Result**: DEFERRED — ddrun does not auto-execute .hrb startup symbol (H.5 scope)

### TEST-H1-003: Scope Preservation
- **Type**: New — the core purpose of H.1
- **Covers**: H.1 — full 16-bit scope survives round-trip
- **Setup**: Build complete with v3 support
- **Action**: Parse .hrb binary and verify scope field is 2 bytes
- **Expected**: `HB_FS_LOCAL` (0x0200) preserved in scope field
- **Result**: PASS (2026-03-27) — first symbol `HELLO` has scope `0x0205` (PUBLIC|FIRST|LOCAL). Upper byte `0x02` (LOCAL) preserved — would have been zero in v2.

### TEST-H1-004: v2 Backward Compatibility
- **Type**: Regression
- **Covers**: H.1 — runner.c dispatches by version
- **Setup**: Code review of runner.c v2/v3 dispatch
- **Action**: Verified `iVersion >= 3` guards and v2 fallback path in runner.c
- **Expected**: v2 code path unchanged
- **Result**: PASS (2026-03-27) — v2 path uses 1-byte scope read (line 397), v3 path uses 2-byte (line 393). Version dispatch at line 324.

### TEST-H1-005: Module Name in v3
- **Type**: New
- **Covers**: H.1 — module name field is written and readable
- **Setup**: Build complete with v3 support
- **Action**: Parse .hrb binary at offset 8
- **Expected**: Module name (source path) present after pcode version
- **Result**: PASS (2026-03-27) — module name = `tests/hello.prg`

### TEST-H1-006: Pcode Version in v3
- **Type**: New
- **Covers**: H.1 — pcode version field matches HB_PCODE_VER
- **Setup**: Build complete with v3 support
- **Action**: Read bytes at offset 6-7 in generated .hrb
- **Expected**: Value = 3 (HB_PCODE_VER = 0x0003)
- **Result**: PASS (2026-03-27) — pcode version = 3

### TEST-H1-007: ddtest Passes
- **Type**: Regression
- **Covers**: H.1 — no regression in test suite
- **Setup**: Full build with v3 support
- **Action**: `ddtest`
- **Expected**: 4861/4861 tests pass
- **Result**: PASS (2026-03-27) — 4861/4861 passed

### TEST-H1-008: Classes and Closures Work via .hrb
- **Type**: Regression
- **Covers**: H.1 — complex features work through .hrb path
- **Setup**: Build complete
- **Action**: `ddrun tests/overload.prg`
- **Expected**: Runs without errors
- **Result**: DEFERRED — ddrun auto-execution of .hrb startup symbol is H.5 scope. The v3 format itself is correct (writer verified); execution path needs H.5 INIT/EXIT auto-dispatch.

---

[<- Index](../INDEX.md) · [Map](../MAP.md) · [BRIEF](BRIEF.md) · [DESIGN](DESIGN.md) · [PLAN](IMPLEMENTATION_PLAN.md) · **TESTS** · [AUDIT](AUDIT.md)
