# IMPLEMENTATION_PLAN -- RefactorHvm (SUBSYSTEM)

## Phase 0: Dead Code Removal -- REVERTED (2026-03-27)

Attempted in `0ec787c`, reverted in `6f6811b`. The 12 `hb_xvm*ThenInt*`
functions appeared dead in source grep but ARE emitted by `gencc.c` in
generated C code. They are NOT dead code — they are live in the `-gc2`
compilation path. Phase 0 is cancelled.

---

## Phase 1: Operator Deduplication (2-3 days)

- **Milestone**: 4 ordering comparisons factored into 1. Inc/Dec factored into 1.
  3 xvm*ByInt factored into 1. ~350 lines saved. ddtest identical results.

### Steps

- [x] **R1a.1** Create `hb_vmCompare()` with `iMode` parameter (0=Less, 1=LessEqual,
  2=Greater, 3=GreaterEqual). Shared cascade with static lookup tables for
  OO operator constants, error codes, and operator strings.
- [x] **R1a.2** Rewrite `hb_vmLess`, `hb_vmLessEqual`, `hb_vmGreater`,
  `hb_vmGreaterEqual` as one-line wrappers calling `hb_vmCompare()`.
- [x] **R1a.3** Verify: `ddtest` — 4861/4861 pass.
- [x] **R1b.1** Create `hb_vmIncDec()` with `iDir` parameter (+1/-1).
  Shared cascade with overflow/underflow bounds checked via direction.
- [x] **R1b.2** Rewrite `hb_vmInc`, `hb_vmDec` as one-line wrappers.
- [x] **R1b.3** Verify: `ddtest` — 4861/4861 pass.
- [x] **R1c** SKIPPED — Mult/Divide/Modulus have structurally different
  semantics (zero-division, integer modulo). Factoring would add complexity
  without improving clarity.
- [x] **R1d** Add Clipper-compat comment to string subtraction in `hb_vmMinus`.
- [x] **R1.final** Update blueprint artifacts.

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

## Phase 3: Performance Annotations -- DONE (2026-03-29, `94218ef`)

- [x] Add `HB_LIKELY`/`HB_UNLIKELY` macros to `include/hbdefs.h`.
- [x] Annotate operator fast paths (hb_vmPlus, hb_vmMinus, hb_vmIncDec,
  hb_vmCompare) with HB_LIKELY. Operator fallback with HB_UNLIKELY.

---

[<- Index](../INDEX.md) · [Map](../MAP.md) · [BRIEF](BRIEF.md) · **PLAN** · [TESTS](TEST_PLAN.md) · [AUDIT](AUDIT.md)
