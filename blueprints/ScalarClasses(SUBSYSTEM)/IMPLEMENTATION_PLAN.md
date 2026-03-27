# IMPLEMENTATION_PLAN -- ScalarClasses (SUBSYSTEM)

## Phase 1: User-Facing Methods + Public API (3-4 days)

- **Milestone**: `"hello":Upper()` works. `(42):Str()` works. `hb_objGetScalarClass()`
  is exported. All existing scalar methods (AsString, ClassName, etc.) continue
  to work. hbtest 4861/4861 passes.

### Steps

- [ ] **S1.1** Add `hb_objGetScalarClass()` to `src/vm/classes.c` — thin wrapper
  over `hb_objGetClassH()`. Add declaration to `include/hbapicls.h`. Add export
  to `src/harbour.def`.
- [x] **S1.2** Add user-facing methods to Character class: Upper, Lower, Trim,
  LTrim, RTrim, Left, Right, SubStr, At, Len, Empty, Replicate, Split, Reverse.
- [x] **S1.3** Add user-facing methods to Numeric class: Abs, Int, Round, Str,
  Min, Max, Empty, Between.
- [x] **S1.4** Add user-facing methods to Date class: AddDays, DiffDays, DOW, Empty.
- [x] **S1.5** Add user-facing methods to Array class: Len, Empty, Sort, Tail,
  Each, Map, Filter.
- [x] **S1.6** Add user-facing methods to Hash class: Keys, Values, Len, Empty,
  HasKey, Del.
- [x] **S1.7** Add user-facing methods to Logical class: IsTrue, Toggle.
- [x] **S1.8** Write test program `tests/scalar.prg` — 55 tests covering all
  new methods. Uses `ENABLE TYPE CLASS ALL` from hbclass.ch.
- [x] **S1.9** Verify: `ddtest` — 4861/4861 pass (no regression).
- [x] **S1.10** Verify: `ddmake tests/scalar.prg -static -gtcgi` — 55/55 pass.
- [x] **S1.11** Update blueprint artifacts.

### Files touched

| File | Change |
|------|--------|
| `src/vm/classes.c` | Add `hb_objGetScalarClass()` (3 lines) |
| `include/hbapicls.h` | Add declaration (1 line) |
| `src/harbour.def` | Add export (1 line) |
| `src/rtl/tscalar.prg` | Add ~150 lines of method definitions |
| `tests/scalar.prg` | New — test program for scalar methods |

### Rollback

Revert tscalar.prg changes. Remove the 3-line C function. No other files affected.

---

## Phase 2: Operator Methods (3-4 days)

- **Milestone**: Scalar classes have operator methods registered. `nOpFlags`
  is set for each scalar class. Cross-type operator combinations that currently
  error can now be handled by scalar class methods (e.g., future type coercion).

### Steps

- [ ] **S2.1** Add operator methods to Character class using OPERATOR syntax:
  `+`, `-`, `=`, `==`, `!=`, `<`, `<=`, `>`, `>=`, `$`.
  Each initially re-executes the built-in operation (`RETURN Self + xOther`).
- [ ] **S2.2** Add operator methods to Numeric class: `+`, `-`, `*`, `/`, `%`,
  `^`, `=`, `==`, `!=`, `<`, `<=`, `>`, `>=`, `++`, `--`.
- [ ] **S2.3** Add operator methods to Date/TimeStamp classes: `+`, `-`,
  comparison operators.
- [ ] **S2.4** Add operator methods to Logical class: `.NOT.`, `.AND.`, `.OR.`,
  `=`, `==`, `!=`.
- [ ] **S2.5** Add operator methods to Array/Hash: `[]` (array index).
- [ ] **S2.6** Verify recursion safety: `"a" + "b"` must NOT enter Character
  operator method (inline cascade handles it). Test with a counter to confirm.
- [ ] **S2.7** Verify: `make && ddtest` — 4861/4861 pass.
- [ ] **S2.8** Update blueprint artifacts.

### Files touched

| File | Change |
|------|--------|
| `src/rtl/tscalar.prg` | Add ~100 lines of OPERATOR definitions |

---

## Phase 3: Rich Methods (3-4 days)

- **Milestone**: Scalar classes provide a rich method API. `cName:Split(",")`,
  `aItems:Map({|x| x * 2})`, `nTotal:Between(0, 100)`.

### Steps

- [ ] **S3.1** Add `Reverse()` to Character class.
- [ ] **S3.2** Add `Between(a,b)` to Numeric class.
- [ ] **S3.3** Add `Reduce(b,x)` to Array class.
- [ ] **S3.4** Expand test coverage in `tests/scalar.prg`.
- [ ] **S3.5** Verify: `make && ddtest` — all pass.

---

## Phase 4: Performance Tuning (2-3 days)

- **Milestone**: Benchmarks confirm < 1% regression on integer arithmetic,
  < 5% on string concatenation, and establish baseline for scalar method dispatch.

### Steps

- [ ] **S4.1** Create benchmark program `tests/scalarbench.prg`.
- [ ] **S4.2** Measure: tight integer loop (`n := n + 1` x 10M).
- [ ] **S4.3** Measure: string concatenation loop (`c := c + c` x 1M).
- [ ] **S4.4** Measure: scalar method dispatch (`"hello":Upper()` x 1M).
- [ ] **S4.5** Document results in TEST_PLAN.md.

---

## Risk Register

| Risk | Phase | Severity | Mitigation |
|------|-------|----------|------------|
| Recursion in operator methods | 2 | High | Inline cascades fire first; verified in DESIGN.md section 6 |
| Performance regression on hot paths | 2,4 | Medium | Operators only fire for non-matched types; benchmarks in Phase 4 |
| Method name conflicts with user code | 1 | Low | All new methods are standard names (Upper, Lower, etc.) |
| tscalar.prg changes break existing scalar behavior | 1 | Low | Additive only — no existing methods modified |

---

[<- Index](../INDEX.md) · [Map](../MAP.md) · [BRIEF](BRIEF.md) · [DESIGN](DESIGN.md) · [API](C_API.md) · [COMPAT](COMPAT.md) · **PLAN** · [TESTS](TEST_PLAN.md) · [MATRIX](TRACEABILITY.md) · [AUDIT](AUDIT.md)
