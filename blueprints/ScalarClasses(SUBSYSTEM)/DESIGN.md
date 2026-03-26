# DESIGN -- ScalarClasses (SUBSYSTEM)

## 1. Current State

### Operator Dispatch in hvm.c

Every arithmetic/comparison operator in `src/vm/hvm.c` follows an identical
pattern -- a cascade of type checks with `hb_objOperatorCall()` as the last
resort:

```c
/* hvm.c:3280-3394 — hb_vmPlus() */
static void hb_vmPlus( PHB_ITEM pResult, PHB_ITEM pItem1, PHB_ITEM pItem2 )
{
   if( HB_IS_NUMINT( pItem1 ) && HB_IS_NUMINT( pItem2 ) )
      /* integer fast path — overflow to double */
   else if( HB_IS_NUMERIC( pItem1 ) && HB_IS_NUMERIC( pItem2 ) )
      /* float arithmetic */
   else if( HB_IS_STRING( pItem1 ) && HB_IS_STRING( pItem2 ) )
      /* string concatenation */
   else if( HB_IS_DATETIME( pItem1 ) && HB_IS_DATETIME( pItem2 ) )
      /* datetime addition */
   else if( HB_IS_DATETIME( pItem1 ) && HB_IS_NUMERIC( pItem2 ) )
      /* datetime + numeric */
   else if( HB_IS_NUMERIC( pItem1 ) && HB_IS_DATETIME( pItem2 ) )
      /* numeric + datetime */
   else if( ! hb_objOperatorCall( HB_OO_OP_PLUS, pResult, pItem1, pItem2, NULL ) )
      /* error: EG_ARG 1081 */
}
```

There are **64 `hb_objOperatorCall` call sites** across `hvm.c` (12,572 lines),
covering all 30 operators.

### Scalar Class Registration (already working)

Twelve scalar class handles are declared in `classes.c:327-339`:

```c
static HB_USHORT s_uiArrayClass     = 0;
static HB_USHORT s_uiBlockClass     = 0;
static HB_USHORT s_uiCharacterClass = 0;
static HB_USHORT s_uiDateClass      = 0;
static HB_USHORT s_uiTimeStampClass = 0;
static HB_USHORT s_uiHashClass      = 0;
static HB_USHORT s_uiLogicalClass   = 0;
static HB_USHORT s_uiNilClass       = 0;
static HB_USHORT s_uiNumericClass   = 0;
static HB_USHORT s_uiSymbolClass    = 0;
static HB_USHORT s_uiPointerClass   = 0;
static HB_USHORT s_uiObjectClass    = 0;
```

These are initialized by `hb_clsDoInit()` (`classes.c:1153-1187`), which calls
the PRG factory functions (`HBARRAY`, `HBBLOCK`, `HBCHARACTER`, ...) defined in
`src/rtl/tscalar.prg` and stores the resulting class handles.

### Scalar Class Resolution (already working)

The **internal** function `hb_objGetClassH()` (`classes.c:1360-1402`) resolves
scalar classes for any item type:

```c
static HB_USHORT hb_objGetClassH( PHB_ITEM pObject )
{
   if( HB_IS_ARRAY( pObject ) )
   {
      if( pObject->item.asArray.value->uiClass != 0 )
         return pObject->item.asArray.value->uiClass;  /* real object */
      else
         return s_uiArrayClass;                         /* plain array */
   }
   else if( HB_IS_NIL( pObject ) )    return s_uiNilClass;
   else if( HB_IS_STRING( pObject ) ) return s_uiCharacterClass;
   else if( HB_IS_NUMERIC( pObject ) ) return s_uiNumericClass;
   /* ... all other types ... */
   return 0;
}
```

### Operator Dispatch (already scalar-aware)

`hb_objHasOperator()` (`classes.c:2406-2419`) uses `hb_objGetClassH()`:

