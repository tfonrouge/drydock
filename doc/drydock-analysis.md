# Drydock — Technical Analysis

Deep technical analysis supporting the [Drydock modernization plan](drydock.md).
This document contains the diagnosis, per-workstream design rationale, code
examples, and the full compatibility fracture map.

---

## Table of Contents

1. [Diagnosis: The Core Problem](#diagnosis-the-core-problem)
2. [Scalar Classes](#scalar-classes)
3. [Gradual Strong Typing](#gradual-strong-typing)
4. [Encoding-Aware Strings](#encoding-aware-strings)
5. [Debug Adapter Protocol](#debug-adapter-protocol)
6. [Extension Methods and Traits](#extension-methods-and-traits)
7. [VM Dispatch Table](#vm-dispatch-table)
8. [Structured Reflection](#structured-reflection)
9. [Implementation Order](#implementation-order)
10. [Compatibility Fracture Map](#compatibility-fracture-map)

---

## Diagnosis: The Core Problem

Harbour has **two type systems that do not talk to each other**.

### The operator cascade

Every operator in `src/vm/hvm.c` is a cascade of `if/else if` with brute-force
type checking. For example, `hb_vmPlus()` at line 3280:

```c
if( HB_IS_NUMINT( pItem1 ) && HB_IS_NUMINT( pItem2 ) )      // int + int
else if( HB_IS_NUMERIC( pItem1 ) && HB_IS_NUMERIC( pItem2 ) ) // float + float
else if( HB_IS_STRING( pItem1 ) && HB_IS_STRING( pItem2 ) )   // string + string
else if( HB_IS_DATETIME( pItem1 ) && HB_IS_DATETIME( pItem2 )) // date + date
else if( HB_IS_DATETIME( pItem1 ) && HB_IS_NUMERIC( pItem2 ) ) // date + number
else if( HB_IS_NUMERIC( pItem1 ) && HB_IS_DATETIME( pItem2 ) ) // number + date
else if( ! hb_objOperatorCall( HB_OO_OP_PLUS, ... ) )          // object? last resort
```

This pattern repeats **64 times** across hvm.c (`hb_objOperatorCall` appears 64 times).
Objects are the **last fallback** — a second-class citizen.

### The OO system is sophisticated but underused

In `src/vm/classes.c`, the class system supports:
- Multiple inheritance
- Scoping (PROTECTED, HIDDEN, READONLY)
- Operator overloading (30 operators defined in `hbapicls.h:56-87`)
- Delegation (`HB_OO_MSG_DELEGATE`)
- Properties (`HB_OO_MSG_PROPERTY`)
- Destructors, SYNC methods with mutex
- Virtual methods, inline codeblocks

But a `STRING` never benefits from any of this because it is a flat `char*`
with a `HB_IT_STRING` flag.

### Objects are arrays with a tag

From `include/hbapi.h:418-425`:

```c
typedef struct _HB_BASEARRAY {
   PHB_ITEM    pItems;
   HB_SIZE     nLen;
   HB_SIZE     nAllocated;
   HB_USHORT   uiClass;      // 0 = plain array, >0 = object
   HB_USHORT   uiPrevCls;
} HB_BASEARRAY;
```

`HB_IS_OBJECT(p)` is simply `HB_IS_ARRAY(p) && HB_ARRAY_OBJ(p)`.

**This is the leverage point.** Everything proposed below derives from
unifying the scalar type world with the OO world.

### The scalar classes already exist

`src/rtl/tscalar.prg` contains **12 complete scalar wrapper classes** written
in 2004 by Antonio Linares, with C bindings by Przemyslaw Czerpak in 2007:

| Class | Function Name | Covers |
|-------|--------------|--------|
| ScalarObject | HBScalar | Base class |
| Array | __HBArray | Add, At, AtPut, Collect, Copy, Do, DeleteAt, IndexOf, Scan |
| Block | __HBBlock | AsString |
| Character | __HBCharacter | AsString, AsExpStr |
| Date | __HBDate | Year, Month, Day |
| TimeStamp | __HBTimeStamp | Date, Time, Year, Month, Day, Hour, Minute, Sec |
| Hash | __HBHash | AsString |
| Logical | __HBLogical | AsString |
| NIL | __HBNil | AsString |
| Numeric | __HBNumeric | AsString |
| Symbol | __HBSymbol | AsString |
| Pointer | __HBPointer | AsString |

**But they aren't wired into the VM dispatch.** `hvm.c` has zero references
to `HBScalar`, `__HBCharacter`, or `__HBNumeric`. The `#if 0` blocks in
`classes.c` lines 225-228 (`msgClass`, `msgClassParent`) suggest someone
started this work and abandoned it.

---

## Scalar Classes

### Problem

13+ primitive types managed by if/else cascades in C. You cannot:
- Add a method to String (`:Trim()`, `:Split()`, `:ToUTF8()`)
- Extend Numeric with custom operations
- Make Hash enumerable the same way as Array
- Unify the iteration interface

### Proposal: Wire existing scalar classes into VM dispatch

**Do not change the internal representation.** Items remain `HB_ITEM` with
their union. What changes is that each scalar type gets a `uiClass` registered
at VM startup.

### Impact on hvm.c

The cascade in `hb_vmPlus()` reduces drastically:

```c
// BEFORE: ~80 lines of if/else
// AFTER:
static void hb_vmPlus( PHB_ITEM pResult, PHB_ITEM pItem1, PHB_ITEM pItem2 )
{
   // Fast path for common cases (inlined, no performance change)
   if( HB_IS_NUMINT( pItem1 ) && HB_IS_NUMINT( pItem2 ) )
   {
      /* ... arithmetic fast path unchanged ... */
   }
   // Unified dispatch for everything else
   else if( ! hb_objOperatorCall( HB_OO_OP_PLUS, pResult, pItem1, pItem2, NULL ) )
   {
      hb_errRT_BASE_Subst( EG_ARG, 1081, NULL, "+", 2, pItem1, pItem2 );
   }
}
```

### What this unlocks

1. **User extensibility.** `HBString` is a real class:
   ```clipper
   cName := "harbour"
   ? cName:Upper()        // HBString method
   ? cName:Split( "," )   // extension
   ? cName:Encoding()     // returns codepage info
   ```
2. **Unified interfaces.** `FOREACH` dispatches to `__ENUMSTART`/`__ENUMSKIP`/
   `__ENUMSTOP` for *any* type.
3. **hvm.c shrinks by ~2000 lines.**
4. **Plugins can extend scalar types.** A contrib adds `:ToJSON()` to
   `HBHash` without touching core.

### Implementation steps

1. Register scalar classes during `hb_clsInit()` in `classes.c`
2. Implement `hb_objGetScalarClass( HB_TYPE )` to resolve class for any item
3. Modify `hb_objGetMethod()` to check scalar class when `uiClass == 0`
4. Move type-specific operator logic from hvm.c to scalar class methods
5. Keep arithmetic fast paths inline in hvm.c for performance
6. Add `.prg` wrapper classes with user-facing methods

---

## Gradual Strong Typing

### What already exists

The compiler has partial support for `AS` and `DECLARE` in
`src/compiler/complex.c:89-90`. The lexer parses `AS STRING`, `AS NUMERIC`,
`AS ARRAY OF <type>`, `DECLARE <class>`, and `_HB_MEMBER`.

**But it is cosmetic.** No compile-time type checking occurs.

### Three-phase proposal

**Phase 1 — Compiler-validated type annotations (~4 weeks):**

```clipper
LOCAL cName AS STRING
LOCAL nCount AS NUMERIC := 0
LOCAL oConn AS MyDBConnection

FUNCTION GetUser( cId AS STRING ) AS OBJECT CLASS TUser
```

Emit **warnings** (not errors) for type mismatches. Fully opt-in. Gated behind
`-kt` compiler flag.

**Phase 2 — Runtime type guards (~2 weeks):**

```clipper
LOCAL cName AS STRING! := "hello"   // ! = strict mode
cName := 42  // runtime error
```

Compiler emits `HB_P_TYPECHECK` opcode. Precedent: `classes.c:127` has
`HB_TYPE itemType` for restricted assignment.

**Phase 3 — Type inference (long term):**

```clipper
LOCAL x := GetUser( "123" )   // compiler infers TUser
x:NonExistentMethod()         // compile-time warning
```

---

## Encoding-Aware Strings

### Current problem

`hb_struString` has no encoding field. Encoding is global (`hb_vmCDP()`),
not per-string. Concatenating strings from different codepages produces
silent garbage.

### Proposal

```c
struct hb_struString {
   HB_SIZE  length;
   HB_SIZE  allocated;
   char *   value;
   HB_BYTE  encoding;     // 0=legacy(vmCDP), 1=UTF8, 2=binary
};
```

- `Len()` ALWAYS returns bytes — no semantic change
- New methods: `:Chars()`, `:Bytes()`, `:Encoding()`, `:ToUTF8()`
- `U"..."` literal syntax for UTF-8 strings
- Mixed-encoding concatenation does automatic conversion

---

## Debug Adapter Protocol

### Current state

The debugger (`src/debug/debugger.prg`, 3797 lines) is a TUI with no
conditional breakpoints, no remote debugging, no IDE integration.

### Three-phase proposal

**Phase 1 — Extract debugger API (~2 weeks):**

```c
typedef struct {
   void (*onBreakpoint)( HB_DBG_CTX * ctx, int nLine, const char * szModule );
   void (*onStep)( HB_DBG_CTX * ctx, int nLine );
   void (*onException)( HB_DBG_CTX * ctx, PHB_ITEM pError );
   void (*onModuleLoad)( HB_DBG_CTX * ctx, const char * szModule );
   void (*onThreadStart)( HB_DBG_CTX * ctx, int nThread );
   void (*onOutput)( HB_DBG_CTX * ctx, const char * szText );
} HB_DBG_CALLBACKS;
```

**Phase 2 — DAP server as contrib module (~4 weeks):**

`contrib/hbdap/` implementing the Debug Adapter Protocol (JSON-RPC over
stdio/socket) understood by VSCode, Neovim, Emacs.

**Phase 3 — Conditional breakpoints (~1 week):**

Extend `HB_BREAKPOINT` with `szCondition`, `pCondBlock`, `nHitCount`,
`nHitTarget`, `szLogMessage`.

---

## Extension Methods and Traits

### Extension methods

```clipper
EXTEND CLASS HBString
   METHOD Split( cSeparator )
      // ...
   ENDMETHOD
ENDCLASS
```

Implementation: `__clsAddMsg()` already does this — only syntax sugar needed.

### Traits

```clipper
TRAIT TSerializable
   METHOD ToJSON()
      RETURN hb_jsonEncode( Self )
   ENDMETHOD
ENDTRAIT

CREATE CLASS MyModel
   INHERIT HBObject
   MIXIN TSerializable
   DATA cName
ENDCLASS
```

A trait is a class without direct instantiation. `MIXIN` copies methods via
`__clsAddMsg()`. No VM changes — pure compile-time sugar.

---

## VM Dispatch Table

### Problem

`hvm.c:1387` — a `switch` with 181+ cases, 12,572 lines total.

### Proposal: Threaded dispatch with computed goto

```c
static const void * s_dispatchTable[ HB_P_LAST_PCODE ] = {
   [HB_P_NEGATE] = &&op_negate,
   [HB_P_PLUS]   = &&op_plus,
   // ...
};

#define DISPATCH()  goto *s_dispatchTable[ *pCode ]
#define NEXT()      pCode++; DISPATCH()
```

Split handlers into per-category files (`op_arith.c`, `op_flow.c`,
`op_send.c`, etc.). `hvm.c` goes from 12,572 to ~500 lines.

GCC/Clang: computed goto. MSVC fallback: switch behind `#ifdef`.

---

## Structured Reflection

```clipper
oObj:__Methods()                    // hash { "Name" => { scope, class, type } }
oObj:__Data()                       // hash { "Name" => { value, scope, type } }
oObj:__ClassTree()                  // array of ancestor classes
oObj:__Implements( "TSerializable" ) // .T. / .F.
oObj:__Invoke( "MethodName", aParams ) // dynamic dispatch
```

Already possible via existing `__cls*` functions. Sugar as HBObject methods.

---

## Implementation Order

### Sprint 1 (weeks 1-3): Foundation — Scalar Classes + Reflection

- [ ] Register scalar classes during `hb_clsInit()`
- [ ] Implement `hb_objGetScalarClass( HB_TYPE )`
- [ ] Modify `hb_objGetMethod()` for scalar dispatch
- [ ] Move type-specific operators from hvm.c to scalar class methods
- [ ] Keep arithmetic fast paths inline
- [ ] Add reflection methods to HBObject

### Sprint 2 (weeks 4-6): Extensibility — Extension Methods + Breakpoints

- [ ] Add `EXTEND CLASS` syntax to `harbour.y`
- [ ] Route to `__clsAddMsg()` on resolved class
- [ ] Extend `HB_BREAKPOINT` with condition/hitcount/logpoint
- [ ] Add condition evaluation in `hb_dbgIsBreakPoint()`
- [ ] Test suites for both

### Sprint 3 (weeks 7-10): Debug — DAP Server

- [ ] Define `HB_DBG_CALLBACKS` interface
- [ ] Refactor `dbgentry.c` to dispatch through callbacks
- [ ] Migrate TUI debugger to callback interface
- [ ] Implement DAP server in `contrib/hbdap/`
- [ ] Test with VSCode

### Sprint 4 (weeks 11-14): Type Safety — Typing + Strings

- [ ] Extend `PHB_HVAR` with `declaredType`
- [ ] Post-parse type validation pass
- [ ] Add `encoding` field to `hb_struString`
- [ ] `U"..."` literal syntax
- [ ] Encoding-aware comparison and concatenation
- [ ] HBString methods: `:Encoding()`, `:ToUTF8()`, `:Bytes()`, `:Chars()`,
      `:Split()`, `:Replace()`, `:Matches()`

### Sprint 5 (weeks 15-17): VM + Traits

- [ ] Extract switch cases to labeled blocks
- [ ] Build dispatch table with computed goto
- [ ] Split handler groups into separate files
- [ ] `TRAIT`/`ENDTRAIT`/`MIXIN` syntax
- [ ] Trait as non-instantiable class
- [ ] `MIXIN` as method-copy during class creation

---

## Compatibility Fracture Map

Drydock targets **99.5% backward compatibility**. Not 100%.

**Rule: zero silent data corruption. Zero runtime surprises for correct code.**

### Fracture 1: ValType() Identity Crisis — Risk: 0.05%

**288 call sites** across RTL (107) and contrib (181).

`ValType()` stays based on `HB_ITEM_TYPE()`, not on class.
`HB_IS_OBJECT("hello")` stays `.F.`. The inconsistency (scalar has a class
but isn't an "object") is the **existing behavior** from the 2004 scalar classes.

**Mitigation:** Document. Add `HB_IS_SCALAR(p)` macro.

### Fracture 2: Len() Semantic Split — Risk: 0%

**525 call sites** of `Len()` in RTL alone.

`Len()` ALWAYS returns bytes. Period. New `:Chars()` method for character count.
The 5% risk only exists if someone changes `Len()` — **do not do this**.

### Fracture 3: sizeof(HB_ITEM) ABI Break — Risk: 0.3%

Adding `encoding` byte may change `sizeof(HB_ITEM)`. Source-level: 0%. Binary:
pre-compiled C extensions need recompilation.

**Mitigation:** Check padding first. If it doesn't fit, bump `HB_PCODE_VER`.

### Fracture 4: New Reserved Words — Risk: 0.01%

`TRAIT`, `MIXIN`, `EXTEND` are currently valid identifiers.

**Mitigation:** Context-sensitive keywords (recognized only at statement-start,
like `DECLARE` already is in `complex.c:1107-1134`).

### Fracture 5: New Compiler Warnings — Risk: 0%

Gated behind `-kt` flag. Default off.

### Fracture 6: Extension Method Shadowing — Risk: 0.01%

**Mitigation:** User-defined methods always take priority over scalar class methods.

### Fracture 7: Key Poll Timing — Risk: 0.05%

**Mitigation:** Keep 65536 default. Only change with explicit `SET KEYPOLL`.

### Scoreboard

| Change | Risk | Silent? | Discoverable | Mitigation |
|--------|------|---------|-------------|------------|
| Scalar class wiring | 0.05% | No | Code review | Document, `HB_IS_SCALAR()` |
| `Len()` encoding | 0% | N/A | N/A | Don't change semantics |
| `sizeof(HB_ITEM)` ABI | 0.3% | Crash | Link/load time | Check padding, bump pcode |
| New reserved words | 0.01% | No | Compile time | Context-sensitive keywords |
| Compiler warnings | 0% | N/A | N/A | Gate behind `-kt` |
| Method shadowing | 0.01% | No | Test time | User methods > scalar |
| Key poll timing | 0.05% | Yes | Never crashes | Keep default |
| **Total** | **~0.5%** | | | |
