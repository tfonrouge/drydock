# BRIEF -- GradualTyping (FEATURE)

## Identity

| Field | Value |
|-------|-------|
| **Name** | GradualTyping |
| **Mode** | FEATURE |
| **Tier** | 2 — Build a Real Compiler |
| **Phase** | F |
| **Component** | Compiler — `src/compiler/`, VM — `src/vm/hvm.c` |
| **Status** | PLANNING |

---

## 1. Motivation

Harbour parses `AS` type annotations but they have **zero semantic effect**.
The grammar supports:

```harbour
LOCAL cName AS STRING
FUNCTION GetUser( cId AS STRING ) AS OBJECT CLASS TUser
```

The compiler stores `ValType` hints in `HB_HVAR` and `HB_EXPR` nodes, then
throws them away. No warnings, no errors, no runtime checks. A developer who
writes `AS STRING` gets zero value from the annotation.

This is the #1 developer productivity gap in Harbour. Type errors are the
most common class of bugs in dynamically-typed languages, and they are
discoverable at compile time with minimal effort.

---

## 2. Proposed Change — Three Phases

### Phase F.1: Compile-Time Warnings (4 weeks)

Walk the persistent AST (from Phase E) and emit warnings for provable type
mismatches. Gate behind `-kt` compiler flag (opt-in, default off).

```harbour
LOCAL cName AS STRING
cName := 42          /* Warning: assigning Numeric to String variable */
cName := GetUser()   /* No warning: return type unknown */
```

**What gets checked:**
- Assignment of known-type literal to typed variable
- Return statement type vs. declared return type
- Argument type vs. declared parameter type (for known functions)
- Binary operator type compatibility (e.g., string + numeric)

**What does NOT get checked (yet):**
- Untyped variables (no inference)
- Dynamic dispatch results (method calls, macro evaluation)
- Array element types
- Hash value types

**Implementation**: AST walker that propagates type information through
expressions and emits warnings at mismatch points. Uses the persistent AST
from Phase E.

### Phase F.2: Flow-Sensitive Type Narrowing (1 week)

Within the AST walker, recognize type-narrowing patterns:

```harbour
LOCAL xVal AS VARIANT
IF HB_ISSTRING( xVal )
   /* xVal is narrowed to STRING in this branch */
   ? xVal:Upper()      /* No warning — String has Upper() */
ELSEIF HB_ISNUMERIC( xVal )
   /* xVal is narrowed to NUMERIC */
   ? xVal + 1           /* No warning — Numeric supports + */
ENDIF
```

This is a lightweight form of type inference that provides high value for
idiomatic Harbour code where `HB_IS*()` guards are pervasive.

### Phase F.3: Optional Runtime Type Guards (1 week)

Emit `HB_P_TYPECHECK` opcode for strict-mode annotations:

```harbour
LOCAL cName AS STRING! := "hello"   /* ! = strict mode */
cName := 42                         /* Runtime error: type mismatch */
```

The `!` suffix is opt-in. Without it, annotations remain advisory (warnings
only). This phase adds a single new opcode to the pcode set.

---

## 3. Affected Files

| File | Lines | Change |
|------|-------|--------|
| `src/compiler/hbexpr.c` | new | Type-checking AST walker |
| `src/compiler/harbour.y` | 3,011 | Parse `!` suffix on type annotations |
| `src/compiler/hbmain.c` | 4,526 | Invoke type checker after AST construction |
| `include/hbpcode.h` | ~250 | Add `HB_P_TYPECHECK` opcode (Phase F.3 only) |
| `src/vm/hvm.c` | 12,572 | Handle `HB_P_TYPECHECK` opcode (Phase F.3 only) |
| `src/compiler/genc.c` | 2,771 | Emit `HB_P_TYPECHECK` in C output |

## 4. Compatibility Stance

**Target: 100% backward compatibility.**

- Warnings are off by default. Gate behind `-kt` flag.
- No existing code produces warnings unless `-kt` is explicitly passed.
- `HB_P_TYPECHECK` opcode only emitted for `AS TYPE!` strict annotations — new
  syntax that no existing code uses.
- Pcode version bump required for Phase F.3 (new opcode).

## 5. Dependencies

| Dependency | Status | Notes |
|------------|--------|-------|
| PersistentAST (Phase E) | PLANNING | **Required** — type checking walks the AST |

**Blocks**: LSPServer (Phase I) — type information feeds hover and diagnostics.

## 6. Estimated Scope

| Phase | Effort | Can Ship Independently |
|-------|--------|----------------------|
| F.1: Compile-time warnings | 4 weeks | Yes |
| F.2: Flow-sensitive narrowing | 1 week | Yes (after F.1) |
| F.3: Runtime type guards | 1 week | Yes (after F.1) |
| **Total** | **6 weeks** | |

---

[<- Index](../INDEX.md) · [Map](../MAP.md) · **BRIEF**
