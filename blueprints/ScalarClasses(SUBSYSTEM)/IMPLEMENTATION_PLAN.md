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

## Phase 2: Move All Scalar Methods to C (5-7 days)

- **Milestone**: ALL scalar class methods are defined in C during VM init.
  `"hello":Upper()`, `(42):Abs()`, `{1,2,3}:Map()` work WITHOUT any includes,
  REQUEST, or ENABLE TYPE CLASS ALL. Cross-type operators work. tscalar.prg
  becomes optional.

### Steps

- [ ] **S2.1** Implement CHARACTER methods in C (thin wrappers around RTL):
  Upper, Lower, Trim, LTrim, RTrim, Left, Right, SubStr, At, Len, Empty,
  Replicate, Split, Reverse. (~14 C functions calling existing RTL functions)
- [ ] **S2.2** Implement NUMERIC methods in C: Abs, Int, Round, Str, Min, Max,
  Empty, Between. (~8 C functions)
- [ ] **S2.3** Implement DATE methods in C: Year, Month, Day, DOW, Empty,
  AddDays, DiffDays. (~7 C functions)
- [ ] **S2.4** Implement TIMESTAMP methods in C: Year, Month, Day, Hour,
  Minute, Sec, Date, Time. (~8 C functions)
- [ ] **S2.5** Implement ARRAY methods in C: Len, Empty, Sort, Tail, Each,
  Map, Filter, Add. (~8 C functions)
- [ ] **S2.6** Implement HASH methods in C: Keys, Values, Len, Empty,
  HasKey, Del. (~6 C functions)
- [ ] **S2.7** Implement LOGICAL methods in C: IsTrue, Toggle. (~2 C functions)
- [ ] **S2.8** Register all methods via `hb_clsAdd()` in
  `hb_clsInitDrydockObject()` for each scalar class.
- [ ] **S2.9** Add operator methods to ARRAY class: `__OpPlus` (array concat
  and element append).
- [ ] **S2.10** Add operator methods to HASH class: `__OpPlus` (hash merge).
- [ ] **S2.11** Add operator method to CHARACTER class: `__OpMult` (string repeat).
- [ ] **S2.12** Test: `tests/scalar.prg` — remove `ENABLE TYPE CLASS ALL`.
  All 75+ tests pass without it.
- [ ] **S2.13** Test: cross-type operators work:
  `{1,2} + {3,4}` → `{1,2,3,4}`, `"abc" * 3` → `"abcabcabc"`.
- [ ] **S2.14** Verify: `ddtest` 4861/4861 pass. `zig build` clean.
- [ ] **S2.15** Update blueprint artifacts.

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

- [ ] **S3.1** Create benchmark program `tests/scalarbench.prg`.
- [ ] **S3.2** Measure: tight integer loop (`n := n + 1` x 10M): < 1% regression.
- [ ] **S3.3** Measure: string concat loop: < 5% regression.
- [ ] **S3.4** Measure: scalar method dispatch (`"hello":Upper()` x 1M): baseline.
- [ ] **S3.5** Make `ENABLE TYPE CLASS ALL` a no-op (all methods already in C).
  Add compiler note: "This directive is no longer needed in Drydock."
- [ ] **S3.6** Update CLAUDE.md, README.md, doc/drydock/oo-spec.md.
- [ ] **S3.7** Update all blueprint artifacts to STABLE.

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
