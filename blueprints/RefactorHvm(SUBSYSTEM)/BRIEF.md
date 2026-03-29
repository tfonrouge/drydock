# BRIEF -- RefactorHvm (SUBSYSTEM)

## Identity

| Field | Value |
|-------|-------|
| **Name** | RefactorHvm |
| **Mode** | SUBSYSTEM |
| **Component** | VM — `src/vm/hvm.c`, `include/hbxvm.h` |
| **Status** | STABLE |
| **Supersedes** | HvmOperatorDedup(PATCH) |

---

## 1. Motivation

`src/vm/hvm.c` is the execution engine of the Harbour VM. At **12,572 lines**
in a single file, it contains:

- The pcode interpreter loop (187 opcodes)
- All operator implementations (21 primary functions)
- 110 C-level API wrappers (`hb_xvm*`)
- Stack, frame, and statics management
- Sequence/recovery exception handling
- Debugger hooks and profiler instrumentation
- Reference callback vtables
- Module initialization

It is the most critical file in the codebase — every Harbour program passes
through it on every operation. Its current state has three classes of problems
that compound each other: **structural duplication** that creates a maintenance
multiplier, **dead code** that inflates the surface area, and **missing
performance primitives** that leave optimization on the table.

These problems are not academic. The ScalarClasses workstream proposes
routing operator dispatch through the OO class system. With the current
state of hvm.c, that change would need to be replicated across ~15 function
copies per operator — a guaranteed source of divergence bugs. RefactorHvm
creates the clean foundation that ScalarClasses (and future workstreams)
can build on safely.

---

## 2. Analysis — The Three Layers

### 2.1 Layer 1: Primary Operator Functions (hb_vm*)

**118 static functions**, including 21 operator functions that contain the
real type-cascade logic. These are the source of truth for operator behavior:

| Category | Functions | Lines | Cascade Pattern |
|----------|-----------|-------|-----------------|
| Binary arithmetic | `hb_vmPlus`, `hb_vmMinus`, `hb_vmMult`, `hb_vmDivide`, `hb_vmModulus`, `hb_vmPower` | ~397 | NUMINT→NUMERIC→[STRING→DATETIME]→objOperatorCall→error |
| Unary arithmetic | `hb_vmInc`, `hb_vmDec` | ~128 | INT→LONG→DOUBLE→DATETIME→objOperatorCall→error |
| Negation | `hb_vmNegate` | ~71 | INT→LONG→DOUBLE→DATETIME→LOGICAL→STRING→objOperatorCall |
| Equality | `hb_vmEqual`, `hb_vmExactlyEqual`, `hb_vmNotEqual` | ~330 | NIL→STRING→NUMINT→NUMERIC→DATETIME→LOGICAL→POINTER→[HASH→BLOCK→SYMBOL→ARRAY]→objOperatorCall→error |
| Ordering | `hb_vmLess`, `hb_vmLessEqual`, `hb_vmGreater`, `hb_vmGreaterEqual` | ~276 | STRING→NUMINT→NUMERIC→DATETIME→LOGICAL→objOperatorCall→error |
| Logical | `hb_vmNot`, `hb_vmAnd`, `hb_vmOr` | ~89 | LOGICAL→objOperatorCall→error |
| Containment | `hb_vmInstring` | ~48 | STRING→HASH→objOperatorCall(INCLUDE)→objOperatorCall(INSTRING)→error |
| Optimized add | `hb_vmAddInt` | ~59 | NUMINT→DOUBLE→DATETIME→objOperatorCall→error |

Every operator terminates with `hb_objOperatorCall()` as fallback, which
already resolves scalar classes via `hb_objGetClassH()`. This is the hook
point for ScalarClasses.

### 2.2 Layer 2: C-Level API Wrappers (hb_xvm*)

**110 `HB_EXPORT` functions** declared in `include/hbxvm.h`, exported in
`src/harbour.def`. Used by the C code generator (`src/compiler/gencc.c`)
when compiling Harbour to C instead of pcode.

