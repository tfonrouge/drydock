# Audit -- RefactorHvm (SUBSYSTEM)
**Last Audit**: 2026-03-27
**Overall**: :white_check_mark: Aligned

## Drift Log

| Artifact | Section | Design Says | Reality | Severity | Action |
|----------|---------|-------------|---------|----------|--------|
| BRIEF.md | Phase 0 scope | "~712 lines" (R0a ~680 + R0b ~12 + R0c ~12 + R0d ~8) | Actual: 733 lines removed (723 function lines + 10 `#if 0` lines) | Low | Expected variance — functions were slightly larger than estimated |

## Phase 0 — REVERTED (`6f6811b`)

The 12 `hb_xvm*ThenInt*` / `*IntIs` functions were deleted under the assumption
they had zero callers. This was WRONG. The C code generator (`gencc.c`) emits
calls to these functions in the `.prg → .c` compilation path. The generated C
files (`errsys.c`, `alert.c`, `achoice.c`, etc.) reference `hb_xvmEqualIntIs`,
`hb_xvmGreaterThenIntIs`, etc.

The original analysis searched only handwritten `.c` files and `gencc.c` source
code. It missed that gencc.c generates code at runtime that calls these functions
— the calls only appear in compiled `.c` output, not in gencc.c itself.

**Root cause**: The functions ARE used, but only by generated code. `grep` of
the source tree found zero callers because the callers are generated at build
time by the compiler.

**Lesson**: "Zero callers in the source tree" does not mean "zero callers."
Generated code must be checked too.

## Phase 0 Original Summary (REVERTED)

- **Commit**: `0ec787c` (2026-03-27) — REVERTED by `6f6811b`
- **Lines removed**: 733 (hvm.c: 12,572 → 11,839)
- **Functions deleted**: 12 (`hb_xvmEqualInt`, `hb_xvmEqualIntIs`, `hb_xvmNotEqualInt`, `hb_xvmNotEqualIntIs`, `hb_xvmLessThenInt`, `hb_xvmLessThenIntIs`, `hb_xvmLessEqualThenInt`, `hb_xvmLessEqualThenIntIs`, `hb_xvmGreaterThenInt`, `hb_xvmGreaterThenIntIs`, `hb_xvmGreaterEqualThenInt`, `hb_xvmGreaterEqualThenIntIs`)
- **Declarations removed**: 12 from `include/hbxvm.h`
- **Exports removed**: 12 from `src/harbour.def`
- **Dead code block removed**: `#if 0` hash equality in `hb_vmEqual`
- **Test result**: ddtest 4861/4861 passed — zero behavior change

## Checklist

- [x] BRIEF.md Phase 0 scope matches actual removal
- [x] TEST_PLAN.md results recorded for all Phase 0 tests
- [ ] IMPLEMENTATION_PLAN.md created for Phase 1

---

[<- Index](../INDEX.md) · [Map](../MAP.md) · [BRIEF](BRIEF.md) · [TESTS](TEST_PLAN.md) · **AUDIT**
