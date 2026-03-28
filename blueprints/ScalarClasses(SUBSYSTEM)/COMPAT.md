# COMPAT -- ScalarClasses (SUBSYSTEM)

## Compatibility Target

**100% source compatibility. 100% ABI compatibility.**

## Compatibility Covenant (non-negotiable)

1. `ValType()` return values never change
2. `Len()` on strings always returns bytes
3. `HB_IS_OBJECT()` returns `.F.` for scalar values
4. Existing operator behavior is identical for all built-in type combinations
5. User-defined class operator methods always shadow scalar class methods
6. No new keywords, no grammar changes, no new opcodes
7. C extensions compiled against current headers link without recompilation

## Fracture Analysis

### Fracture 1: Methods That Previously Errored Now Succeed — Risk: LOW

**Description**: Calling a method on a scalar value that didn't have a scalar
class registered would previously produce `Error BASE/1004 No exported method`.
After this change, `toString()`, `className()`, `isScalar()`, `isNil()`,
`valType()` will succeed on ALL values.

**Call sites affected**: Zero — no existing Harbour code calls `:toString()` on
scalar values because it would error. Only NEW code uses the new methods.

**Silent?**: No — the change is from "error" to "success". This is strictly
additive. Code that previously worked continues to work identically.

**Discoverable**: Not applicable — no code breaks.

**Mitigation**: None needed. Additive change.

### Fracture 2: Default Parent Class Changes — Risk: MEDIUM

**Description**: User-defined classes with no `FROM` clause currently inherit
from `HBObject` (defined in `tobject.prg`). After this change, they inherit
from `DrydockObject` (defined in C). DrydockObject must provide the same
methods as HBObject, or HBObject must inherit from DrydockObject.

**Call sites affected**: Any class using `HBObject` methods (NEW, INIT, ERROR,
ISKINDOF, ISDERIVEDFROM, MSGNOTFOUND).

**Silent?**: Could be silent if DrydockObject doesn't provide a method that
HBObject provided.

**Discoverable**: Runtime — method-not-found error.

**Mitigation**: Either (a) DrydockObject includes all HBObject methods, or
(b) HBObject inherits from DrydockObject (preserving the method chain).
Option (b) is recommended — minimal change, preserves compatibility.

### Fracture 3: Class Handle Values Change — Risk: LOW

**Description**: Scalar class handles (ClassH values) change because classes
are now created in a different order (C init before PRG init). Code that
hardcodes class handle numbers will break.

**Call sites affected**: Extremely unlikely — class handles are opaque.

**Discoverable**: Runtime — wrong class operations.

**Mitigation**: No code should hardcode class handles. ClassH is an opaque value.

### Fracture 4: Module System Interaction — Risk: LOW (forward reference)

**Description**: When ModuleSystem (Phase H) ships, scalar class methods
(Upper, Lower, Split, Map, etc.) must remain available without explicit
IMPORT statements. Scalar classes are always-available VM-level features,
not library features that belong to a namespace. This is a design constraint
on ModuleSystem, not a change to ScalarClasses.

**Call sites affected**: None — this is a constraint on future work.

**Discoverable**: N/A — preventive.

**Mitigation**: ModuleSystem defines a "built-in namespace exception list"
(see [ModuleSystem DESIGN.md](../ModuleSystem(FEATURE)/DESIGN.md) Section 5)
that includes all scalar class methods. Scalar methods are resolved via
`hb_objGetMethod()` class dispatch, not the dynsym function table, so they
are inherently namespace-independent.

## Migration Guide

**For existing Harbour code**: No changes needed. Everything works as before.

**For code that wants new features**: Use `:toString()`, `:className()`,
`:isScalar()`, `:isNil()`, `:valType()` on any value. No includes or
REQUEST statements needed.

**For code using scalar class methods (Upper, etc.)**: All scalar methods
are now built into the VM. `ENABLE TYPE CLASS ALL` is deprecated and no
longer needed. Remove it from your code — methods work without it.

---

[<- Index](../INDEX.md) · [Map](../MAP.md) · [BRIEF](BRIEF.md) · [DESIGN](DESIGN.md) · [ARCH](ARCHITECTURE.md) · [API](C_API.md) · **COMPAT** · [PLAN](IMPLEMENTATION_PLAN.md) · [TESTS](TEST_PLAN.md) · [MATRIX](TRACEABILITY.md) · [AUDIT](AUDIT.md)