Most are thin wrappers that delegate to Layer 1:

```c
/* hvm.c:11020 — clean delegation, no duplication */
HB_BOOL hb_xvmPlus( void )
{
   hb_vmPlus( hb_stackItemFromTop( -2 ),
              hb_stackItemFromTop( -2 ),
              hb_stackItemFromTop( -1 ) );
   hb_stackPop();
   HB_XVM_RETURN
}
```

**But 15 functions have their own independent type cascades:**

| Group | Functions | Lines | Callers in Codebase |
|-------|-----------|-------|---------------------|
| Comparison-Int (12) | `hb_xvmEqualInt`, `hb_xvmEqualIntIs`, `hb_xvmNotEqualInt`, `hb_xvmNotEqualIntIs`, `hb_xvmLessThenInt`, `hb_xvmLessThenIntIs`, `hb_xvmLessEqualThenInt`, `hb_xvmLessEqualThenIntIs`, `hb_xvmGreaterThenInt`, `hb_xvmGreaterThenIntIs`, `hb_xvmGreaterEqualThenInt`, `hb_xvmGreaterEqualThenIntIs` | ~680 | **Zero** |
| Arithmetic-ByInt (3) | `hb_xvmMultByInt`, `hb_xvmDivideByInt`, `hb_xvmModulusByInt` | ~140 | `gencc.c` (live) |

The 12 comparison-Int functions are **dead code** — declared, exported, never
called anywhere in the codebase (not by `gencc.c`, not by `contrib/`, not by
`tests/`). They contain full type cascades with their own `hb_objHasOperator`
/ `hb_objOperatorCall` paths, adding 680 lines of unmaintained operator logic.

### 2.3 Layer 3: Opcode Dispatch (hb_vmExecute)

**187 `HB_P_*` cases** in a single `switch` statement (lines 1387-2964).
This layer is clean — it delegates to Layer 1 without duplicating cascades:

- `HB_P_PLUS` → `hb_vmPlus()`
- `HB_P_PLUSEQ` / `HB_P_PLUSEQPOP` → `hb_vmPlus()` with stack management
- `HB_P_LOCALNEARADDINT` → `hb_vmAddInt()` (fused opcode)
- `HB_P_SEND` / `HB_P_SENDSHORT` → `hb_vmSend()`

Compound assignment opcodes (`*EQ`, `*EQPOP`) are mechanical stack glue
around the primary functions. Fused opcodes (`LOCALNEARADDINT`, `LOCALINC`,
`LOCALDEC`, `LOCALINCPUSH`, `LOCALADDINT`) operate directly on local
variables without intermediate stack pushes — a well-designed optimization.

**No changes needed in Layer 3.** The opcode dispatch is correct and clean.

---

## 3. Criticism — Specific Problems

### 3.1 Operator Cascade Duplication (Structural)

**The four ordering comparisons are copy-paste clones.**

`hb_vmLess`, `hb_vmLessEqual`, `hb_vmGreater`, `hb_vmGreaterEqual` — 4 × 69
lines = 276 lines where ~210 are identical. The only differences:

| Function | C op | Timestamp expr | Logical expr | OO const | Error |
|----------|------|----------------|--------------|----------|-------|
| Less | `<` | `j1<j2 \|\| (j1==j2 && t1<t2)` | `!a && b` | `HB_OO_OP_LESS` | 1073 |
| LessEqual | `<=` | `j1<j2 \|\| (j1==j2 && t1<=t2)` | `!a \|\| b` | `HB_OO_OP_LESSEQUAL` | 1074 |
| Greater | `>` | `j1>j2 \|\| (j1==j2 && t1>t2)` | `a && !b` | `HB_OO_OP_GREATER` | 1075 |
| GreaterEqual | `>=` | `j1>j2 \|\| (j1==j2 && t1>=t2)` | `a \|\| !b` | `HB_OO_OP_GREATEREQUAL` | 1076 |