```c
HB_BOOL hb_objHasOperator( PHB_ITEM pObject, HB_USHORT uiOperator )
{
   HB_USHORT uiClass = hb_objGetClassH( pObject );
   if( uiClass && uiClass <= s_uiClasses )
      return ( s_pClasses[ uiClass ]->nOpFlags & ( 1 << uiOperator ) ) != 0;
   return HB_FALSE;
}
```

This already resolves scalar class handles. If `s_uiCharacterClass` has
`HB_OO_OP_PLUS` in its `nOpFlags`, then `hb_objHasOperator("hello", HB_OO_OP_PLUS)`
returns `HB_TRUE`.

`hb_objOperatorCall()` (`classes.c:2425-2455`) dispatches via `hb_vmSend()`:

```c
HB_BOOL hb_objOperatorCall( HB_USHORT uiOperator, PHB_ITEM pResult,
                            PHB_ITEM pObject, PHB_ITEM pMsgArg1, PHB_ITEM pMsgArg2 )
{
   if( hb_objHasOperator( pObject, uiOperator ) )
   {
      hb_vmPushSymbol( s_opSymbols + uiOperator );
      hb_vmPush( pObject );
      /* push args, call hb_vmSend(), copy result */
      return HB_TRUE;
   }
   return HB_FALSE;
}
```

### Method Dispatch for Scalars (already working)

`hb_objGetMethod()` (`classes.c:1802-2209`) already dispatches method calls to
scalar classes via `hb_clsScalarMethod()`:

```c
/* classes.c:2064-2074 — inside hb_objGetMethod() */
else if( HB_IS_STRING( pObject ) )
{
   if( s_uiCharacterClass )
   {
      pClass = s_pClasses[ s_uiCharacterClass ];
      PHB_SYMB pExecSym = hb_clsScalarMethod( pClass, pMsg, pStack );
      if( pExecSym )
         return pExecSym;
   }
}
```

This means `"hello":AsString()` already works today because the Character
class defines `AsString()`.

### Public vs Internal Class Resolution

| Function | Scope | Resolves Scalars? | Used By |
|----------|-------|-------------------|---------|
| `hb_objGetClass()` | Public (`hbapicls.h:121`) | **No** — returns 0 for non-arrays | C extensions, `__objGetClass()` PRG function |
| `hb_objGetClassH()` | Internal (`classes.c:1360`) | **Yes** — returns scalar class handle | `hb_objHasOperator()`, `hb_objGetClsName()` |

This is intentional. The public API preserves `HB_IS_OBJECT()` semantics:
scalars are NOT objects, even though they have associated classes.

### Scalar Classes in tscalar.prg (404 lines)

Twelve classes, all inheriting from `ScalarObject` (alias `HBScalar`):

| Class | PRG Function | Methods Today |
|-------|-------------|---------------|
| ScalarObject | `HBScalar` | `Copy`, `IsScalar`, `AsString`, `AsExpStr` |
| Array | `__HBArray` | `Init`, `AsString`, `At`, `AtPut`, `Add`, `Collect`, `Copy`, `Do`, `DeleteAt`, `InsertAt`, `IndexOf`, `Remove`, `Scan`, `_Size` |
| Block | `__HBBlock` | `AsString` |
| Character | `__HBCharacter` | `AsString`, `AsExpStr` |
| Date | `__HBDate` | `Year`, `Month`, `Day`, `AsString`, `AsExpStr` |
| TimeStamp | `__HBTimeStamp` | `Date`, `Time`, `Year`, `Month`, `Day`, `Hour`, `Minute`, `Sec`, `AsString`, `AsExpStr` |
| Hash | `__HBHash` | `AsString` |
| Logical | `__HBLogical` | `AsString` |
| NIL | `__HBNil` | `AsString` |
| Numeric | `__HBNumeric` | `AsString` |
| Symbol | `__HBSymbol` | `AsString` |
| Pointer | `__HBPointer` | `AsString` |

**None of these classes define operator methods.** No `__OPPLUS`, `__OPMINUS`,
or any of the 30 operator symbols.

---

## 2. Problem Statement

The dispatch infrastructure for scalar-class operators **already exists and
works**. The chain is:

