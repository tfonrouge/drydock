# TEST_PLAN -- RefactorHvm (SUBSYSTEM)

## Phase 0: Dead Code Removal

### TEST-R0-001: Full Build
- **Type**: Regression
- **Covers**: R0a-R0d — deleted code doesn't break compilation
- **Setup**: Incremental build (hvm.c changed)
- **Action**: `make -j$(nproc) HB_BUILD_CONTRIBS=no`
- **Expected**: Build completes without errors
- **Result**: PASS (2026-03-27)

### TEST-R0-002: Test Suite
- **Type**: Regression
- **Covers**: R0a-R0d — no behavior change
- **Setup**: Full build completed
- **Action**: `bin/linux/gcc/ddtest`
- **Expected**: 4861/4861 tests pass
- **Result**: PASS (2026-03-27) — 4861/4861 passed

### TEST-R0-003: Zig Build
- **Type**: Regression
- **Covers**: R0a-R0d — zig build unaffected
- **Setup**: Zig 0.13.0 installed
- **Action**: `zig build`
- **Expected**: Build completes, `zig-out/bin/drydock --version` works
- **Result**: Not yet executed (zig build will pick up the change on next run)

### TEST-R0-004: Dead Functions Removed
- **Type**: New
- **Covers**: R0a — 12 dead functions deleted from hvm.c
- **Action**: `grep -c "ThenInt\|EqualInt" src/vm/hvm.c`
- **Expected**: 0 matches
- **Result**: PASS (2026-03-27) — 0 matches. 723 lines removed (10275-10997).

### TEST-R0-005: Declarations Removed
- **Type**: New
- **Covers**: R0b — declarations removed from hbxvm.h
- **Action**: `grep -c "ThenInt\|EqualInt" include/hbxvm.h`
- **Expected**: 0 matches
- **Result**: PASS (2026-03-27) — 0 matches. 12 declarations removed.

### TEST-R0-006: Exports Removed
- **Type**: New
- **Covers**: R0c — exports removed from harbour.def
- **Action**: `grep -c "ThenInt\|EqualInt" src/harbour.def`
- **Expected**: 0 matches
- **Result**: PASS (2026-03-27) — 0 matches. 12 exports removed.

### TEST-R0-007: Dead #if 0 Block Removed
- **Type**: New
- **Covers**: R0d — hash equality dead code in hb_vmEqual deleted
- **Action**: Verify `#if 0` block at former line 4045 is gone
- **Expected**: Block removed
- **Result**: PASS (2026-03-27) — 10 lines removed from hb_vmEqual. Total: 733 lines removed from hvm.c (12572 → 11839).

---

[<- Index](../INDEX.md) · [Map](../MAP.md) · [BRIEF](BRIEF.md) · **TESTS** · [AUDIT](AUDIT.md)
