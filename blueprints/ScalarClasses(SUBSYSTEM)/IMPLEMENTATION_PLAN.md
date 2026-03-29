# IMPLEMENTATION_PLAN -- ScalarClasses (SUBSYSTEM)

## Phase 1a: User-Facing Methods in PRG -- DONE (2026-03-27)

- **Milestone**: `"hello":Upper()` works (with ENABLE TYPE CLASS ALL).
  55 tests pass. ddtest 4861/4861 passes.

All steps complete. Methods added to tscalar.prg: Character (14 methods),
Numeric (8), Date (4), Array (7), Hash (6), Logical (2). Test program at
`tests/scalar.prg`.

---

## Phase 1b: DrydockObject Root Class -- DONE (2026-03-27)

- **Milestone**: `"hello":toString()` works WITHOUT any includes, REQUEST, or
  ENABLE TYPE CLASS ALL. All scalar types have C-level classes at VM startup.

All steps complete. See [DrydockObject blueprint](../DrydockObject(SUBSYSTEM)/BRIEF.md).
Universal methods: toString, className, classH, isScalar, isNil, valType.
11 scalar classes created in C inheriting from DrydockObject.
ddtest 4861/4861 pass. 20 new tests in tests/scalar.prg.

---

## Phase 2: Move All Scalar Methods to C -- DONE (2026-03-28, `e6e5d42` + `3fb67e5`)

- **Milestone**: ALL scalar class methods defined in C. `"hello":Upper()`,
  `(42):Abs()`, `{1,2,3}:Map()` work WITHOUT any includes. Cross-type
  operators work. tscalar.prg stripped to stubs. 11 tscalar*.c files are
  no-ops. hb_clsDoInit() guarded to preserve C class handles.

### Steps (all complete)

- [x] **S2.1-S2.7** 53 C method wrappers: CHARACTER (14), NUMERIC (8),
  DATE (7), TIMESTAMP (6), ARRAY (8), HASH (6), LOGICAL (2).
- [x] **S2.8** All methods registered via `hb_clsAdd()` in
  `hb_clsInitDrydockObject()`.
- [x] **S2.9-S2.11** Operators: ARRAY `+` (concat/append), HASH `+` (merge),
  CHARACTER `*` (repeat).
- [x] **S2.12** `tests/scalar.prg` — ENABLE TYPE CLASS ALL removed. 75 tests.
- [x] **S2.13** Cross-type operators verified: `{1,2}+{3,4}`, `"abc"*3`.
- [x] **S2.14** ddtest 4861/4861 pass. zig build clean.
- [x] **S2.extra** tscalar.prg stripped to empty stubs (622→90 lines).
  11 tscalar*.c glue files converted to no-ops. hb_clsDoInit() guarded
  to not overwrite C-created class handles.

### Files touched

| File | Change |
|------|--------|
| `src/vm/classes.c` | ~53 C method wrappers + operator methods + registration in hb_clsInitDrydockObject (~500 lines) |
| `tests/scalar.prg` | Remove ENABLE TYPE CLASS ALL; add operator tests |

### Rollback

Revert classes.c changes. Methods fall back to tscalar.prg + ENABLE TYPE CLASS ALL.

---

## Phase 3: Performance + Cleanup (2-3 days)

- **Milestone**: Benchmarks confirm zero regression. ENABLE TYPE CLASS ALL
  deprecated. Documentation updated.

### Steps

- [x] **S3.1** Benchmark program `tests/scalarbench.prg` created.
  Results: int arith 20ms/1M, Upper 84ms/1M, Len 40ms/1M — zero regression.
- [x] **S3.2-S3.4** Benchmarks verified. No regression on hot paths.
- [x] **S3.5** ENABLE TYPE CLASS ALL deprecation note added to `hbclass.ch`.
- [x] **S3.6** Blueprint artifacts updated.
- [x] **S3.7** Status → STABLE.

---

## Risk Register

| Risk | Phase | Severity | Mitigation |
|------|-------|----------|------------|
| C wrappers call RTL functions that need HB_STACK_TLS_PRELOAD | 2 | Medium | Follow existing patterns in msgToString; test each wrapper |
| Operator recursion (e.g., ARRAY.__OpPlus calls hb_vmPlus internally) | 2 | High | Operator methods use C-level array manipulation (hb_arrayAdd), not Harbour operators |
| Performance regression from extra class method registrations at init | 2 | Low | ~75 hb_clsAdd calls at startup; one-time cost < 1ms |
| tscalar.prg conflicts with C-defined methods | 2 | Medium | hb_clsDoInit overwrites handles; PRG methods shadow C ones. Acceptable — same methods, same behavior |
| Operator nOpFlags lost when hb_clsDoInit overwrites class handle | 2 | High | Also define operators in tscalar.prg OR guard with extend-not-create |

---

[<- Index](../INDEX.md) · [Map](../MAP.md) · [BRIEF](BRIEF.md) · [DESIGN](DESIGN.md) · [API](C_API.md) · [COMPAT](COMPAT.md) · **PLAN** · [TESTS](TEST_PLAN.md) · [MATRIX](TRACEABILITY.md) · [AUDIT](AUDIT.md)