```
hb_vmPlus() → hb_objOperatorCall() → hb_objHasOperator() → hb_objGetClassH()
                                                              ↓
                                              returns s_uiCharacterClass (etc.)
                                                              ↓
                                      checks pClass->nOpFlags & (1 << operator)
                                                              ↓
                                             returns HB_FALSE — no operator flag set
```

The failure point is at `nOpFlags`: scalar classes have **no operator methods
registered**, so `nOpFlags == 0`, so `hb_objHasOperator()` returns `HB_FALSE`,
so `hb_objOperatorCall()` returns `HB_FALSE`, and the error handler fires.

Meanwhile, the inline type cascades in `hvm.c` handle all standard type
combinations (string+string, num+num, date+num, etc.) before
`hb_objOperatorCall` is ever reached. These cascades are:

- **Unreachable by scalar class dispatch** -- the inline code fires first
- **Not extensible** -- users cannot override string concatenation behavior
- **Verbose** -- ~2,000 lines of type-check boilerplate across 64 call sites

---

## 3. Proposed Changes

### 3.1 Add Operator Methods to Scalar Classes (tscalar.prg)

**No C changes required.** Adding operator methods to the PRG classes
automatically sets `nOpFlags` in the class's `CLASS` struct via
`hb_clsAddMsg()` (`classes.c:2902-2965`), which detects operator symbol
names and sets the corresponding bit.

#### Character Class — Operators

```harbour
CREATE CLASS Character INHERIT HBScalar FUNCTION __HBCharacter

   METHOD AsString()
   METHOD AsExpStr()

   /* String operators */
   OPERATOR "+"  ARG xOther  INLINE Self + xOther    /* handled inline for str+str */
   OPERATOR "-"  ARG xOther  INLINE Self - xOther    /* right-trim + concat */
   OPERATOR "="  ARG xOther  INLINE Self = xOther    /* loose comparison */
   OPERATOR "==" ARG xOther  INLINE Self == xOther   /* exact comparison */
   OPERATOR "!=" ARG xOther  INLINE Self != xOther
   OPERATOR "<"  ARG xOther  INLINE Self < xOther
   OPERATOR "<=" ARG xOther  INLINE Self <= xOther
   OPERATOR ">"  ARG xOther  INLINE Self > xOther
   OPERATOR ">=" ARG xOther  INLINE Self >= xOther
   OPERATOR "$"  ARG xOther  INLINE Self $ xOther    /* substring check */

ENDCLASS
```

**Important**: these operators initially just re-execute the built-in
operation. They will only be invoked when the hvm.c inline cascade does NOT
match (i.e., for cross-type combinations that currently error). Over time,
the method bodies can be enriched with type-coercion logic.

The same pattern applies to Numeric, Date, TimeStamp, Logical, Array, and
Hash classes -- each gets the operators that make sense for its type.

#### Recursion Guard

When a scalar operator method executes `Self + xOther` and both operands are
the same type, the hvm.c inline cascade handles it directly. The scalar class
method is **never re-entered** because:

1. `hb_vmPlus()` checks `HB_IS_STRING(pItem1) && HB_IS_STRING(pItem2)` first
2. Only if no inline match does it fall through to `hb_objOperatorCall()`
3. The scalar method body does `Self + xOther` which re-enters `hb_vmPlus()`
4. If Self is a string and xOther is also a string, step 1 matches
5. The inline code handles it -- no recursive dispatch

For cross-type cases (e.g., `"hello" + 5`), the scalar method would need
explicit handling. Initially, these will raise the same type error as today.

### 3.2 New Public Function: `hb_objGetScalarClass()` (classes.c, hbapicls.h)

Expose scalar class resolution as a public API for C extensions.

```c
/* classes.c — new function */
HB_USHORT hb_objGetScalarClass( PHB_ITEM pItem )
{
   return hb_objGetClassH( pItem );
}
```

This is a thin wrapper over the existing internal `hb_objGetClassH()`. The
public API name makes the intent explicit: "give me the class handle that
the OO system would use for this item, even if it's a scalar."

