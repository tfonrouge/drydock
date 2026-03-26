# Audit -- ZigBuild (SUBSYSTEM)
**Last Audit**: 2026-03-26
**Overall**: :white_check_mark: Aligned

## Drift Log

| Artifact | Section | Design Says | Reality | Severity | Action |
|----------|---------|-------------|---------|----------|--------|
| BRIEF.md | Phase Z.0 (original) | "Add `-MMD -MP` to `config/c.mk` and include generated `.d` files. Two lines." | Flags added to `config/linux/gcc.mk` and `config/linux/clang.mk` (not `c.mk`). Includes added to both `config/c.mk` AND `config/prg.mk`. 4 files, 18 lines — not 2. | Medium | **Fixed** — BRIEF.md Z.0 section updated to reflect actual implementation on 2026-03-26 |
| BRIEF.md | Phase Z.1 verification | "produces a working `harbour` binary that passes `hbtest`" | `hbtest` requires the full runtime (hbvm, hbrtl, etc.), not just the compiler. Z.1 only builds the compiler. Verification criterion is wrong. | Medium | Update Z.1 verification to: `harbour` compiles `tests/hello.prg` to C output |
| BRIEF.md | Scope table | Shows Z.0 effort as "1 day" | Actual: ~2 hours including research, implementation, testing | Low | Cosmetic — no action needed |

## Process Gaps

| Gap | Impact | Action |
|-----|--------|--------|
| No TEST_PLAN existed before Z.0 implementation | Verification was ad hoc — done correctly but not documented | Created TEST_PLAN.md retroactively |
| No DESIGN existed before Z.0 implementation | Acceptable for Z.0 (trivial change). Not acceptable for Z.1+. | Create DESIGN.md before starting Z.1 |
| AUDIT.md not created until after Z.0 shipped | Drift in BRIEF.md was caught retroactively, not proactively | Creating now; will be checked at each phase boundary going forward |
| Skill workflow not invoked at step transitions | Artifacts were produced ad hoc instead of following the step sequence | Follow the workflow: DESIGN before code, TEST_PLAN before code, AUDIT after each phase |

## Checklist

- [x] BRIEF.md Phase Z.0 section matches actual implementation
- [x] BRIEF.md Phase Z.1 verification criterion corrected (was "passes hbtest", now "compiles hello.prg to C")
- [x] DESIGN.md exists before Z.1 starts (created 2026-03-26)
- [x] TEST_PLAN.md covers Z.0 retroactively and Z.1 proactively (created 2026-03-26)
- [x] IMPLEMENTATION_PLAN.md exists before Z.1 starts (created 2026-03-26)

## Notes

Phase Z.0 was a 4-file, 18-line change that worked correctly on first attempt.
The drift was in the BRIEF's description of where the changes would go, not in
the implementation itself. The ad hoc testing (full build, hbtest, incremental
rebuild, no-op rebuild) was thorough and covered the right scenarios — it just
wasn't documented as a plan before execution.

Going forward, the workflow must be followed step-by-step for Z.1+. The build
system migration is too complex for improvised implementation.

---
[<- Index](../INDEX.md) · [Map](../MAP.md) · [BRIEF](BRIEF.md) · [DESIGN](DESIGN.md) · [PLAN](IMPLEMENTATION_PLAN.md) · [TESTS](TEST_PLAN.md) · **AUDIT**
