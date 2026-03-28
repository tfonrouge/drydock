# BRIEF -- ExtensionMethods (FEATURE)

## Identity

| Field | Value |
|-------|-------|
| **Name** | ExtensionMethods |
| **Mode** | FEATURE |
| **Tier** | 1 — Foundation |
| **Component** | Compiler (`src/compiler/`) + VM (`src/vm/classes.c`) |
| **Status** | PLANNING |

---

## 1. Motivation

With DrydockObject and ScalarClasses, every value has a class and every class
has methods — always available, no includes needed. But there's no way for
users to **add methods to existing classes** without editing source files or
using low-level C APIs.

In Harbour, extending a scalar class requires:
```prg
#include "hbclass.ch"
ENABLE TYPE CLASS ALL
EXTEND CLASS CHARACTER WITH
   METHOD addNumeric
ENDCLASS
METHOD CHARACTER:addNumeric( n )
   RETURN Self + hb_ntos( n )
```

This is verbose, requires specific headers, and only works if the class
factory was linked. It's the wrong pattern for a modern OO language.

**The Drydock pattern should be:**
```prg
FUNCTION STRING.addNumeric( n )
   RETURN Self + n:toString()
```

One line declares a method. No boilerplate. No headers. Works on any class —
scalar or user-defined. This is extension methods: the ability to add methods
to any class from any `.prg` file.

---

## 2. Proposed Syntax

### Method Extensions

```prg
/* Add a method to an existing class */
FUNCTION STRING.reverse()
   LOCAL cResult := "", i
   FOR i := Self:Len() TO 1 STEP -1
      cResult += Self:SubStr( i, 1 )
   NEXT
   RETURN cResult

/* Add a method to NUMERIC */
FUNCTION NUMBER.format( cMask )
   RETURN Transform( Self, cMask )

/* Add a method to ARRAY */
FUNCTION ARRAY.sum()
   LOCAL nTotal := 0
   Self:Each({|x| nTotal += x })
   RETURN nTotal
```

### Operator Extensions

```prg
/* String repetition: "abc" * 3 → "abcabcabc" */
FUNCTION STRING.__OpMult( nTimes )
   RETURN Replicate( Self, nTimes )

/* Array concatenation: {1,2} + {3,4} → {1,2,3,4} */
FUNCTION ARRAY.__OpPlus( xOther )
   IF HB_IsArray( xOther )
      RETURN AClone( Self ):AddAll( xOther )
   ENDIF
   RETURN AAdd( AClone( Self ), xOther )
```

### Class Name Aliases

| Modern Name | Legacy Name | Use in Extensions |
|-------------|-------------|-------------------|
| `STRING` | `CHARACTER` | `FUNCTION STRING.method()` |
| `NUMBER` | `NUMERIC` | `FUNCTION NUMBER.method()` |
| `BOOL` | `LOGICAL` | `FUNCTION BOOL.method()` |
| `ARRAY` | `ARRAY` | `FUNCTION ARRAY.method()` |
| `HASH` | `HASH` | `FUNCTION HASH.method()` |
| `DATE` | `DATE` | `FUNCTION DATE.method()` |
| `NIL` | `NIL` | `FUNCTION NIL.method()` |

Both modern and legacy names are accepted.

---

## 3. How It Works

### Compilation

The compiler sees `FUNCTION CLASSNAME.methodName(params)` and generates:

1. A regular function `__ext_CLASSNAME_methodName(params)` with `Self`
   bound to the receiver (via `HB_STACK_TLS_PRELOAD` + `hb_stackSelfItem()`)
2. An `INIT PROCEDURE` that calls `hb_clsAddMsg()` to register the method
   on the named class at module load time

### Initial Implementation (preprocessor)

Before native compiler support, a `#command` directive can transform:
```prg
FUNCTION STRING.reverse()
   ...body...
```
into:
```prg
INIT PROCEDURE __ext_reg_STRING_reverse
   __clsAddMsg( __clsFindByName( "CHARACTER" ), "REVERSE", @__ext_STRING_reverse() )
   RETURN
STATIC FUNCTION __ext_STRING_reverse()
   ...body...    /* Self is available via standard method dispatch */
```

### Native Compiler Support (PersistentAST era)

The parser recognizes dotted function names natively. No preprocessor needed.
The AST node generates the registration code directly.

### Visibility

Extension methods are available to all code in the same executable once the
module containing them is loaded. This follows the same model as Harbour's
existing `INIT PROCEDURE` / `REQUEST` mechanism:

- If the .prg is linked → methods are available at startup
- If loaded via `hb_hrbLoad()` → methods become available at load time
- Scope is global (same as any class method)

---

## 4. What This Unlocks

| Capability | Example |
|------------|---------|
| User adds methods to scalars | `FUNCTION STRING.titleCase()` |
| User adds operators to scalars | `FUNCTION STRING.__OpMult(n)` |
| Contrib adds methods to types | `FUNCTION STRING.parseJSON()` in hbjson |
| Domain-specific extensions | `FUNCTION NUMBER.asCurrency(cSymbol)` |
| Test helpers | `FUNCTION ARRAY.shouldEqual(aExpected)` |

---

## 5. Affected Files

| File | Change |
|------|--------|
| `include/hbclass.ch` | Add `#command FUNCTION <cls>.<method>` preprocessor rule |
| `src/vm/classes.c` | Add `hb_clsFindByName()` — resolve class handle from name string |
| `src/compiler/harbour.y` | (Future) Native dotted function name support |
| `include/hbapicls.h` | Export `hb_clsFindByName()` |

## 6. Compatibility Stance

**100% backward compatible.**

- Extension methods are strictly additive
- No existing syntax changes meaning
- No existing methods are affected
- Works alongside CREATE CLASS / ENDCLASS syntax
- `EXTEND CLASS ... WITH` (Harbour syntax) continues to work

## 7. Dependencies

| Dependency | Status | Notes |
|------------|--------|-------|
| [DrydockObject](../DrydockObject(SUBSYSTEM)/BRIEF.md) | STABLE | Scalar classes must always exist |
| [ScalarClasses](../ScalarClasses(SUBSYSTEM)/BRIEF.md) Phase 2 | ACTIVE | Rich methods in C (extension target) |
| [PersistentAST](../PersistentAST(SUBSYSTEM)/BRIEF.md) | PLANNING | Native compiler support (not required for preprocessor approach) |

## 8. Estimated Scope

| Phase | Effort | Description |
|-------|--------|-------------|
| E.1: Preprocessor approach | 2-3 days | `#command` rule + `hb_clsFindByName()` + tests |
| E.2: Class name aliases | 1 day | STRING→CHARACTER mapping in resolver |
| E.3: Native compiler support | 3-5 days | Parser changes (deferred to PersistentAST) |

---

[<- Index](../INDEX.md) · [Map](../MAP.md) · **BRIEF** · [PLAN](IMPLEMENTATION_PLAN.md) · [TESTS](TEST_PLAN.md) · [AUDIT](AUDIT.md)