**Why not just make `hb_objGetClassH()` public?** Because `hb_objGetClass()`
already exists as public API with different semantics (returns 0 for non-objects).
Renaming or changing it would break C extensions. A new function avoids ambiguity.

### 3.3 Add User-Facing Methods to Scalar Classes (tscalar.prg)

Extend scalar classes with methods that wrap existing RTL functions:

#### Character Class — Methods

| Method | Wraps | Signature |
|--------|-------|-----------|
| `Upper()` | `Upper()` | `:Upper() --> cString` |
| `Lower()` | `Lower()` | `:Lower() --> cString` |
| `Trim()` | `AllTrim()` | `:Trim() --> cString` |
| `LTrim()` | `LTrim()` | `:LTrim() --> cString` |
| `RTrim()` | `RTrim()` | `:RTrim() --> cString` |
| `Left(n)` | `Left()` | `:Left(n) --> cString` |
| `Right(n)` | `Right()` | `:Right(n) --> cString` |
| `SubStr(n,l)` | `SubStr()` | `:SubStr(nStart[,nLen]) --> cString` |
| `At(cSub)` | `At()` | `:At(cSearch) --> nPos` |
| `Len()` | `Len()` | `:Len() --> nLength` |
| `Empty()` | `Empty()` | `:Empty() --> lEmpty` |
| `Replicate(n)` | `Replicate()` | `:Replicate(nTimes) --> cString` |
| `Reverse()` | -- | `:Reverse() --> cString` |
| `Split(cDel)` | `hb_ATokens()` | `:Split([cDelim]) --> aTokens` |

#### Numeric Class — Methods

| Method | Wraps | Signature |
|--------|-------|-----------|
| `Abs()` | `Abs()` | `:Abs() --> nAbsolute` |
| `Int()` | `Int()` | `:Int() --> nInteger` |
| `Round(n)` | `Round()` | `:Round(nDec) --> nRounded` |
| `Str(l,d)` | `Str()` | `:Str([nLen],[nDec]) --> cString` |
| `Min(n)` | `Min()` | `:Min(nOther) --> nMinimum` |
| `Max(n)` | `Max()` | `:Max(nOther) --> nMaximum` |
| `Empty()` | `Empty()` | `:Empty() --> lEmpty` |
| `Between(a,b)` | -- | `:Between(nLow,nHigh) --> lInRange` |

#### Date / TimeStamp — Methods

Already have `Year()`, `Month()`, `Day()`, `Hour()`, `Minute()`, `Sec()`.
Add:

| Method | Wraps | Signature |
|--------|-------|-----------|
| `AddDays(n)` | -- | `:AddDays(nDays) --> dDate` |
| `DiffDays(d)` | -- | `:DiffDays(dOther) --> nDays` |
| `DOW()` | `DOW()` | `:DOW() --> nDayOfWeek` |
| `Empty()` | `Empty()` | `:Empty() --> lEmpty` |

#### Logical — Methods

| Method | Wraps | Signature |
|--------|-------|-----------|
| `IsTrue()` | -- | `:IsTrue() --> lValue` |
| `Toggle()` | -- | `:Toggle() --> lOpposite` |

#### Array — Additional Methods

Already has `At`, `AtPut`, `Add`, `Collect`, `Copy`, `Do`, `DeleteAt`,
`InsertAt`, `IndexOf`, `Remove`, `Scan`, `_Size`. Add:

| Method | Wraps | Signature |
|--------|-------|-----------|
| `Len()` | `Len()` | `:Len() --> nCount` |
| `Empty()` | `Empty()` | `:Empty() --> lEmpty` |
| `Sort(b)` | `ASort()` | `:Sort([bCompare]) --> aSorted` |
| `Tail()` | `ATail()` | `:Tail() --> xValue` |
| `Each(b)` | -- | `:Each(bBlock) --> Self` |
| `Map(b)` | -- | `:Map(bBlock) --> aNew` |
| `Filter(b)` | -- | `:Filter(bBlock) --> aNew` |
| `Reduce(b,x)` | -- | `:Reduce(bBlock[,xInit]) --> xResult` |

