# AUDIT -- DrydockObject (SUBSYSTEM)

**Last audit**: 2026-03-28
**Overall**: :white_check_mark: Aligned (Phase 1 complete, Phase 2 planned)

---

## Code vs Blueprint

| Claim (BRIEF/DESIGN) | Code Reality | Status |
|-----------------------|-------------|--------|
| DrydockObject root class created in C | `hb_clsCreate(0, "DrydockObject")` at classes.c:1264 | Done |
| 11 scalar classes inherit from DrydockObject | `hb_clsNew()` calls at classes.c:1279-1289 | Done |
| `toString()` built-in default message | Static symbol at classes.c:386; dispatch at classes.c:2424; implementation at classes.c:4679-4730 | Done |
| `className()` method | Registered at classes.c:1266 via existing CLASSNAME handler | Done |
| `isScalar()` method | Static symbol at classes.c:387; implementation at classes.c:4737-4741 | Done |
| `isNil()` method | Static symbol at classes.c:388; implementation at classes.c:4748-4752 | Done |
| `valType()` method | Static symbol at classes.c:389; implementation at classes.c:4759-4763 | Done |
| `compareTo()` method | **Not implemented** — moved to Phase 2 in oo-spec.md | Planned |
| `isComparable()` method | **Not implemented** — moved to Phase 2 in oo-spec.md | Planned |
| `hb_clsDoInit()` extend-not-create | Guard at classes.c:1400-1405 skips handle overwrite | Done |
| `hb_clsInitDrydockObject()` function | Declared at classes.c:302; implemented at classes.c:1259-1364 | Done |
| `s_uiDrydockObjectClass` variable | Declared at classes.c:426 | Done |

## Tests

| Test | Result |
|------|--------|
| ddtest (full suite) | 4861/4861 pass |
| tests/scalar.prg | 75/75 pass (without ENABLE TYPE CLASS ALL) |
| `"hello":toString()` without setup | Works |
| `NIL:isNil()` without setup | Works |
| `(42):className()` returns "NUMERIC" | Works |

## Drift Items Fixed (2026-03-28)

| Item | Fix |
|------|-----|
| BRIEF.md status was PLANNING | User updated to STABLE |
| compareTo/isComparable claimed as Phase 1 in oo-spec.md | Moved to Phase 2 (Extended Protocols) |
| ENABLE TYPE CLASS ALL in tests/scalar.prg | Removed; tests pass without it |
| AsString() calls in tests | Replaced with toString() |

## Checklist

- [x] BRIEF.md status matches INDEX.md (STABLE)
- [x] DESIGN.md code references match actual line numbers (verified)
- [x] All claimed methods exist in code (6/6 Phase 1 methods)
- [x] Tests pass without ENABLE TYPE CLASS ALL
- [ ] IMPLEMENTATION_PLAN.md task checkboxes up to date
- [ ] compareTo/isComparable implemented (Phase 2, future)

---

[<- Index](../INDEX.md) · [BRIEF](BRIEF.md) · [DESIGN](DESIGN.md) · **AUDIT**
