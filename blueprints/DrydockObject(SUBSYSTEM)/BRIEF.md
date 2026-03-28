# BRIEF -- DrydockObject (SUBSYSTEM)

## Identity

| Field | Value |
|-------|-------|
| **Name** | DrydockObject |
| **Mode** | SUBSYSTEM |
| **Tier** | 1 — Foundation (new root) |
| **Component** | VM — `src/vm/classes.c`, `src/vm/hvm.c` |
| **Status** | STABLE |

---

## 1. Motivation

Drydock's mission is "every value is a first-class object." Today, Harbour
has two disconnected type systems:

1. **HB_ITEM tagged union** — handles all values via type flags and inline cascades
2. **CLASS registry** — handles only arrays with `uiClass != 0`

Scalar classes (Character, Numeric, Date, etc.) exist in `tscalar.prg` but
are optional, require explicit `ENABLE TYPE CLASS ALL`, and depend on static
archive linking to pull in factory functions. This means:

- `"hello":toString()` — **doesn't work** without explicit setup
- `(42):className()` — **doesn't work** without explicit setup
- `NIL:isNil()` — **doesn't work** at all
- User-defined classes have no universal base methods

In a fully OO language (Ruby, Smalltalk, Python), there is no distinction
between "scalar values" and "objects." Every value IS an object. Every value
has methods. There's a root class that everything inherits from.

DrydockObject makes this real at the VM level. Not by changing HB_ITEM's
memory layout (that would break the ABI), but by creating a class hierarchy
in C during VM initialization that covers every possible value — always
available, no linking constraints, no user setup required.

---

## 2. What This Creates

### DrydockObject — The Root Class

A class created in pure C during `hb_clsInit()`. Every class in the system
inherits from it — scalar classes, HBObject, and user-defined classes.

**Universal methods (always available on ANY value):**

| Method | Returns | Purpose |
|--------|---------|---------|
| `toString()` | String | Human-readable representation of any value |
| `className()` | String | Type/class name ("CHARACTER", "NUMERIC", etc.) |
| `isScalar()` | Logical | `.T.` for scalar types, `.F.` for user objects |
| `isNil()` | Logical | `.T.` only for NIL values |
| `valType()` | String | Traditional ValType() as a method ("C", "N", etc.) |
| `compareTo(other)` | Numeric/NIL | -1, 0, or 1 for ordered types; NIL for incomparable |
| `isComparable()` | Logical | `.T.` for types that support ordering (string, numeric, date, logical) |

### Scalar Type Classes — Always Registered

11 scalar classes created in C, inheriting from DrydockObject, associated
with their HB_TYPE flags. No factory functions needed. No linking dependency.

```
DrydockObject
├── HBArray          (HB_IT_ARRAY)
├── HBBlock          (HB_IT_BLOCK)
├── HBCharacter      (HB_IT_STRING)
├── HBDate           (HB_IT_DATE)
├── HBTimeStamp      (HB_IT_TIMESTAMP)
├── HBHash           (HB_IT_HASH)
├── HBLogical        (HB_IT_LOGICAL)
├── HBNil            (HB_IT_NIL)
├── HBNumeric        (HB_IT_NUMERIC)
├── HBSymbol         (HB_IT_SYMBOL)
└── HBPointer        (HB_IT_POINTER)
```

### toString() — Built-In Default Message

Like `CLASSNAME` and `CLASSH`, `toString` is handled as a default message in
`hb_objGetMethod()`. This means it works on ANY value — even values whose
scalar class doesn't explicitly define a toString method. It's a VM-level
guarantee, not a class-level method.

---

## 3. What This Unlocks

| Capability | Before | After |
|------------|--------|-------|
| `"hello":toString()` | Error (unless ENABLE TYPE CLASS ALL) | Always works |
| `(42):className()` | Returns "NUMERIC" via built-in only | Returns "NUMERIC" via class method |
| `NIL:isNil()` | Error | Always works |
| `MyClass():toString()` | Error (unless class defines it) | Default from DrydockObject |
| Scalar classes | Optional library feature | Native VM feature |
| User class base | HBObject (PRG, optional) | DrydockObject (C, always available) |

