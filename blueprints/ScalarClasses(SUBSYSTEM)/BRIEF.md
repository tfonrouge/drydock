# BRIEF -- ScalarClasses (SUBSYSTEM)

## Identity

| Field | Value |
|-------|-------|
| **Name** | ScalarClasses |
| **Mode** | SUBSYSTEM |
| **Component** | VM (virtual machine) + RTL (runtime library) |
| **Status** | PLANNING |

## Motivation

Harbour has **two type systems that do not talk to each other**:

1. **Inline type cascades** in `src/vm/hvm.c` (12,572 lines). Every operator
   (`hb_vmPlus`, `hb_vmMinus`, `hb_vmEqual`, ...) contains a hand-rolled
   if/else cascade checking `HB_IS_NUMINT`, `HB_IS_NUMERIC`, `HB_IS_STRING`,
   `HB_IS_DATETIME`, etc. -- with `hb_objOperatorCall()` as a last-resort
   fallback (64 call sites).

2. **A sophisticated OO system** in `src/vm/classes.c` (5,665 lines) with
   hash-based method dispatch, multiple inheritance, 30 overloadable operators,
   scoping, and delegation -- that scalar values never benefit from.

The infrastructure to bridge them **already exists but is not wired in**:

- 12 scalar wrapper classes live in `src/rtl/tscalar.prg` (HBScalar, Array,
  Block, Character, Date, TimeStamp, Hash, Logical, NIL, Numeric, Symbol,
  Pointer).
- Static class handles (`s_uiArrayClass`, `s_uiCharacterClass`, ...) are
  declared in `classes.c:327-337` and initialized by `hb_clsDoInit()` at
  VM startup.
- `hb_objGetMethod()` already resolves scalar class methods for message sends
  (`classes.c:1872-2145`), so `"hello":ClassName()` works today.

**What does NOT work**: operators on scalars never consult scalar classes.
The 64 `hb_objOperatorCall` sites in `hvm.c` only fire for items where
`HB_IS_OBJECT()` is true (arrays with `uiClass != 0`). Plain strings,
numbers, dates, etc. are handled entirely by the inline cascades.

**The goal**: unify operator dispatch so that scalar classes participate in
the operator resolution chain -- enabling user-extensible operators on any
type -- while keeping arithmetic fast paths inline for zero-cost on the
hot path.

## What This Unlocks

1. **User-extensible scalar methods**: `cName:Upper()`, `cName:Split(",")`,
   `nTotal:Format("$#,###.##")`, `dDate:AddMonths(3)`.
2. **Unified FOR EACH**: dispatch `__ENUMSTART`/`__ENUMSKIP`/`__ENUMSTOP` to
   scalar class methods, allowing any type to be enumerable.
3. **Plugin extensibility**: contrib modules can add methods to scalar types
   (e.g., `cJSON:Parse()`) without touching core VM code.
4. **Reduced hvm.c complexity**: ~2,000 lines of type-check cascades collapse
   into scalar class operator methods + fast-path guards.

## Affected Files

| File | Lines | Role | Change |
|------|-------|------|--------|
| `src/vm/hvm.c` | 12,572 | VM execution loop | Simplify operator cascades; route non-fast-path cases through `hb_objOperatorCall` |
| `src/vm/classes.c` | 5,665 | OO system | Add `hb_objGetScalarClass()`; modify `hb_objHasOperator()` / `hb_objOperatorCall()` to handle scalar types |
| `src/rtl/tscalar.prg` | 404 | Scalar class definitions | Add operator methods (`__OPPLUS`, `__OPMINUS`, ...) and user-facing methods (`Upper`, `Split`, `Format`, ...) |
| `include/hbapicls.h` | 142 | Class/object public API | Export `hb_objGetScalarClass()` |
| `include/hbapi.h` | 1,257 | Core type definitions | No struct changes -- scalar classes are resolved by type, not stored in items |
| `src/vm/itemapi.c` | 1,173 | Item manipulation | Possible: helper for scalar-to-class resolution |

## Affected Structs