#### Hash — Methods

| Method | Wraps | Signature |
|--------|-------|-----------|
| `Keys()` | `hb_HKeys()` | `:Keys() --> aKeys` |
| `Values()` | `hb_HValues()` | `:Values() --> aValues` |
| `Len()` | `Len()` | `:Len() --> nCount` |
| `Empty()` | `Empty()` | `:Empty() --> lEmpty` |
| `HasKey(x)` | `hb_HHasKey()` | `:HasKey(xKey) --> lExists` |
| `Del(x)` | `hb_HDel()` | `:Del(xKey) --> hHash` |

### 3.4 Simplify hvm.c Operator Cascades (Phase 3 — Optional)

**NOT part of the initial implementation.** Documented here for completeness.

Once scalar class operators are proven correct and benchmarked, the hvm.c
cascades can be simplified. For example, `hb_vmPlus()` would become:

```c
static void hb_vmPlus( PHB_ITEM pResult, PHB_ITEM pItem1, PHB_ITEM pItem2 )
{
   /* Integer fast path — keep inline for performance */
   if( HB_IS_NUMINT( pItem1 ) && HB_IS_NUMINT( pItem2 ) )
   {
      /* unchanged: overflow-checked integer addition */
   }
   /* Everything else goes through scalar class dispatch */
   else if( ! hb_objOperatorCall( HB_OO_OP_PLUS, pResult, pItem1, pItem2, NULL ) )
   {
      PHB_ITEM pSubst = hb_errRT_BASE_Subst( EG_ARG, 1081, NULL, "+", 2, pItem1, pItem2 );
      if( pSubst )
      {
         hb_itemMove( pResult, pSubst );
         hb_itemRelease( pSubst );
      }
   }
}
```

This would remove ~90 lines from `hb_vmPlus()` alone. Across all 64 operator
call sites, the reduction would be ~1,500-2,000 lines.

**Prerequisites for Phase 3:**
- [RefactorHvm](../RefactorHvm(SUBSYSTEM)/BRIEF.md) Phases 0-1 complete
  (reduces cascade copies from ~33 to ~14; without this, simplification
  must be replicated across all copies — guaranteed divergence bugs)
- All operator methods in tscalar.prg verified against hbtest
- Performance benchmark shows < 5% regression on string concatenation loops
- The string+string operator method in Character class must match the exact
  semantics of the current inline code (including MEMO flag handling, overflow
  checks, etc.)

---

## 4. Memory Layout Impact

**None.** No struct changes to `HB_ITEM`, `HB_BASEARRAY`, `CLASS`, or `METHOD`.

Scalar class resolution is a dispatch-time lookup via `hb_objGetClassH()` -- the
class handle is never stored in the item. This avoids:

- ABI breakage (no `sizeof` changes)
- GC complexity (no new pointers to trace)
- Memory overhead (no per-item class field)

The `nOpFlags` field in `CLASS` is already a `HB_U32` bitmask with room for 32
operators (30 currently used). No expansion needed.

---

## 5. Registration / Initialization

The initialization sequence is **unchanged**:

```
VM startup
  → hb_clsInit()           classes.c:1102   Initialize OO system, register operator symbols
  → ...
  → hb_clsDoInit()         classes.c:1153   Call tscalar.prg factory functions
    → HBCHARACTER()         tscalar.prg      Creates Character class, returns instance
    → __CLSASSOCTYPE()      classes.c:4044   Associates class handle with HB_IT_STRING
    → s_uiCharacterClass = uiClass           Stored in static variable
    → ... (repeat for all 12 scalar types)
```

Adding operator methods to the scalar classes changes nothing in this sequence.
The `OPERATOR` keyword in `hbclass.ch` compiles to `__clsAddMsg()` calls during
class creation, which automatically set `nOpFlags` bits.

---

## 6. Dispatch / Resolution

### Current Operator Flow (no scalar class participation)