**Downstream workstreams enabled:**
- ScalarClasses Phase 2 (operators) — scalar classes guaranteed to exist
- ExtensionMethods — can extend any type's class
- Reflection — every value has introspectable class metadata
- Debugger — can call toString() on any value for display
- Error messages — can use toString() in error formatting

---

## 4. Affected Files

| File | Lines | Change |
|------|-------|--------|
| `src/vm/classes.c` | ~5,665 | Create DrydockObject + 11 scalar classes in hb_clsInit; add toString built-in message; modify hb_clsDoInit to extend-not-create |
| `src/vm/hvm.c` | ~11,839 | No change (dispatch already works via hb_objGetMethod) |
| `include/hbapicls.h` | ~142 | Export DrydockObject class handle if needed |
| `src/harbour.def` | ~3,800 | Export new symbols if needed |
| `tests/scalar.prg` | ~100 | Remove ENABLE TYPE CLASS ALL; add toString/isNil tests |

## 5. Affected Structs

**None.** No changes to HB_ITEM, HB_BASEARRAY, CLASS, or METHOD structures.
The change is purely in initialization — creating classes using existing APIs.

## 6. Compatibility Stance

**Target: 100% source and ABI compatibility.**

- `ValType()` return values unchanged
- `HB_IS_OBJECT()` returns `.F.` for scalars (unchanged)
- `Len()` returns bytes for strings (unchanged)
- Existing user classes work unchanged
- HBObject continues to work (inherits from DrydockObject)
- All C extensions compile without changes
- The only observable change: methods that previously errored now succeed
  (strictly additive)

## 7. Performance Stance

**Must not regress on any existing path.**

- Scalar class creation happens once at VM startup (~1ms)
- Method dispatch for scalars uses the same `hb_clsScalarMethod()` path
- toString() as a built-in message adds one pointer comparison in the
  default message check — negligible
- No change to the operator fast paths in hvm.c

## 8. Dependencies

| Dependency | Status | Notes |
|------------|--------|-------|
| *(none)* | — | DrydockObject is a root workstream. It depends on nothing. |

**Blocks:**
- ScalarClasses Phase 2+ (operators, rich methods)
- ExtensionMethods
- Reflection
- Any feature that assumes "every value is an object"

## 9. Risks

| Risk | Severity | Mitigation |
|------|----------|------------|
| hb_clsNew called before class pool is ready | High | Call AFTER s_pClasses allocation in hb_clsInit |
| Inheritance from DrydockObject breaks HBObject | Medium | HBObject inherits from DrydockObject (preserves chain) |
| Class handle ordering assumptions | Low | No code should hardcode class handle values |
| hb_clsDoInit overwrites C-created class handles | High | Modify to extend, not replace |
| toString infinite recursion (toString calls toString) | Medium | C implementation uses type switch, not method dispatch |

## 10. Estimated Scope

| Phase | Effort | Can Ship Independently |
|-------|--------|----------------------|
| D.1: toString built-in message | 0.5 day | Yes |
| D.2: DrydockObject root class in C | 1 day | Yes (after D.1) |
| D.3: 11 scalar classes in C | 1 day | Yes (after D.2) |
| D.4: Modify hb_clsDoInit (extend-not-create) | 1 day | Yes (after D.3) |
| D.5: Tests + verification | 0.5 day | Yes (after D.4) |
| **Total** | **4 days** | |

---

[<- Index](../INDEX.md) · [Map](../MAP.md) · **BRIEF** · [DESIGN](DESIGN.md) · [ARCH](ARCHITECTURE.md) · [API](C_API.md) · [COMPAT](COMPAT.md) · [PLAN](IMPLEMENTATION_PLAN.md) · [TESTS](TEST_PLAN.md) · [AUDIT](AUDIT.md)
