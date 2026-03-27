# System Roadmap
**Updated**: 2026-03-26
**Current Focus**: Tier 0 (ZigBuild Phase Z.3 + HRBModern H.1) + Tier 1 (RefactorHvm Phase 0) — in parallel

## Full Dependency Graph

```mermaid
graph LR
  subgraph Tier 0 — Build
    Z[ZigBuild] -.-> HM[HRBModern]
    HM -.-> Z
  end

  subgraph Tier 1 — Foundation
    A[RefactorHvm] --> B[ScalarClasses]
    A -.-> C[ComputedGoto]
    A -.-> D[GenerationalGC]
    B --> EM[ExtensionMethods]
    B --> RF[Reflection]
    B --> ES[EncodingStrings]
    EM --> TR[Traits]
  end

  subgraph Tier 2 — Compiler
    E[PersistentAST] --> F[GradualTyping]
    E --> G[Optimizer]
    E --> H[ModuleSystem]
    E --> I[LSPServer]
    F --> I
  end

  subgraph Tier 3 — Performance
    D --> J[RemoveGIL]
    E --> K[RegisterPcode]
    G --> K
    K --> M[LLVMBackend]
    B -.-> L[InlineCaching]
    C -.-> L
  end
```

Solid arrows = hard dependency. Dashed arrows = recommended but not blocking.
Tier 0 (ZigBuild) is independent — runs in parallel with everything.

## Sprint Focus

| Blueprint | Status | Goal This Sprint |
|-----------|--------|-----------------|
| ZigBuild(SUBSYSTEM) | :yellow_circle: ACTIVE | ~~Z.0-Z.2 done (2026-03-26).~~ Next: Phase Z.3 — `.hrb`-first dev builds + C release path. |
| HRBModern(FEATURE) | :yellow_circle: ACTIVE | ~~Phase H.1: v3 writer + reader done (2026-03-26).~~ Next: H.2 (bundling) or H.4 (`-dp` disassembler). |
| RefactorHvm(SUBSYSTEM) | :blue_circle: PLANNING | Begin Phase 0 (dead code removal — 680 lines, zero callers) |
| ScalarClasses(SUBSYSTEM) | :blue_circle: PLANNING | BRIEF + DESIGN complete; begin Phase 1 once RefactorHvm Phase 0 lands |
| ComputedGoto(SUBSYSTEM) | :blue_circle: PLANNING | BRIEF complete; implementation can proceed independently |
| GenerationalGC(SUBSYSTEM) | :blue_circle: PLANNING | BRIEF complete; design phase — identify all write barrier insertion points |

## Parallelism

Two independent tracks can proceed simultaneously:

**Track A — Build Infrastructure (Tier 0)**
```
Z.0 (add -MMD) ✓
  → Z.1 (zig compiler bootstrap) ✓
  → Z.2 (full C build) ✓
  → Z.3 (.hrb-first dev builds + C release path, 1 week)
  → Z.4 (contrib migration, 2 weeks)
  → Z.5 (Make removal, 1 week)
  → Z.6 (hbmk2 simplification, 2-3 weeks)

H.1 (fix .hrb v3 format, 3 days) — independent, can start now
  → H.2 (.hrb bundling, 3 days)
  → H.3 (.hrb embedding, 3 days)
H.4 (CLI: -dp, -gejson, 2 days) — independent
H.5 (auto INIT/EXIT in .hrb, 1 day) — after H.1
```

**Track B — Runtime Modernization (Tiers 1-3)**
```
RefactorHvm → ScalarClasses → ExtensionMethods → Traits
                           → Reflection
                           → EncodingStrings
ComputedGoto (independent)
GenerationalGC (independent)
```

These tracks have **zero dependencies** on each other. Build infrastructure
changes don't touch compiler/VM source code. Compiler/VM changes don't
touch the build system.

## Upcoming — Tier 1 Follow-On

| Blueprint | Mode | Unblocked By | Notes |
|-----------|------|-------------|-------|
| ExtensionMethods | FEATURE | ScalarClasses | `EXTEND CLASS` syntax for adding methods to scalar types |
| EncodingStrings | SUBSYSTEM | ScalarClasses | UTF-8 aware string type via scalar class infrastructure |
| Reflection | FEATURE | ScalarClasses | Runtime type introspection via scalar class metadata |
| Traits | FEATURE | ExtensionMethods | `TRAIT`/`MIXIN` syntax with compile-time method copy |

## Upcoming — Tier 2

| Blueprint | Mode | Unblocked By | Notes |
|-----------|------|-------------|-------|
| PersistentAST | SUBSYSTEM | *(root)* | **Critical unlock** — retain AST after parsing; enables all Tier 2 work |
| GradualTyping | FEATURE | PersistentAST | Make `AS` annotations produce compile-time warnings |
| Optimizer | SUBSYSTEM | PersistentAST | CFG-based constant folding, propagation, DCE, CSE |
| ModuleSystem | FEATURE | PersistentAST | `IMPORT`/`EXPORT` with namespaces |
| LSPServer | FEATURE | PersistentAST + GradualTyping | IDE integration via Language Server Protocol |

## Upcoming — Tier 3

| Blueprint | Mode | Unblocked By | Notes |
|-----------|------|-------------|-------|
| RemoveGIL | SUBSYSTEM | GenerationalGC | True parallel execution; per-object locking |
| RegisterPcode | SUBSYSTEM | PersistentAST + Optimizer | Register-based instruction set; ~30% fewer instructions |
| InlineCaching | FEATURE | ScalarClasses | Monomorphic/polymorphic method caches; 2-5x OO speedup |
| LLVMBackend | FEATURE | RegisterPcode | AOT/JIT via LLVM; native code quality |

## Blocked

| Blueprint | Blocked On | Est. Resolution |
|-----------|-----------|----------------|
| ScalarClasses Phase 3 | RefactorHvm Phases 0-1 | Sprint 1 |
| ZigBuild Phase Z.3 | Z.1 + Z.2 | Week 3 |
| GradualTyping | PersistentAST | Tier 2 start |
| Optimizer | PersistentAST | Tier 2 start |
| LSPServer | PersistentAST + GradualTyping | Tier 2 mid |
| RemoveGIL | GenerationalGC | Tier 3 start |
| RegisterPcode | PersistentAST + Optimizer | Tier 3 start |
| LLVMBackend | RegisterPcode | Tier 3 mid |

## North Star

Every Harbour value supports method dispatch and operator overloading through a
unified OO system. The compiler catches type errors at compile time, produces
optimized code via a persistent AST and CFG-based optimizer, and integrates with
modern IDEs via LSP. The VM executes on all cores via lock-free parallelism, with
sub-millisecond GC pauses and optional native compilation through LLVM.

The build system is a single file that cross-compiles to any platform with one
command: `zig build -Dtarget=x86_64-windows-gnu`.

Backward compatibility: 99.5% source compatibility with existing Clipper/Harbour
code. All breaks documented, non-silent, and discoverable at compile time.
