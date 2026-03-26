# BRIEF -- ModuleSystem (FEATURE)

## Identity

| Field | Value |
|-------|-------|
| **Name** | ModuleSystem |
| **Mode** | FEATURE |
| **Tier** | 2 — Build a Real Compiler |
| **Phase** | H |
| **Component** | Compiler — `src/compiler/harbour.y`, VM — `src/vm/hvm.c` |
| **Status** | PLANNING |

---

## 1. Motivation

Harbour has no module system. All symbols live in a global namespace, resolved
at runtime via a dynamic symbol table with dichotomic search. Name collisions
are resolved by load order. There is no way to:

- Explicitly import only what you need from another module
- Export a controlled public API from a module
- Use namespace-qualified identifiers to avoid collisions
- Resolve symbols at compile time for known modules (performance)

For large codebases (enterprise apps with hundreds of PRG files, contrib
ecosystem with 74 packages), this causes:

- Accidental shadowing of functions by identically-named functions in other files
- No encapsulation — every function is globally visible
- Runtime symbol lookup overhead on every function call
- No compile-time verification that called functions exist

---

## 2. Proposed Syntax

```harbour
/* Module declaration (one per file, optional for backward compat) */
MODULE MyApp.Users

/* Explicit imports */
IMPORT MyApp.Database: Connect, Query
IMPORT MyApp.Logging: *           /* import all exports */

/* Exports (default: nothing exported unless MODULE declared) */
EXPORT FUNCTION GetUser( cId AS STRING ) AS OBJECT
   LOCAL db := Connect()
   RETURN Query( db, "SELECT * FROM users WHERE id = ?", { cId } )
END

/* Private to this module */
FUNCTION ValidateId( cId )
   RETURN Len( cId ) == 36
END
```

All new keywords (`MODULE`, `IMPORT`, `EXPORT`) are context-sensitive — they
only have special meaning at the start of a statement. Existing code using
these as identifiers continues to compile.

---

## 3. Affected Files

| File | Lines | Change |
|------|-------|--------|
| `src/compiler/harbour.y` | 3,011 | Add MODULE/IMPORT/EXPORT grammar rules |
| `src/compiler/complex.c` | ~53K | Context-sensitive keyword recognition |
| `src/vm/hvm.c` | 12,572 | Namespace-qualified symbol resolution |
| `include/hbsymb.h` | ~200 | Add module field to symbol structure |

## 4. Dependencies

| Dependency | Status | Notes |
|------------|--------|-------|
| PersistentAST (Phase E) | PLANNING | Cross-module symbol resolution benefits from AST; not strictly required |

## 5. Estimated Scope

**6 weeks** — grammar changes, symbol table extension, compile-time resolution.

---

[<- Index](../INDEX.md) · [Map](../MAP.md) · **BRIEF**