A single parameterized function eliminates 3 copies. Every future change to
comparison behavior (e.g., routing through scalar classes) becomes one edit
instead of four.

**Inc/Dec are mirror images.**

`hb_vmInc` (64 lines) and `hb_vmDec` (64 lines) differ only in `+1` vs `-1`
and overflow vs underflow bounds. A direction parameter collapses both into
one ~70-line function.

**Equal/NotEqual are negation mirrors.**

`hb_vmEqual` (99 lines) and `hb_vmNotEqual` (101 lines) differ only in
negating each comparison result. A `fNegate` parameter would save ~80 lines,
though the NIL handling has a subtle difference that requires care.

**Maintenance multiplier**: Any change to operator behavior (like ScalarClasses
Phase 3) must currently be applied to N copies. N ranges from 2 (Inc/Dec) to
4 (ordering) to 15 (if counting xvm*Int variants). This is the primary risk
for ScalarClasses.

### 3.2 xvm Comparison-Int Functions (680 Lines — NOT Dead Code)

The 12 `hb_xvm*ThenInt*` / `hb_xvm*IntIs` / `hb_xvmEqualInt*` /
`hb_xvmNotEqualInt*` functions are:

- Declared in `include/hbxvm.h:237-248`
- Exported in `src/harbour.def:3672-3698`
- Defined in `src/vm/hvm.c:10275-10997`
- **Emitted by `gencc.c`** in the `-gc2` C code generation path. Phase 0
  attempted removal (commit `0ec787c`, 2026-03-27) and was reverted
  (`6f6811b`) because these functions ARE called from generated C code.
  The initial "zero callers" analysis only searched source files, not
  generated output. A proper analysis of `gencc.c` confirmed all 12
  functions are emitted via `gencc_checkJumpCondAhead()` (lines 195-202).

They contain independent type cascades with their own `hb_objHasOperator` /
`hb_objOperatorCall` paths — 680 lines of operator logic that no **source**
code path reaches. They were presumably designed for a peephole optimization
in the C code generator (`gencc.c`) — the compiler does emit
`hb_xvmMultByInt` etc. for arithmetic, but the comparison variants need
verification.

Additionally, they contain a typo in their names: "Then" instead of "Than"
(`hb_xvmLessThenInt`), which would be an ABI break to fix if they had callers.

### 3.3 Missing Performance Primitives

**No branch prediction hints.** The entire 12,572-line file contains zero
`__builtin_expect()`, `likely()`, or `unlikely()` macros. In a VM interpreter
where type checks dominate the hot path, this is a significant missed
opportunity. Modern interpreters (Lua, CPython, V8) rely heavily on branch
hints to guide CPU speculation.

Examples of high-value hint sites:

```c
/* Hot: integer arithmetic is the common case */
if( HB_IS_NUMINT( pItem1 ) && HB_IS_NUMINT( pItem2 ) )  /* likely */

/* Cold: operator overload is the rare fallback */
else if( ! hb_objOperatorCall( ... ) )  /* unlikely */

/* Hot: most items are not byref */
if( HB_IS_BYREF( pLocal ) )  /* unlikely */

/* Hot: profiler is usually disabled */
if( hb_bProfiler )  /* unlikely in production */
```

**No explicit jump table hint for the main switch.** The 187-case switch in
`hb_vmExecute` relies on compiler optimization to produce a jump table.
GCC/Clang typically do this for dense ranges, but the `HB_P_*` values may
not be dense enough for optimal codegen. A computed-goto dispatch (as used
by CPython and Lua 5.4) would give a measurable improvement, but is a larger
change best left to a dedicated performance workstream.

