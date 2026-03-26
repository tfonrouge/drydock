# Harbour Compiler — Deep Analysis & Modernization Assessment

**Date**: 2026-03-26
**Context**: Analysis of the Harbour compiler fork under the Drydock modernization initiative.

---

## 1. What Harbour Is Today

A **production-grade legacy compiler** from the Clipper/xBase lineage. It works,
ships real software, and supports 20+ platforms. But architecturally it is frozen
circa 2005. This document catalogues what is wrong, why it matters, and proposes
a concrete path to make Harbour a modern compiler — without losing what makes it
valuable.

---

## 2. Critical Deficiencies

### 2.1 No Real Type System

The `AS` annotations in the grammar (`harbour.y`) parse but do **nothing**. There
is no type checking, no type inference, no flow analysis. Every value is an
`HB_ITEM` tagged union resolved at runtime. Consequences:

- No compile-time error catching for type mismatches
- No optimization based on known types (can't elide boxing, can't specialize
  arithmetic)
- No IDE tooling (autocomplete, refactoring) without runtime speculation
- 45 expression types in the AST (`HB_EXPRTYPE`) carry `ValType` hints that
  are stored but never validated

### 2.2 No Intermediate Representation

The compiler is **single-pass**: parse → emit pcode → done. Expression trees
(`HB_EXPR` in `hbcompdf.h`) are built during parsing and immediately freed after
code generation. There is no persistent AST, no SSA form, no control-flow graph.

Consequences:

- **Optimizer is trivial** — `hbopt.c` (1,746 lines) does peephole
  pattern-matching on a linear byte stream: push/pop elimination, variable
  offset narrowing, that's it
- **Dead code elimination** (`hbdead.c`, 609 lines) only removes syntactically
  unreachable code after unconditional jumps — fills with NOOPs, doesn't
  actually shrink output
- No constant propagation, no dead store elimination, no loop invariant code
  motion, no function inlining, no common subexpression elimination
- No ability to add modern analyses without rewriting the frontend
- Error diagnostics are basic: line number + module name, no source snippets,
  no suggestions, no recovery past the first major parse error

### 2.3 Single-Threaded Execution Despite MT Support

The VM has a **Global VM Lock** (`HB_VM_LOCK()`). Only one thread executes
Harbour pcode at a time. Thread switching requires cooperative yield points
checked every 65,536 opcodes (`hvm.c:1360`). `hb_vmSuspendThreads()` is
cooperative stop-the-world. This is Python's GIL problem:

- Multiple threads provide zero speedup on multi-core hardware
- No preemption — threads can starve each other
- All memory allocation contends on the global lock
- Spinlock contention (`HB_SPINLOCK_T` in `garbage.c:68-74`) with busy-waiting

### 2.4 Stop-the-World Mark-and-Sweep GC

`garbage.c` (814 lines) implements a non-generational, non-incremental,
non-concurrent collector:

- **Every collection pauses all threads** via `hb_vmSuspendThreads()`
  (`garbage.c:581`) and walks the entire heap
- **No write barriers** — incremental collection cannot be retrofitted without
  touching every pointer store in the VM
- **No generational optimization** — all objects treated equally, even though
  most allocations die young
- **Reference cycles** detected after cleanup, not prevented — can leak memory
  if destructors create new references (`garbage.c:295-303`)
- **O(n) complexity** where n = total heap objects, triggered by allocation
  count threshold (`HB_GC_AUTO`)

### 2.5 Monolithic Codebase

| File | Lines | Problem |
|------|-------|---------|
| `src/vm/hvm.c` | 12,572 | 181-case switch, 64 operator cascades, 680 lines dead code, 7 mixed concerns |
| `src/pp/ppcore.c` | ~215K | Entire preprocessor in one file — tokenization, pattern matching, code generation |
| `utils/hbmk2/hbmk2.prg` | 16,905 | Build tool with zero modularization or tests |
| `src/vm/classes.c` | 5,665 | OO system mixed with dispatch tables, scoping, and delegation |
| `src/compiler/complex.c` | ~53K | Lexer with limited context awareness |