| Struct | File | Change |
|--------|------|--------|
| `HB_ITEM` | `include/hbapi.h:393-415` | **No change.** Scalars remain HB_ITEM unions. Class is resolved at dispatch time from `HB_TYPE`, not stored in the item. |
| `CLASS` | `src/vm/classes.c:143-175` | **No change.** Scalar classes are ordinary classes registered via `hb_clsNew()`. |
| `METHOD` | `src/vm/classes.c:121-139` | **No change.** Scalar class methods use the same METHOD struct. |
| `HB_BASEARRAY` | `include/hbapi.h:417-425` | **No change.** `uiClass` remains 0 for plain arrays; scalar arrays use `s_uiArrayClass` for dispatch only. |

**Key design decision**: we do NOT embed a class handle in `HB_ITEM` or
`HB_BASEARRAY`. Scalar class resolution is a **dispatch-time lookup** via
`hb_objGetScalarClass(pItem->type)` -- an O(1) table indexed by type flags.
This avoids ABI breakage, memory overhead, and GC complexity.

## Compatibility Stance

**Target: 100% source compatibility, 100% ABI compatibility.**

Non-negotiable rules (the Drydock Compatibility Covenant):

1. `ValType()` return values never change.
2. `Len()` on strings always returns bytes.
3. `HB_IS_OBJECT()` returns `.F.` for scalar values -- scalars are NOT objects.
4. `ClassName()` on scalars returns the scalar class name (already works today).
5. Existing operator behavior is identical for all built-in type combinations.
6. User-defined class operator methods always shadow scalar class methods.
7. No new keywords, no grammar changes, no new opcodes.
8. C extensions compiled against current headers link without recompilation.

**Risk**: the only potential fracture is if user code depends on specific
error codes when calling methods on scalars (EG_NOMETHOD 1004). After this
change, method calls that previously errored may succeed if the scalar class
defines the method. This is **additive** and unlikely to break real code.

## Performance Stance

**Must not regress on arithmetic hot paths.**

The integer fast path (`HB_IS_NUMINT(a) && HB_IS_NUMINT(b)`) stays inline
in `hvm.c`. Only the slow-path fallback changes -- from inline type cascades
to `hb_objOperatorCall()` dispatch. The fast path is the common case (>90%
of arithmetic operations in typical Harbour code).

Benchmarks required:
- `hbtest` regression suite: pass with identical results
- Tight arithmetic loop (10M iterations of `n := n + 1`): < 1% regression
- String concatenation loop: < 5% regression (already uses `hb_xrealloc`)
- Method dispatch on scalars (new): establish baseline

## Dependencies

| Dependency | Status | Notes |
|------------|--------|-------|
| [RefactorHvm](../RefactorHvm(SUBSYSTEM)/BRIEF.md) Phases 0-1 | PLANNING | Reduces hvm.c operator cascade copies from ~33 to ~14. Required before Phase 3 (cascade simplification) to avoid maintaining N copies of each change. Phases 1-2 of ScalarClasses can proceed in parallel. |

## Estimated Scope

**2-3 weeks** of focused implementation, broken into:

- **Phase 1** (3-4 days): Add `hb_objGetScalarClass()`, modify `hb_objHasOperator()` and `hb_objOperatorCall()` to resolve scalar classes. No hvm.c changes yet -- just enable the dispatch path.
- **Phase 2** (3-4 days): Add operator methods to `tscalar.prg` classes. Wire `hvm.c` operator cascades to fall through to `hb_objOperatorCall()` for non-fast-path cases.
- **Phase 3** (3-4 days): Add user-facing methods to scalar classes (`Upper`, `Lower`, `Split`, `Format`, etc.). Expand test coverage.
- **Phase 4** (2-3 days): Performance tuning, benchmark verification, documentation.

---
[<- Index](../INDEX.md) · [Map](../MAP.md) · **BRIEF** · [DESIGN](DESIGN.md) · [ARCH](ARCHITECTURE.md) · [API](C_API.md) · [COMPAT](COMPAT.md) · [PLAN](IMPLEMENTATION_PLAN.md) · [TESTS](TEST_PLAN.md) · [MATRIX](TRACEABILITY.md) · [AUDIT](AUDIT.md)