**Profiler adds per-opcode overhead when enabled.** The profiler calls
`clock()` on every opcode iteration (`hvm.c:1344-1354`). When
`HB_NO_PROFILER` is not defined, this adds two function calls and two array
updates per opcode, which impacts cache locality and pipeline throughput.
The flag check (`hb_bProfiler`) is at least a branch (potentially
mispredicted) on every iteration.

### 3.4 Mixed Abstraction Levels

The file blends seven distinct concerns:

| Concern | Lines | % |
|---------|-------|---|
| Opcode dispatch (hb_vmExecute switch) | ~1,600 | 13% |
| Operator implementations (hb_vm* type cascades) | ~1,400 | 11% |
| C-level API wrappers (hb_xvm*) | ~2,800 | 22% |
| Stack/frame management | ~800 | 6% |
| Reference callback vtables | ~450 | 4% |
| Sequence/recovery/ALWAYS exception handling | ~400 | 3% |
| Everything else (init, debug, module, push/pop, DB, macro, enum, array) | ~5,100 | 41% |

The operator implementations and the xvm wrappers together account for
~4,200 lines (33%) — a third of the file devoted to operators. Of those,
~1,000 lines are duplication or dead code.

Separating the file into translation units would harm cross-function
inlining by the C compiler (unless link-time optimization is used). But the
organizational cost is real: understanding operator behavior requires
navigating a 12K-line file with no section markers beyond `/* --- */`
comments.

### 3.5 Surprising Semantics

**String "subtraction" in hb_vmMinus** (`hvm.c:3459-3491`): when both
operands are strings, `hb_vmMinus` strips trailing spaces from the left
operand, then appends the right operand. This is a Clipper compatibility
feature buried in what reads like a numeric subtraction function, with zero
documentation in the code. The comment `/* NOTE: ... */` that exists for
date subtraction Clipper compatibility (`hvm.c:3352`) is absent for this
equally surprising behavior.

**`#if 0` dead code in hb_vmEqual** (`hvm.c:4045-4053`): hash equality
comparison is disabled with no comment explaining why. It either should be
enabled (it compares hash references, which is well-defined) or deleted.
Leaving `#if 0` blocks in a hot function is confusing.

### 3.6 Error Pattern — Consistent But Verbose

54 `hb_errRT_BASE_Subst` call sites follow the same template:

```c
PHB_ITEM pSubst = hb_errRT_BASE_Subst( EG_ARG, 1081, NULL, "+", 2, pItem1, pItem2 );
if( pSubst )
{
   hb_stackPop();
   hb_itemMove( pResult, pSubst );
   hb_itemRelease( pSubst );
}
```

The only varying parts are the error code, error number, operator string,
argument count, and stack cleanup. A helper macro could compress this 6-line
pattern into 1 line, saving ~270 lines and making the cascade structure more
visible. But this is cosmetic — the pattern is consistent and correct.

---

## 4. Suggestions — Phased Approach

### Phase 0: Dead Code Removal (1 day)

| ID | Change | Lines Removed | Risk |
|----|--------|---------------|------|
| R0a | Delete 12 dead `hb_xvm*ThenInt*` / `*IntIs` functions from hvm.c | ~680 | None — zero callers |
| R0b | Remove their declarations from `include/hbxvm.h` | ~12 | None — zero consumers |
| R0c | Remove their exports from `src/harbour.def` | ~12 | None — zero consumers |
| R0d | Remove `#if 0` hash equality block from `hb_vmEqual` | ~8 | None — dead code |
| | **Subtotal** | **~712** | |

**Verification**: `make clean && make && bin/linux/gcc/hbtest`. Zero behavior
change. This is the safest possible first commit — removing code that no
execution path reaches.

### Phase 1: Operator Deduplication (2-3 days)

