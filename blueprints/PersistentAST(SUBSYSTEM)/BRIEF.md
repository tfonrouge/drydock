# BRIEF -- PersistentAST (SUBSYSTEM)

## Identity

| Field | Value |
|-------|-------|
| **Name** | PersistentAST |
| **Mode** | SUBSYSTEM |
| **Tier** | 2 — Build a Real Compiler |
| **Phase** | E |
| **Component** | Compiler — `src/compiler/` |
| **Status** | PLANNING |

---

## 1. Motivation

The Harbour compiler is **single-pass**: it parses source code, builds temporary
expression trees (`HB_EXPR` in `hbcompdf.h`), emits pcode immediately, and
frees the expression nodes. By the time parsing finishes, no representation of
the program remains except the linear pcode byte stream.

**This is the single most important architectural limitation in the compiler.**

Without a persistent AST:

- **No real optimizer** — `hbopt.c` can only do peephole pattern matching on
  the pcode byte stream (push/pop elimination, offset narrowing). There is no
  data structure to perform constant propagation, dead store elimination,
  common subexpression elimination, loop invariant code motion, or inlining.
- **No type checking** — the `AS` annotations parse and store `ValType` hints
  in `HB_EXPR` nodes, but these nodes are freed before any validation can
  occur. GradualTyping (Phase F) cannot be built without a tree to analyze.
- **No LSP server** — go-to-definition, hover information, and diagnostics
  require a persistent representation of the program structure. Without it,
  every IDE query would require a full reparse.
- **No control-flow graph** — CFG construction requires a tree or IR to
  analyze. The linear pcode stream doesn't preserve the structure needed
  for dominance analysis, loop detection, or SSA construction.
- **No cross-function analysis** — function bodies are compiled and forgotten
  individually. No interprocedural optimization is possible.

Every modern compiler improvement in Tier 2 depends on this change.

---

## 2. Current State

### HB_EXPR Structure (hbcompdf.h:347-437)

```c
typedef struct HB_EXPR_ {
   HB_EXPRTYPE   ExprType;     /* 45 expression types */
   HB_USHORT     ValType;      /* runtime type hint */
   union {
      struct { HB_BOOL value; }                  asLogical;
      struct { int value; HB_MAXINT lVal; }      asNum;
      struct { char * string; HB_SIZE length; }  asString;
      struct { char * szName; int iScope; ... }  asSymbol;
      struct { struct HB_EXPR_ * pLeft;
               struct HB_EXPR_ * pRight; }       asOperator;
      struct { struct HB_EXPR_ * pFunName;
               struct HB_EXPR_ * pParms; }       asFunCall;
      struct { struct HB_EXPR_ * pObject;
               char * szMessage;
               struct HB_EXPR_ * pParms; }       asMessage;
      /* ... 15+ more union variants ... */
   } value;
   struct HB_EXPR_ * pNext;    /* linked list chaining */
} HB_EXPR;
```

### Lifecycle (current)

```
parse rule fires (harbour.y)
  → hb_compExprNew*() allocates HB_EXPR node
  → operator/function nodes link children
  → hb_compExprGenPush() / hb_compExprGenPop() emit pcode
  → hb_compExprFree() deallocates node and children
```

The entire tree lives only during the reduction of a single grammar rule.
Cross-statement analysis is impossible.

### Function Structure (HB_HFUNC in hbcompdf.h)

```c
typedef struct _HB_HFUNC {
   char *         szName;
   HB_BYTE *     pCode;        /* pcode byte buffer — the only surviving output */
   HB_SIZE        nPCodeSize;
   HB_SIZE        nPCodePos;
   /* locals, statics, parameters — name tables only, no type info */
   PHB_HVAR       pLocals;
   PHB_HVAR       pStatics;
   /* loop/if/switch nesting trackers */
   /* ... */
} HB_HFUNC;
```

After compilation, only `pCode` (the byte stream) survives. Variable names are
kept for debug info but their types and usage patterns are lost.

---

## 3. Proposed Change

### 3.1 Retain the AST

Stop freeing expression trees after pcode emission. Instead, attach the tree to
the owning `HB_HFUNC`:

```c
typedef struct _HB_HFUNC {
   /* ... existing fields ... */
   PHB_EXPR       pBodyAST;     /* NEW: root of the statement list for this function */
   PHB_HVAR       pLocals;      /* existing: now also carries resolved type info */
} HB_HFUNC;
```

The parse-then-emit cycle becomes:

```
parse rule fires
  → allocate HB_EXPR nodes (unchanged)
  → link into function's statement list (NEW — append to pBodyAST)
  → emit pcode (unchanged — for backward compatibility)
  → DO NOT free the tree
```

### 3.2 Statement List

