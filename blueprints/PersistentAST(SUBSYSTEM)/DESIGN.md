# DESIGN -- PersistentAST (SUBSYSTEM)

## 1. Current State

- The compiler currently emits pcode during parsing and FREES expression nodes immediately via `hb_compExprFree()`
- `HB_EXPR` is the expression node type with ~45 variants (`HB_ET_*`)
- Expressions are allocated during parsing, used for pcode emission, then freed
- No AST survives past the current function's compilation

---

## 2. Proposed Changes

### 2.1 Retain AST After Pcode Emission

- Add `PHB_EXPR pBodyAST` field to `HB_HFUNC` struct in `include/hbcompdf.h`
- Remove `hb_compExprFree()` calls in `harbour.y` after pcode emission
- Instead, chain statements via `HB_EXPR::pNext` into `pBodyAST`
- Add `hb_compExprFreeAll()` for bulk cleanup at function finalization

### 2.2 Statement Representation

- Add `HB_ET_STMTLIST` expression type for statement blocks
- IF/FOR/WHILE represented as tree nodes with child branches:
  ```
  HB_ET_IF
    +-- condition: HB_EXPR (expression)
    +-- thenBody: HB_ET_STMTLIST (statement list)
    +-- elseBody: HB_ET_STMTLIST (or NULL)

  HB_ET_FOR
    +-- init: HB_EXPR (assignment)
    +-- end: HB_EXPR (limit)
    +-- step: HB_EXPR (or NULL)
    +-- body: HB_ET_STMTLIST

  HB_ET_WHILE
    +-- condition: HB_EXPR
    +-- body: HB_ET_STMTLIST
  ```

### 2.3 Walker/Visitor Infrastructure

- Generic `hb_compExprWalk(pExpr, pVisitor)` function
- Visitor is a function table (one handler per `HB_ET_*` type)
- Built-in visitors: printer (debug), symbol resolver, type checker (for GradualTyping)

### 2.4 Symbol Resolution Walker

- Phase E.2: Walk the AST and resolve variable references to their declarations
- Each `HB_EXPR` gets `pSymbol` pointer to its declaration (local, static, memvar)
- Multi-file support: symbol table includes imported symbols (for ModuleSystem Phase H)

---

## 3. Memory Impact

- Peak compile-time memory +30-50%
- Build flag `HB_BUILD_AST=no` to disable retention for memory-constrained builds
- No runtime memory impact -- AST is compiler-only

---

## 4. Files Modified

- `include/hbcompdf.h` -- Add `pBodyAST` to `HB_HFUNC`
- `src/compiler/harbour.y` -- Stop freeing expression nodes after pcode emit
- `src/compiler/hbexpr.c` -- Walker infrastructure, printer, symbol resolver (~2000 LOC)
- `src/compiler/hbcomp.c` -- `hb_compExprFreeAll()` cleanup

---

## 5. Compatibility

100% source and binary. Pcode output identical. AST is internal compiler structure.

---

[<- Index](../INDEX.md) . [Map](../MAP.md) . [BRIEF](BRIEF.md) . **DESIGN**