| ID | Change | Lines Saved | Risk |
|----|--------|-------------|------|
| R1a | Factor 4 ordering comparisons into 1 parameterized `hb_vmCompare()` | ~210 | Low — mechanical |
| R1b | Factor Inc/Dec into 1 `hb_vmIncDec()` with direction parameter | ~60 | Low — trivial mirror |
| R1c | Factor 3 live `hb_xvm*ByInt` into 1 parameterized function | ~80 | Low — same cascade, same stack contract |
| R1d | Add Clipper-compat comment to string subtraction in `hb_vmMinus` | 0 | None |
| | **Subtotal** | **~350** | |

**Verification**: `hbtest -all` with identical results. Each refactoring is
a separate commit.

### Phase 2: Equal/NotEqual Consolidation (1 day, optional)

| ID | Change | Lines Saved | Risk |
|----|--------|-------------|------|
| R2a | Factor Equal/NotEqual into 1 function with negate flag | ~80 | Medium — NIL handling subtlety |

The NIL handling differs:
- Equal: `NIL == NIL` → true; `NIL == x` → false; `x == NIL` → false
- NotEqual: `NIL != NIL` → false; `NIL != x` → true; `x != NIL` → true

This is just negation, so a `fNegate` flag works. But the stack cleanup
differs slightly (`hb_stackDec` vs `hb_stackPop` paths), requiring care.

### Phase 3: Performance Annotations (1-2 days, independent)

| ID | Change | Lines Added | Risk |
|----|--------|-------------|------|
| R3a | Add `HB_LIKELY`/`HB_UNLIKELY` macros to `include/hbdefs.h` | ~10 | None |
| R3b | Annotate operator fast paths with `HB_LIKELY` | ~40 | None — hint only |
| R3c | Annotate error/fallback paths with `HB_UNLIKELY` | ~30 | None — hint only |
| R3d | Annotate profiler/debug guards with `HB_UNLIKELY` | ~10 | None — hint only |

Macro definition:
```c
#if defined(__GNUC__) || defined(__clang__)
#  define HB_LIKELY(x)   __builtin_expect(!!(x), 1)
#  define HB_UNLIKELY(x) __builtin_expect(!!(x), 0)
#else
#  define HB_LIKELY(x)   (x)
#  define HB_UNLIKELY(x) (x)
#endif
```

This is zero-risk (compiles to nothing on non-GCC/Clang) and benefits every
hot path in the VM. Should be benchmarked before and after.

### Phase 4: Error Pattern Macro (optional, cosmetic)

| ID | Change | Lines Saved | Risk |
|----|--------|-------------|------|
| R4a | Create `HB_VM_OPERATOR_ERROR` macro for the 6-line Subst pattern | ~220 | Low — macro expansion |

```c
#define HB_VM_OPERATOR_ERROR( op, errCode, opStr, nArgs, ... ) \
   do { \
      PHB_ITEM _pSubst = hb_errRT_BASE_Subst( EG_ARG, errCode, NULL, opStr, nArgs, __VA_ARGS__ ); \
      if( _pSubst ) { hb_stackPop(); hb_itemMove( pResult, _pSubst ); hb_itemRelease( _pSubst ); } \
   } while( 0 )
```

This makes operator functions ~40% shorter and the cascade structure
immediately visible. Purely cosmetic — no behavior change.

### Explicitly Rejected

