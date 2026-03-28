# AUDIT -- ScalarClasses (SUBSYSTEM)

**Last audit**: 2026-03-28
**Overall**: :white_check_mark: Aligned (Phase 2 complete)

---

## Code vs Blueprint

| Claim (BRIEF/DESIGN) | Code Reality | Status |
|-----------------------|-------------|--------|
| 60 methods in C (54 scalar + 6 universal) | 54 `hb_clsAdd()` calls at classes.c:1296-1363 + 6 DrydockObject methods | Done |
| Character: 14 methods | Upper, Lower, Trim, LTrim, RTrim, Left, Right, SubStr, At, Len, Empty, Replicate, Split, Reverse | Done |
| Numeric: 8 methods | Abs, Int, Round, Str, Min, Max, Empty, Between | Done |
| Date: 7 methods | Year, Month, Day, DOW, Empty, AddDays, DiffDays | Done |
| Timestamp: 6 methods | Year, Month, Day, Hour, Minute, Sec | Done |
| Array: 8 methods | Len, Empty, Sort, Tail, Each, Map, Filter, Add | Done |
| Hash: 6 methods | Keys, Values, Len, Empty, HasKey, Del | Done |
| Logical: 2 methods | IsTrue, Toggle | Done |
| Operators: Array+, Hash+, Character* | 3 `hb_clsAdd()` calls at classes.c:1361-1363 | Done |
| `hb_objGetScalarClass()` exported | classes.c:1574-1579; exported in hbapicls.h | Done |
| tscalar.prg stripped to stubs | 93 lines — empty class definitions, no methods | Done |
| No ENABLE TYPE CLASS ALL needed | Removed from tests/scalar.prg; 75 tests pass | Done |

## Method Count Corrections (2026-03-28)

The original BRIEF claimed ~75 methods. Actual count:

| Category | Count | Methods |
|----------|-------|---------|
| Character | 14 | Upper, Lower, Trim, LTrim, RTrim, Left, Right, SubStr, At, Len, Empty, Replicate, Split, Reverse |
| Numeric | 8 | Abs, Int, Round, Str, Min, Max, Empty, Between |
| Date | 7 | Year, Month, Day, DOW, Empty, AddDays, DiffDays |
| Timestamp | 6 | Year, Month, Day, Hour, Minute, Sec |
| Array | 8 | Len, Empty, Sort, Tail, Each, Map, Filter, Add |
| Hash | 6 | Keys, Values, Len, Empty, HasKey, Del |
| Logical | 2 | IsTrue, Toggle |
| Operators | 3 | Array +, Hash +, Character * |
| **Scalar subtotal** | **54** | |
| DrydockObject | 6 | toString, className, classH, isScalar, isNil, valType |
| **Total** | **60** | |

BRIEF updated from ~75 to 60.

## Tests

| Test | Result |
|------|--------|
| ddtest (full suite) | 4861/4861 pass |
| tests/scalar.prg | 75/75 pass (without ENABLE TYPE CLASS ALL) |

## Drift Items Fixed (2026-03-28)

| Item | Fix |
|------|-----|
| BRIEF claimed ~75 methods | Corrected to 60 |
| INDEX.md claimed 55 tests | Corrected to 75 |
| INDEX.md claimed 53 methods | Corrected to 60 |
| ENABLE TYPE CLASS ALL in tests | Removed |
| AsString() test calls | Replaced with toString() |
| COMPAT.md referenced ENABLE TYPE CLASS ALL as needed | Updated to say deprecated |

## Checklist

- [x] BRIEF.md status matches INDEX.md (STABLE)
- [x] Method count in BRIEF matches code (60)
- [x] Test count in INDEX matches tests/scalar.prg (75)
- [x] ENABLE TYPE CLASS ALL removed from Drydock's own code
- [x] hbclass.ch comment updated to mark it deprecated
- [x] COMPAT.md updated
- [ ] IMPLEMENTATION_PLAN.md Phase 2 checkboxes (S2.1-S2.12)
- [ ] Benchmark Phase 3 (future)

---

[<- Index](../INDEX.md) · [BRIEF](BRIEF.md) · [DESIGN](DESIGN.md) · [COMPAT](COMPAT.md) · **AUDIT**