These aren't style issues — they make every change high-risk and every analysis
slow. `hvm.c` alone blends opcode dispatch (13%), operator implementations (11%),
C-level API wrappers (22%), stack management (6%), exception handling (3%),
reference vtables (4%), and everything else (41%).

---

## 3. Structural Weaknesses

### 3.1 Two Disconnected Type Hierarchies

The VM (`hvm.c`) resolves types via if/else cascades:
`int → numeric → string → date → object (last resort)`.

The OO system (`classes.c`) has proper method dispatch with hash tables, scoping,
multiple inheritance, and 30 overloadable operators.

**Scalars never benefit from the OO system.** 12 scalar wrapper classes exist in
`src/rtl/tscalar.prg` (written 2004-2007) but are disconnected from `hvm.c` —
`nOpFlags == 0` for all scalar classes, so `hb_objHasOperator()` always returns
`HB_FALSE`.

### 3.2 Pcode Is a Dead End for Performance

181 opcodes, switch-dispatched (not computed goto). Pure stack machine — no
register allocation. The pcode is generated, embedded as C byte arrays, compiled
by GCC, and interpreted at runtime. You pay the cost of C compilation **and** the
cost of interpretation with none of the benefits of either:

- Not fast enough to skip JIT (unlike LuaJIT or V8)
- Not static enough to optimize at C compile time (GCC sees opaque byte arrays)
- No branch prediction hints (`__builtin_expect`) anywhere in the 12K-line
  dispatch loop
- Method dispatch requires hash table lookup on every message send — no inline
  caching

### 3.3 No Module System

Files are compilation units. There are no namespaces, no explicit imports/exports,
no visibility controls between modules. Symbol resolution is global and runtime
(dynamic symbol table with dichotomic search at startup). Name collisions are
resolved by load order.

### 3.4 Preprocessor: Powerful But Archaic

