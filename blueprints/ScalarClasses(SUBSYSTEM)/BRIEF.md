# BRIEF -- ScalarClasses (SUBSYSTEM)

## Identity

| Field | Value |
|-------|-------|
| **Name** | ScalarClasses |
| **Mode** | SUBSYSTEM |
| **Component** | VM — `src/vm/classes.c` |
| **Status** | STABLE |

## Motivation

DrydockObject (STABLE) proved the architecture: universal methods like
`toString()`, `isScalar()`, `valType()` are defined in C during VM init,
work on ANY value, and require no includes or linking. 11 scalar classes
exist at startup, inheriting from DrydockObject.

But the **rich methods** (`Upper`, `Abs`, `Len`, `Map`, etc.) still live
in `src/rtl/tscalar.prg` behind `ENABLE TYPE CLASS ALL` — a macro that
expands to `REQUEST HBCharacter, HBNumeric, ...` which forces the linker
to pull in factory functions. This is a 6-layer indirection chain from
Harbour's "optional OO" era:

```
hbclass.ch → ENABLE TYPE CLASS ALL → REQUEST → linker → factory function → hb_clsDoInit()
```

**This is wrong for Drydock.** If `"hello":toString()` works everywhere,
then `"hello":Upper()` should too. The distinction between "universal" and
"rich" methods is arbitrary from the user's perspective.

**The goal**: move ALL scalar class methods into C, defined during VM init
via `hb_clsAdd()`. Each C method is a thin wrapper around an existing RTL
function. No tscalar.prg required. No `ENABLE TYPE CLASS ALL` required.

## What This Creates

### Always-Available Scalar Methods (no includes, no REQUEST)

| Class | Methods | C Wrapper Target |
|-------|---------|-----------------|
| CHARACTER | Upper, Lower, Trim, LTrim, RTrim, Left, Right, SubStr, At, Len, Empty, Replicate, Split, Reverse | RTL: Upper(), Lower(), AllTrim(), Left(), etc. |
| NUMERIC | Abs, Int, Round, Str, Min, Max, Empty, Between | RTL: Abs(), Int(), Round(), Str(), Min(), Max() |
| DATE | Year, Month, Day, DOW, Empty, AddDays, DiffDays | RTL: Year(), Month(), Day(), DOW() |
| TIMESTAMP | Year, Month, Day, Hour, Minute, Sec, Date, Time | RTL: hb_Hour(), hb_Minute(), hb_Sec() |
| ARRAY | Len, Empty, Sort, Tail, Each, Map, Filter, Add | RTL: Len(), ASort(), ATail(), AAdd() |
| HASH | Keys, Values, Len, Empty, HasKey, Del | RTL: hb_HKeys(), hb_HValues(), hb_HHasKey() |
| LOGICAL | IsTrue, Toggle | Trivial C |
| NIL, BLOCK, SYMBOL, POINTER | (minimal — toString covers it) | Already in DrydockObject |

**60 methods** (54 scalar + 6 DrydockObject universal), ~83% are thin C
wrappers around existing RTL functions.

### Scalar Operators (cross-type, currently-erroring cases)

| Expression | Operator | Result |
|-----------|----------|--------|
| `{1,2} + {3,4}` | ARRAY.__OpPlus | `{1,2,3,4}` (concat) |
| `{1,2} + 3` | ARRAY.__OpPlus | `{1,2,3}` (append) |
| `{"a"=>1} + {"b"=>2}` | HASH.__OpPlus | Merge |
| `"abc" * 3` | CHARACTER.__OpMult | `"abcabcabc"` (repeat) |

Operators ONLY fire for cross-type/unsupported combinations (the fallback
in `hb_vmPlus()` etc.). Same-type fast paths (int+int, string+string)
stay inline in hvm.c — zero performance impact.

### tscalar.prg Becomes Optional

- Existing code with `ENABLE TYPE CLASS ALL` still works (backward compat)
- But it's no longer NEEDED — all methods are available without it
- Eventually deprecated with a compiler note

## What This Unlocks

| Capability | Before | After |
|------------|--------|-------|
| `"hello":Upper()` | Needs ENABLE TYPE CLASS ALL | Always works |
| `(42):Abs()` | Needs ENABLE TYPE CLASS ALL | Always works |
| `{1,2,3}:Map({|x| x*2})` | Needs ENABLE TYPE CLASS ALL | Always works |
| `{1,2} + {3,4}` | Runtime error | Array concat |
| `"abc" * 3` | Runtime error | String repeat |
| User extends STRING | Edit tscalar.prg or use EXTEND CLASS | ExtensionMethods syntax (see blueprint) |

**Downstream workstreams enabled:**
- ExtensionMethods — users extend any class with `FUNCTION STRING.method()` syntax
- Operator customization — users add operators via extension methods
- Plugin extensibility — contribs add methods to scalar types without VM changes

## Affected Files

| File | Change |
|------|--------|
| `src/vm/classes.c` | Add ~75 C method wrappers in `hb_clsInitDrydockObject()`; add operator methods to scalar classes |
| `src/rtl/tscalar.prg` | Becomes optional backward-compat shim |
| `tests/scalar.prg` | Remove ENABLE TYPE CLASS ALL; expand tests |

## Affected Structs

**None.** No changes to HB_ITEM, CLASS, METHOD, or HB_BASEARRAY.
Scalar classes use existing APIs (`hb_clsAdd()`, `hb_clsNew()`).

## Compatibility Stance

**Target: 100% source compatibility, 100% ABI compatibility.**

1. `ValType()` return values unchanged.
2. `Len()` on strings returns bytes.
3. `HB_IS_OBJECT()` returns `.F.` for scalars.
4. Existing operator behavior identical for all built-in type combinations.
5. Methods that previously errored now succeed (strictly additive).
6. `ENABLE TYPE CLASS ALL` still works (no-op if C methods already registered).
7. C extensions compile without changes.

## Performance Stance

**Zero regression on existing hot paths.**

- Same-type operators (int+int, string+string) stay inline in hvm.c
- Operator methods ONLY fire for currently-erroring cross-type operations
- C method wrappers call existing RTL functions — same code path, no overhead
- Benchmark: `ddtest` 4861/4861, tight arithmetic loop < 1% regression

## Dependencies

| Dependency | Status | Notes |
|------------|--------|-------|
| [DrydockObject](../DrydockObject(SUBSYSTEM)/BRIEF.md) | STABLE | Provides C-level scalar classes. **Done.** |

## Estimated Scope

- **Phase 1**: DONE — user-facing methods in tscalar.prg (75 tests)
- **Phase 1b**: DONE — DrydockObject root class + always-available scalar classes
- **Phase 2** (5-7 days): Move all methods to C + add operators
- **Phase 3** (2-3 days): Performance verification + cleanup + deprecation notes

---

[<- Index](../INDEX.md) · [Map](../MAP.md) · **BRIEF** · [DESIGN](DESIGN.md) · [ARCH](ARCHITECTURE.md) · [API](C_API.md) · [COMPAT](COMPAT.md) · [PLAN](IMPLEMENTATION_PLAN.md) · [TESTS](TEST_PLAN.md) · [MATRIX](TRACEABILITY.md) · [AUDIT](AUDIT.md)
