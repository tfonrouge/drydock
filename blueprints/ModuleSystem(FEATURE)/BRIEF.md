# BRIEF -- ModuleSystem (FEATURE)

## Identity

| Field | Value |
|-------|-------|
| **Name** | ModuleSystem |
| **Mode** | FEATURE |
| **Tier** | 2 — Build a Real Compiler |
| **Phase** | H |
| **Component** | Compiler — `src/compiler/harbour.y`, VM — `src/vm/dynsym.c`, Macro — `src/macro/` |
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

### 2.1 Files Without MODULE Declaration

Files without a `MODULE` declaration are treated as belonging to the **global
namespace** — exactly as today. All their public functions are registered in the
dynamic symbol table with unqualified names. All existing `.prg` files continue
to compile and behave identically. The module system is entirely opt-in.

This means namespaces provide protection only within adopting codebases. Legacy
code and new module-aware code coexist in the same process without conflict.

### 2.2 Built-In Namespace Exceptions

The following symbols are always available without IMPORT, regardless of
MODULE context:

- **DrydockObject methods**: `toString`, `className`, `isScalar`, `isNil`,
  `valType`, `compareTo`, `isComparable` — resolved by `hb_objGetMethod()`
  built-in message dispatch, not the dynamic symbol table.
- **Scalar class methods**: `Upper`, `Lower`, `Split`, `Map`, `Filter`,
  `Reduce`, etc. — resolved via class method tables, not function lookup.
- **RTL functions**: all ~300 runtime library functions (`Upper()`, `Len()`,
  `ValType()`, `QOut()`, `Str()`, `Val()`, `Date()`, `Time()`, etc.) —
  registered without namespace qualification.

**Rule**: any symbol registered without a dot in its `szName` is globally
accessible. Only dotted (namespace-qualified) symbols require IMPORT.

### 2.3 Name Resolution

Namespace qualification uses the dot (`.`) separator. The dot is currently
invalid in Harbour identifiers, so there is zero collision risk.

**Disambiguation with message-send syntax**:
- `:` (colon) = object message send: `obj:method()` — follows an expression
- `.` (dot) = namespace qualifier: `MyApp.Users.GetUser()` — separates identifiers

These are syntactically unambiguous. The parser distinguishes them during
expression parsing.

**Resolution order for unqualified calls in MODULE files**:
1. Current module's exported symbols
2. Explicitly imported symbols (from IMPORT declarations)
3. Built-in namespace (Section 2.2)
4. Global namespace (all unqualified symbols)
5. Compile-time error (with PersistentAST) or runtime EG_NOFUNC (fallback)

**Resolution for non-MODULE files**: unchanged — flat dynsym lookup.

See [DESIGN.md](DESIGN.md) Sections 2-5 for full symbol table design,
macro compiler integration, and class system interaction.

---

## 3. Affected Files

| File | Lines | Change |
|------|-------|--------|
| `src/compiler/harbour.y` | 3,011 | Add MODULE/IMPORT/EXPORT grammar rules |
| `src/compiler/complex.c` | ~53K | Context-sensitive keyword recognition for MODULE/IMPORT/EXPORT |
| `src/compiler/hbmain.c` | 4,526 | Store declared namespace; emit qualified symbol names |
| `src/vm/dynsym.c` | ~500 | Dotted-name lookup works unchanged; optional namespace registry |
| `src/vm/hvm.c` | 12,572 | Pass namespace context to macro compiler |
| `src/vm/classes.c` | 5,665 | Accept qualified class names in `__CLSNEW`; FRIEND across modules |
| `src/macro/macrolex.c` | ~550 | Accept `.` in identifiers for namespace-qualified names |
| `src/macro/macro.y` | ~500 | No grammar change needed; lexer handles dotted names |
| `src/vm/macro.c` | ~1,800 | Accept namespace context in `HB_MACRO` struct |
| `include/hbvmpub.h` | ~250 | No struct change (dotted names stored in existing `szName`) |
| `include/hbmacro.h` | ~200 | Add `szNamespace` field to `HB_MACRO` struct |
| `src/compiler/genhrb.c` | 171 | Emit declared namespace in `.hrb` v3 format |
| `src/vm/runner.c` | ~880 | Read declared namespace from `.hrb` v3 |

## 4. Dependencies

| Dependency | Status | Notes |
|------------|--------|-------|
| PersistentAST (Phase E) | PLANNING | **Required** — cross-module IMPORT resolution needs persistent AST to verify that imported symbols exist in the target module at compile time |

## 5. Estimated Scope

| Phase | Effort | Description |
|-------|--------|-------------|
| H.1 | 2 weeks | Grammar: MODULE/IMPORT/EXPORT keyword recognition and parsing |
| H.2 | 3 weeks | Symbol table: compiler emits qualified names; dynsym handles dotted names |
| H.3 | 2 weeks | Macro compiler: lexer accepts dots; namespace context in `HB_MACRO`. Minimal change — macro grammar is frozen, only the lexer and symbol resolution are touched |
| H.4 | 3 weeks | Cross-module resolution: IMPORT verification using persistent AST |
| H.5 | 2 weeks | Class system: qualified class names, FRIEND across modules |
| H.6 | 1 week | Testing, `.hbx` format evolution, documentation |
| **Total** | **~13 weeks** | |

## 6. Future Extension: Foreign Function Interface

`IMPORT FOREIGN` is a planned extension of the module syntax for calling
external C libraries directly from PRG without writing C wrapper code:

```harbour
IMPORT FOREIGN "libsqlite3"
   FUNCTION sqlite3_open(cPath AS CSTRING, @pDB AS POINTER) AS INTEGER
   FUNCTION sqlite3_exec(pDB AS POINTER, cSQL AS CSTRING, ...) AS INTEGER
ENDIMPORT
```

This depends on GradualTyping (Phase F) for meaningful `AS` type annotations
and DrydockAPI (Phase A1) for the runtime handle interface. Not scoped as part
of ModuleSystem — it will emerge naturally when the infrastructure is ready.

## 7. Compatibility

See [COMPAT.md](COMPAT.md) for full fracture analysis. Summary:

- 100% backward compatible for files without MODULE declaration
- 99.5% for files with MODULE (intentional encapsulation changes)
- All 7 Compatibility Covenant rules from `vision.md` are satisfied
- MODULE/IMPORT/EXPORT keywords are context-sensitive (Covenant rule 4)

---

[<- Index](../INDEX.md) · [Map](../MAP.md) · [DESIGN](DESIGN.md) · [COMPAT](COMPAT.md) · **BRIEF**