| Change | Why Not |
|--------|---------|
| Split hvm.c into multiple files | Breaks cross-function inlining; the C compiler needs one TU to optimize the hot loop. Could revisit with LTO. |
| Computed-goto dispatch | Significant change with portability concerns (MSVC doesn't support it). Deserves its own blueprint if pursued. |
| Factor Plus/Minus | Genuine semantic differences (string trim+concat, date difference vs sum) make a template forced and less readable. |
| Type dispatch tables | That IS ScalarClasses Phase 3 — routing through `hb_objOperatorCall` replaces cascades. Don't pre-build tables that the class system makes redundant. |
| Rename "Then" to "Than" | Moot if we delete the dead functions (R0a). If kept, ABI break for zero benefit. |

---

## 5. What This Unlocks

### For ScalarClasses

- **Phase 0 + Phase 1** reduce the number of operator cascade copies from
  ~33 to ~14. ScalarClasses Phase 3 (simplifying cascades to fast-path +
  scalar dispatch) becomes safer: fewer places to update, lower divergence risk.
- Ordering comparison consolidation (R1a) means ScalarClasses only needs to
  wire scalar dispatch into ONE comparison function instead of four.

### For Future Performance Work

- **Phase 3** branch hints give a measurable baseline and establish the
  `HB_LIKELY`/`HB_UNLIKELY` convention for the entire codebase.
- Clean operator functions make it possible to benchmark individual type paths
  and identify hot/cold branches quantitatively.

### For Maintainability

- **~1,060 lines removed** (Phases 0-1) from the most critical file in the
  codebase, with zero behavior change.
- Every operator change becomes 1 edit instead of 2-4.
- The error macro (Phase 4) makes cascade structure scannable at a glance.

---

## 6. Affected Files

| File | Lines | Change |
|------|-------|--------|
| `src/vm/hvm.c` | 12,572 | Phases 0-4: delete dead code, factor duplicated functions, add macros |
| `include/hbxvm.h` | ~250 | Phase 0: remove dead declarations |
| `src/harbour.def` | ~3,800 | Phase 0: remove dead exports |
| `include/hbdefs.h` | ~600 | Phase 3: add `HB_LIKELY`/`HB_UNLIKELY` macros |

## 7. Affected Structs

None. This is a pure refactoring of function bodies and dead code removal.
No data structure changes. No ABI changes for live symbols.

## 8. Compatibility Stance

**Target: 100% source and ABI compatibility for all live symbols.**

- No behavior change for any operator.
- No change to any public function signature that has callers.
- Dead symbols removed from `hbxvm.h` and `harbour.def` — these have zero
  callers in the entire codebase, zero callers in `contrib/`, and were never
  emitted by any code generator. External code theoretically could reference
  them by name, but practically nobody does.
- The `HB_LIKELY`/`HB_UNLIKELY` macros compile to identity on non-GCC/Clang.

## 9. Performance Stance

**Must not regress on any path. Phase 3 should improve hot paths.**

- Phases 0-2 are pure refactoring: same logic, same codegen.
- Phase 3 (branch hints) should improve branch prediction on type checks.
  Benchmark before and after on tight arithmetic loop.
- Factored functions (R1a, R1b) pass the discriminator as a parameter, which
  the compiler can constant-propagate when called from wrapper functions.

## 10. Dependencies

| Dependency | Status | Notes |
|------------|--------|-------|
| *(none)* | -- | RefactorHvm is a root workstream with no prerequisites |

**Blocks**: ScalarClasses(SUBSYSTEM) Phase 3 depends on RefactorHvm
Phases 0-1 to reduce cascade copies.

## 11. Estimated Scope

| Phase | Effort | Can Ship Independently |
|-------|--------|----------------------|
| Phase 0: Dead code removal | 1 day | Yes |
| Phase 1: Operator dedup | 2-3 days | Yes (after Phase 0) |
| Phase 2: Equal/NotEqual | 1 day | Yes (after Phase 1) |
| Phase 3: Branch hints | 1-2 days | Yes (independent) |
| Phase 4: Error macro | 0.5 day | Yes (independent) |
| **Total** | **5-7 days** | |

Phases 0-1 are the priority. Phases 2-4 are optional improvements that can
be deferred or done in parallel with ScalarClasses.

---

[<- Index](../INDEX.md) · [Map](../MAP.md) · **BRIEF** · [DESIGN](DESIGN.md) · [ARCH](ARCHITECTURE.md) · [API](C_API.md) · [COMPAT](COMPAT.md) · [PLAN](IMPLEMENTATION_PLAN.md) · [TESTS](TEST_PLAN.md) · [MATRIX](TRACEABILITY.md) · [AUDIT](AUDIT.md)