```
hb_vmPlus("hello", 5)
  ├─ HB_IS_NUMINT("hello") && HB_IS_NUMINT(5)?  → NO
  ├─ HB_IS_NUMERIC("hello") && HB_IS_NUMERIC(5)? → NO
  ├─ HB_IS_STRING("hello") && HB_IS_STRING(5)?   → NO
  ├─ HB_IS_DATETIME(...)                          → NO
  ├─ hb_objOperatorCall(HB_OO_OP_PLUS, ..., "hello", 5, NULL)
  │   └─ hb_objHasOperator("hello", HB_OO_OP_PLUS)
  │       └─ hb_objGetClassH("hello") → s_uiCharacterClass
  │       └─ nOpFlags & (1 << 0) → 0 (no __OPPLUS defined)
  │       └─ returns HB_FALSE
  │   └─ returns HB_FALSE
  └─ Error: EG_ARG 1081
```

### Proposed Operator Flow (scalar class participation)

```
hb_vmPlus("hello", 5)
  ├─ HB_IS_NUMINT("hello") && HB_IS_NUMINT(5)?  → NO
  ├─ HB_IS_NUMERIC("hello") && HB_IS_NUMERIC(5)? → NO
  ├─ HB_IS_STRING("hello") && HB_IS_STRING(5)?   → NO
  ├─ HB_IS_DATETIME(...)                          → NO
  ├─ hb_objOperatorCall(HB_OO_OP_PLUS, ..., "hello", 5, NULL)
  │   └─ hb_objHasOperator("hello", HB_OO_OP_PLUS)
  │       └─ hb_objGetClassH("hello") → s_uiCharacterClass
  │       └─ nOpFlags & (1 << 0) → 1 (__OPPLUS is defined!)
  │       └─ returns HB_TRUE
  │   └─ hb_vmPushSymbol(__OPPLUS)
  │   └─ hb_vmPush("hello")   // Self
  │   └─ hb_vmPush(5)         // argument
  │   └─ hb_vmSend(1)
  │       └─ hb_objGetMethod("hello", __OPPLUS, &stack)
  │           └─ HB_IS_STRING → s_uiCharacterClass
  │           └─ hb_clsScalarMethod(Character, __OPPLUS, stack)
  │           └─ hb_clsFindMsg → finds operator method → returns pFuncSym
  │       └─ HB_VM_EXECUTE(pFuncSym)
  │           └─ Character:__OPPLUS(5) executes
  │   └─ hb_itemMove(pResult, returnItem)
  │   └─ returns HB_TRUE
  └─ Result stored in pResult
```

### Same-Type Operations (unchanged)

```
hb_vmPlus("hello", " world")
  ├─ HB_IS_STRING("hello") && HB_IS_STRING(" world")? → YES
  └─ Inline string concatenation (never reaches scalar class)
```

The inline cascades fire first, so **all existing behavior is preserved**.
Scalar class operators only participate for type combinations that currently
produce errors.

### Recursion Safety

When a scalar operator method body re-executes the built-in operation:

```harbour
OPERATOR "+" ARG xOther
   IF ValType( xOther ) == "C"
      RETURN Self + xOther     /* re-enters hb_vmPlus — inline handles str+str */
   ENDIF
   RETURN NIL   /* or error */
```

The `Self + xOther` in the method body enters `hb_vmPlus()` again.
If both operands are strings, the inline `HB_IS_STRING && HB_IS_STRING`
check matches, and the concatenation happens without ever reaching
`hb_objOperatorCall`. **No infinite recursion.**

---

## 7. Performance Analysis

### Hot Path: Integer Arithmetic (unchanged)

The integer fast path in `hb_vmPlus()` (`hvm.c:3284-3305`) is the first check:

```c
if( HB_IS_NUMINT( pItem1 ) && HB_IS_NUMINT( pItem2 ) )
```

This path has **zero overhead** from scalar classes. It never reaches
`hb_objOperatorCall`.

### Hot Path: String Concatenation (unchanged)

```c
else if( HB_IS_STRING( pItem1 ) && HB_IS_STRING( pItem2 ) )
```

