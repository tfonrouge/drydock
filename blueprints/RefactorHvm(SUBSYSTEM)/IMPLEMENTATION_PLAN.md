# IMPLEMENTATION_PLAN -- RefactorHvm (SUBSYSTEM)

## Phase 0: Dead Code Removal -- DONE (2026-03-27, `0ec787c`)

733 lines removed. 12 dead functions + 1 `#if 0` block. ddtest 4861/4861 passed.

---

## Phase 1: Operator Deduplication (2-3 days)

- **Milestone**: 4 ordering comparisons factored into 1. Inc/Dec factored into 1.
  3 xvm*ByInt factored into 1. ~350 lines saved. ddtest identical results.

### Steps

- [ ] **R1a.1** Create `hb_vmCompare()` with comparison enum parameter.
  Implement the shared cascade: STRING→NUMINT→NUMERIC→DATETIME→LOGICAL→objOperatorCall.
- [ ] **R1a.2** Rewrite `hb_vmLess`, `hb_vmLessEqual`, `hb_vmGreater`,
  `hb_vmGreaterEqual` as thin wrappers calling `hb_vmCompare()`.
- [ ] **R1a.3** Verify: `ddtest` — 4861/4861 pass.
- [ ] **R1b.1** Create `hb_vmIncDec()` with direction parameter (+1/-1).
  Implement shared cascade: INTEGER→LONG→DOUBLE→DATETIME→objOperatorCall.
- [ ] **R1b.2** Rewrite `hb_vmInc`, `hb_vmDec` as wrappers.
- [ ] **R1b.3** Verify: `ddtest` — 4861/4861 pass.
- [ ] **R1c.1** Create `hb_xvmArithByInt()` with operation enum parameter.
  Implement shared cascade: NUMERIC→objOperatorCall.
- [ ] **R1c.2** Rewrite `hb_xvmMultByInt`, `hb_xvmDivideByInt`,
  `hb_xvmModulusByInt` as wrappers.
- [ ] **R1c.3** Verify: `ddtest` — 4861/4861 pass.
- [ ] **R1d** Add Clipper-compat comment to string subtraction in `hb_vmMinus`.
- [ ] **R1.final** Update blueprint artifacts.

### Files touched

| File | Change |
|------|--------|
| `src/vm/hvm.c` | Factor 4+2+3 = 9 functions into 3 parameterized functions |

### Rollback

Each sub-step (R1a, R1b, R1c) is an independent commit. `git revert` any one.

---

## Phase 2: Equal/NotEqual Consolidation (1 day, optional)

- [ ] Factor `hb_vmEqual`/`hb_vmNotEqual` into 1 function with negate flag.
  ~80 lines saved. Medium risk (NIL handling subtlety).

## Phase 3: Performance Annotations (1-2 days, independent)

- [ ] Add `HB_LIKELY`/`HB_UNLIKELY` macros to `include/hbdefs.h`.
- [ ] Annotate operator fast paths, error paths, profiler/debug guards.

---

[<- Index](../INDEX.md) · [Map](../MAP.md) · [BRIEF](BRIEF.md) · **PLAN** · [TESTS](TEST_PLAN.md) · [AUDIT](AUDIT.md)