Add a new expression type `HB_ET_STMTLIST` (or reuse `HB_ET_NONE` as
sentinel) to chain statements in sequence:

```c
/* A function body is a linked list of statement expressions */
pFunc->pBodyAST = pFirstStmt;
pFirstStmt->pNext = pSecondStmt;
/* ... */
```

This is already how `HB_EXPR::pNext` works for expression lists — extend it
to statement scope.

### 3.3 Phased Adoption

**Phase E.1 — Retain trees, don't use them yet (2 weeks)**

- Remove `hb_compExprFree()` calls after codegen
- Attach statement trees to `HB_HFUNC::pBodyAST`
- Add `hb_compExprFreeAll( pFunc )` called at function finalization
- Verify: `make && hbtest` passes with identical output
- Memory: will increase peak usage. Add `HB_BUILD_AST=no` compile flag to
  disable retention for memory-constrained builds.

**Phase E.2 — AST walker infrastructure (2 weeks)**

- Implement visitor pattern: `hb_compExprWalk( pExpr, pCallback, pUserData )`
- Build tree-printer for debugging (`-ast` compiler flag)
- Build symbol-resolution walker: resolve variable references to their
  `HB_HVAR` declarations
- Build type-annotation collector: gather `AS` type info into a per-function
  type map

**Phase E.3 — CFG construction (2 weeks)**

- Build basic blocks from the AST (split at branches, loops, calls)
- Construct control-flow graph edges (fallthrough, jump, branch)
- Compute dominator tree and loop nest tree
- This unlocks: constant propagation, dead code elimination, loop analysis

---

## 4. Affected Files

| File | Lines | Change |
|------|-------|--------|
| `include/hbcompdf.h` | ~500 | Add `pBodyAST` to `HB_HFUNC`; add `HB_ET_STMTLIST` type |
| `src/compiler/hbcomp.c` | ~300 | Add `hb_compExprFreeAll()` |
| `src/compiler/harbour.y` | 3,011 | Remove `hb_compExprFree()` calls; attach trees to function |
| `src/compiler/hbexpr.c` | ~2,000 | New: AST walker, tree printer, symbol resolver |
| `src/compiler/hbmain.c` | 4,526 | Call `hb_compExprFreeAll()` at function finalization |
| `src/compiler/genc.c` | 2,771 | No change (still emits from pcode, not AST) |

## 5. Affected Structs

| Struct | File | Change |
|--------|------|--------|
| `HB_HFUNC` | `hbcompdf.h` | Add `PHB_EXPR pBodyAST` field |
| `HB_EXPR` | `hbcompdf.h` | No structural change — just retained longer |

## 6. Compatibility Stance

**Target: 100% source and binary compatibility.**

- Compiler output (pcode) is identical — AST retention is internal
- No new syntax, no new opcodes, no grammar changes
- The `HB_BUILD_AST=no` flag allows disabling for memory-constrained platforms
- No change to compiled .hrb or .c output

## 7. Performance Stance

**Compile-time memory increase. No runtime change.**

- Peak compiler memory will increase by the size of retained ASTs — estimated
  30-50% for large files. This is acceptable for a compiler (not a runtime
  constraint).
- Compilation speed: no regression expected — the allocation already happens;
  we just skip the free. May actually be slightly faster (fewer `hb_xfree` calls).
- Runtime: zero change — pcode output is identical.

## 8. Dependencies

| Dependency | Status | Notes |
|------------|--------|-------|
| *(none)* | — | PersistentAST is a root workstream for Tier 2 |

**Blocks**:
- GradualTyping (Phase F) — needs AST for type analysis
- Optimizer (Phase G) — needs AST/CFG for real optimizations
- LSPServer (Phase I) — needs AST for IDE queries
- ModuleSystem (Phase H) — benefits from cross-function symbol resolution

## 9. Risks

| Risk | Severity | Mitigation |
|------|----------|------------|
| Memory bloat on large files | Medium | `HB_BUILD_AST=no` compile flag; lazy AST (retain only current function) |
| AST/pcode divergence | High | In Phase E.1, verify AST→pcode roundtrip matches direct pcode |
| Macro compiler (`src/macro/`) | Medium | Macro compiler has its own expression system — leave it single-pass initially |
| Incremental adoption complexity | Low | Phases are strictly additive — each phase adds capability without changing existing output |

## 10. Estimated Scope

| Phase | Effort | Can Ship Independently |
|-------|--------|----------------------|
| E.1: Retain trees | 2 weeks | Yes (no behavior change) |
| E.2: Walker infrastructure | 2 weeks | Yes (adds `-ast` flag) |
| E.3: CFG construction | 2 weeks | Yes (adds `-cfg` flag) |
| **Total** | **6 weeks** | |

---

[<- Index](../INDEX.md) · [Map](../MAP.md) · **BRIEF**