Same — handled inline before scalar dispatch. Zero overhead.

### Cold Path: Fallthrough to hb_objOperatorCall

Currently: `hb_objOperatorCall → hb_objHasOperator → hb_objGetClassH → return FALSE`

Proposed: Same chain, but returns TRUE and dispatches. The dispatch adds:
- `hb_vmPushSymbol` — push operator symbol (fast: no allocation)
- `hb_vmPush` × 2 — push self and argument (stack operations)
- `hb_vmSend(1)` → `hb_objGetMethod` → `hb_clsScalarMethod` → hash lookup
- Method execution (PRG function call)

**Estimated overhead per dispatch**: ~200-500 ns (vs. ~10 ns for inline).

This only matters for cases that **currently produce errors** (like
`string + number`). There is no regression for any working code path.

### Phase 3 Cost (future, optional)

If string+string concatenation is moved to the scalar class, the overhead
would be the dispatch cost (~200-500 ns) vs. the current inline cost (~50 ns).
This is measurable for tight loops. Benchmarks must verify < 5% regression
before proceeding.

### Benchmark Plan

| Test | Current | Target | Method |
|------|---------|--------|--------|
| `n := n + 1` × 10M | Baseline | < 1% regression | `hbtest` + custom `.prg` |
| `c := c + c` × 1M | Baseline | 0% regression (inline path unchanged) | Custom `.prg` |
| `d + n` × 1M | Baseline | 0% regression (inline path unchanged) | Custom `.prg` |
| `"hello":Upper()` × 1M | N/A | Establish baseline | Custom `.prg` |
| `cVar + nVar` × 1M (cross-type) | Error | Establish baseline | Custom `.prg` |

---

## 8. Alternatives Considered

### Alternative A: Embed Class Handle in HB_ITEM

Add a `HB_USHORT uiClass` field to the HB_ITEM union variants (or the HB_ITEM
struct itself), so every item carries its class handle.

**Rejected because:**
- Increases `sizeof(HB_ITEM)` — ABI break for all compiled extensions
- Requires updating every item creation path (hundreds of call sites)
- GC must trace the new field
- `hb_objGetClassH()` already provides O(1) resolution for scalars

### Alternative B: Create Objects Instead of Scalars

Make `hb_itemPutC()` return an actual object (array with `uiClass != 0`)
instead of a plain string item.

**Rejected because:**
- Breaks `HB_IS_OBJECT()` semantics (covenant violation)
- `ValType()` would return "O" instead of "C" (covenant violation)
- Massive memory overhead (every string becomes an array)
- Breaks all C code that accesses `pItem->item.asString.value` directly

### Alternative C: Virtual Method Table in HB_TYPE

Use unused bits in `HB_TYPE` (32-bit, only 20 bits used) to store a class
index.

**Rejected because:**
- Clever but fragile — `HB_TYPE` is used as a bitmask throughout the codebase
- Would break all `HB_IS_*` macros unless carefully masked
- 12 unused bits = max 4096 classes, which may conflict with the 16382
  class pool size in MT mode
- `hb_objGetClassH()` is simpler and already works

### Alternative D: C-Level Operator Methods

Implement scalar operator methods in C (in `classes.c`) instead of PRG
(in `tscalar.prg`).

**Partially accepted for Phase 3:**
- PRG methods have dispatch overhead
- For the hot-path simplification (Phase 3), we may need C-level
  implementations like `HB_FUNC( HB_CHAROP_PLUS )` that replicate the
  inline logic but are callable via the method dispatch table
- But for Phase 1-2, PRG methods are simpler and sufficient

---

[<- Index](../INDEX.md) . [Map](../MAP.md) . [BRIEF](BRIEF.md) . **DESIGN** . [ARCH](ARCHITECTURE.md) . [API](C_API.md) . [COMPAT](COMPAT.md) . [PLAN](IMPLEMENTATION_PLAN.md) . [TESTS](TEST_PLAN.md) . [MATRIX](TRACEABILITY.md) . [AUDIT](AUDIT.md)