`#command`/`#translate` pattern matching is Harbour's killer feature for DSLs —
but it operates on tokens with no semantic awareness, cannot do compile-time
evaluation (`#define X (100 * 2)` doesn't work), and lives in a 215K monolith
that's nearly impossible to extend. No meta-macros, no AST-level transforms.

### 3.5 No Tooling Ecosystem

- No LSP server — no go-to-definition, no hover types, no autocomplete
- No DAP debugger — TUI-only, no IDE integration, no conditional breakpoints
- No REPL for interactive exploration
- No package manager with versioning or dependency constraints
- No formatter integrated into CI/CD workflows
- `hbformat` exists but isn't enforced

### 3.6 Value Representation Inefficiency

Every value is a full `HB_ITEM` tagged union (`hbapi.h:393-415`), sized for the
largest member. No NaN-boxing or compact representations for small integers or
booleans. Every stack slot is a full struct. Indirect access to container contents
causes cache misses. No compressed oops, no pointer tagging.

---

## 4. What Works (Don't Break These)

Before proposing changes, acknowledge what's sound:

1. **Platform matrix** — 20+ platforms with battle-tested configs. The C
   compilation target is the portability guarantee.
2. **Clipper compatibility** — `ValType()`, `Len()`, `HB_IS_OBJECT()` semantics
   are stable and trusted by production code worldwide.
3. **Scalar class infrastructure** — the 12 classes, registration, and dispatch
   machinery already exist and work for method calls. Just not wired for
   operators.
4. **Opcode dispatch layer** — Layer 3 in `hvm.c` is clean. It delegates to
   Layer 1 without duplication.
5. **OO system sophistication** — multiple inheritance, operator overloading,
   scoping, delegation, SYNC methods. The class system itself is capable.
6. **Preprocessor DSL power** — `#command`/`#translate` enables domain-specific
   languages that no modern preprocessor matches.

---

## 5. Modernization Plan — Three Tiers

The existing Drydock roadmap (RefactorHvm → ScalarClasses → ...) is **Tier 1,
Phases A-B**. It's the right starting point but doesn't touch the compiler
pipeline, the type system, concurrency, or tooling. The existing plan makes
Harbour a *better xBase runtime* but not a *modern compiler*.

### Tier 1: Fix the Foundation (months 1-6)

| Phase | Blueprint | Work | Why | Weeks |
|-------|-----------|------|-----|-------|
| **A** | RefactorHvm | Dead code removal, operator deduplication, branch hints | Reduce hvm.c maintenance multiplier from 33→14 cascade copies. Unblock ScalarClasses. | 2 |
| **B** | ScalarClasses | Wire tscalar.prg into VM dispatch; add operator + user-facing methods | Unify the two type hierarchies. Enable `cName:Upper()`, `nTotal:Format()`. | 3 |
| **C** | ComputedGoto | Replace 181-case switch with threaded dispatch table | 5-15% VM speedup. CPython/Lua pattern. Free perf. | 3 |
| **D** | GenerationalGC | Add young generation with write barriers | Reduce GC pause times 10-50x. Most allocations die young. | 6 |

**Deliverable**: A Harbour where every value is an object, strings can handle
UTF-8, the VM dispatches 5-15% faster, and GC pauses aren't user-visible.

### Tier 2: Build a Real Compiler (months 6-14)

| Phase | Blueprint | Work | Why | Weeks |
|-------|-----------|------|-----|-------|
| **E** | PersistentAST | Stop freeing expression trees. Build a proper AST that survives parsing. | **The single most important architectural change.** Everything else in Tier 2 depends on it. | 6 |
| **F** | GradualTyping | Make `AS` annotations produce compile-time warnings. Add flow-sensitive type narrowing. Gate behind `-kt`. | #1 developer productivity feature missing. | 6 |
| **G** | Optimizer | Build CFG from AST. Implement constant folding, constant propagation, dead code elimination, CSE. | Current optimizer is peephole-only. This is where real codegen improvement happens. | 8 |
| **H** | ModuleSystem | `IMPORT`/`EXPORT` with explicit visibility. Namespace-qualified symbols. Compile-time resolution. | Prerequisite for large-scale codebases. Eliminates global symbol pollution. | 6 |
| **I** | LSPServer | Built on persistent AST + type info. Go-to-definition, hover, diagnostics, autocomplete. | Makes the language usable in 2026 IDEs. | 8 |

**Deliverable**: A compiler that catches real bugs at compile time, produces
faster code, and works in VS Code/JetBrains.

### Tier 3: Unlock Performance (months 14-24)

| Phase | Blueprint | Work | Why | Weeks |
|-------|-----------|------|-----|-------|
| **J** | RemoveGIL | Per-object locking or lock-free structures. Thread-local allocation. True parallel execution. | Hardest change. Requires generational GC from Phase D. | 12 |
| **K** | RegisterPcode | Replace stack machine with register machine. | Reduces instruction count ~30%. Enables register allocation. | 8 |
| **L** | InlineCaching | Monomorphic/polymorphic inline caches at call sites. | Avoid hash lookup on every method dispatch. 2-5x speedup on OO code. | 4 |
| **M** | LLVMBackend | Optional JIT or AOT via LLVM for hot loops. | Only worth doing after register-based pcode. | 16 |

**Deliverable**: A Harbour competitive with Python/Ruby on compute-heavy
workloads, scaling across cores.

---

## 6. Dependency Graph

```
Tier 1                          Tier 2                          Tier 3
------                          ------                          ------

RefactorHvm ──→ ScalarClasses                                   RemoveGIL
                    │                                               ↑
                    ├──→ ExtensionMethods ──→ Traits            GenerationalGC
                    ├──→ Reflection                                 ↑
                    └──→ EncodingStrings                       ComputedGoto
                                                                    ↑
                                                              RegisterPcode ──→ LLVMBackend
                                                                    ↑
                                                              InlineCaching
                                                                    ↑
                         PersistentAST ──→ GradualTyping       (PersistentAST)
                              │                 │
                              ├──→ Optimizer     │
                              ├──→ LSPServer ←───┘
                              └──→ ModuleSystem
```

---

## 7. Priority Ranking

If you can only do some, this is the order that maximizes impact:

1. **RefactorHvm + ScalarClasses** — highest ROI, unblocks everything downstream
2. **PersistentAST** — without this, no serious compiler improvement is possible
3. **GradualTyping** — the #1 developer productivity feature missing
4. **LSPServer** — makes the language viable for new developers
5. **GenerationalGC** — eliminates the worst runtime surprise (GC pauses)
6. **ModuleSystem** — prerequisite for large-scale codebases
7. **ComputedGoto** — free performance, low risk
8. **Everything else** — depends on ambition and resources

---

## 8. What NOT to Do

- **Don't rewrite in Rust/Go.** The C codebase is the compatibility guarantee.
  Rewriting loses the 20+ platform matrix and the battle-tested runtime.
- **Don't add async/await before fixing the GIL.** Coroutines on a single thread
  are syntactic sugar, not concurrency.
- **Don't design a new language.** Harbour's value is Clipper compatibility.
  Modern features must layer on top, not replace.
- **Don't build a JIT before a proper IR.** JITs on stack-machine pcode are
  waste — you'll rewrite it when you add registers.
- **Don't split hvm.c into files without LTO.** Cross-function inlining in the
  hot loop matters. File splits need link-time optimization enabled first.

---

## 9. Detailed Component Assessments

### 9.1 Compiler Pipeline

| Aspect | Rating | Notes |
|--------|--------|-------|
| Grammar completeness | 3/5 | Covers Clipper/xBase++ but lacks lambdas, pattern matching, generics, destructuring |
| Code generation | 3/5 | Indirect (pcode-based), functional but not optimizable |
| Optimization | 1/5 | Peephole only. No global optimization, no CFG, no data flow |
| AST/IR quality | 2/5 | Expression-tree based, single-pass, freed immediately |
| Error diagnostics | 2/5 | Line numbers only. No suggestions, no snippets, no recovery |
| Type system | 1/5 | Parses `AS` annotations, stores them, validates nothing |
| Modularity | 2/5 | Procedural, tightly coupled, single-pass |

### 9.2 Virtual Machine

| Aspect | Rating | Notes |
|--------|--------|-------|
| Dispatch efficiency | 2/5 | Switch-based, no computed goto, no branch hints |
| GC | 2/5 | Stop-the-world, non-generational, no write barriers |
| Value representation | 2/5 | Full tagged union per slot, no compact encodings |
| Object model | 3/5 | Hash-based dispatch is capable but no inline caching |
| Threading | 1/5 | Global VM lock, cooperative scheduling, no true parallelism |
| Memory management | 3/5 | `hb_xgrab`/`hb_xfree` wrappers are consistent but global-lock bound |

### 9.3 Tooling

| Aspect | Rating | Notes |
|--------|--------|-------|
| Build system | 3/5 | Works but GNU Make only, 2K-line global.mk |
| IDE integration | 0/5 | No LSP, no DAP |
| Package management | 1/5 | 74 contribs, no versioning, no dependency resolution |
| Debugging | 1/5 | TUI-only debugger, no conditional breakpoints, no remote |
| Testing | 3/5 | `hbtest` exists and works, but no unit test framework for C internals |

---

## 10. Summary

Harbour is a **working compiler with 2005-era internals**. The two fundamental
problems are:

1. **No persistent IR/AST** to enable modern compiler analyses
2. **A VM architecture that can't exploit modern hardware** (GIL,
   non-generational GC, switch-dispatched stack machine)

The Drydock roadmap correctly starts with OO unification (ScalarClasses), but
the real unlock is **Phase E: PersistentAST** — that's the fork in the road
between "better xBase" and "modern compiler."

The path forward is incremental: fix the runtime foundation first (Tier 1), then
build proper compiler infrastructure (Tier 2), then unlock hardware-level
performance (Tier 3). Each tier delivers standalone value. No tier requires
burning what works.
