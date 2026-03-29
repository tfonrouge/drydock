# Blueprints Index
**Updated**: 2026-03-27
**North Star**: Make Harbour a modern compiler — unify scalar types through OO dispatch, build a real type-checked compilation pipeline with persistent AST, unlock hardware-level performance, and replace the 26,793-line build system with a single `build.zig`.

**Analysis**: [Compiler assessment](../doc/drydock/compiler-assessment.md) · [Build system assessment](../doc/drydock/build-assessment.md)

---

## Tier 0 — Build Infrastructure (parallel with all tiers)

| Phase | Name | Mode | Status | Owner | Blocked By |
|-------|------|------|--------|-------|------------|
| Z | [ZigBuild](ZigBuild(SUBSYSTEM)/BRIEF.md) | SUBSYSTEM | :yellow_circle: ACTIVE | @tfonrouge | -- (independent) |
| H | [HRBModern](HRBModern(FEATURE)/BRIEF.md) | FEATURE | :yellow_circle: ACTIVE | @tfonrouge | -- (independent) |

**Deliverable**: Replace 26,793 lines of GNU Make + hbmk2 with ~500-line `build.zig`. Fix `.hrb` bytecode format and make it the default for dev builds — `.prg → .hrb` (milliseconds) instead of `.prg → .c → gcc → .o` (seconds). Correct incremental builds. One-command cross-compilation.

## Tier 1 — Fix the Foundation (months 1-6)

| Phase | Name | Mode | Status | Owner | Blocked By |
|-------|------|------|--------|-------|------------|
| A0 | [DrydockObject](DrydockObject(SUBSYSTEM)/BRIEF.md) | SUBSYSTEM | :green_circle: STABLE | @tfonrouge | -- (new Tier 1 root) |
| A | [RefactorHvm](RefactorHvm(SUBSYSTEM)/BRIEF.md) | SUBSYSTEM | :yellow_circle: ACTIVE | @tfonrouge | -- (independent) |
| B | [ScalarClasses](ScalarClasses(SUBSYSTEM)/BRIEF.md) | SUBSYSTEM | :green_circle: STABLE | @tfonrouge | DrydockObject (done) |
| A1 | [DrydockAPI](DrydockAPI(SUBSYSTEM)/BRIEF.md) | SUBSYSTEM | :blue_circle: PLANNING | @tfonrouge | ScalarClasses (done) |
| B+ | [ExtensionMethods](ExtensionMethods(FEATURE)/BRIEF.md) | FEATURE | :yellow_circle: ACTIVE | @tfonrouge | ScalarClasses (done) |
| C | [ComputedGoto](ComputedGoto(SUBSYSTEM)/BRIEF.md) | SUBSYSTEM | :blue_circle: PLANNING | -- | RefactorHvm (recommended) |
| D | [GenerationalGC](GenerationalGC(SUBSYSTEM)/BRIEF.md) | SUBSYSTEM | :blue_circle: PLANNING | -- | DrydockAPI + RefactorHvm Phase 3 |

**Deliverable**: Every value is an object — DrydockObject root class, toString() on any value, all scalar methods in C (no ENABLE TYPE CLASS ALL needed), extension method syntax (`FUNCTION STRING.method()`). Handle-based extension API (`dd_*`) replaces raw pointer C API. Strings handle UTF-8. VM dispatches 5-15% faster. GC pauses < 1ms.

## Tier 2 — Build a Real Compiler (months 6-14)

| Phase | Name | Mode | Status | Owner | Blocked By |
|-------|------|------|--------|-------|------------|
| E | [PersistentAST](PersistentAST(SUBSYSTEM)/BRIEF.md) | SUBSYSTEM | :blue_circle: PLANNING | -- | -- (Tier 2 root) |
| F | [GradualTyping](GradualTyping(FEATURE)/BRIEF.md) | FEATURE | :blue_circle: PLANNING | -- | PersistentAST |
| G | [Optimizer](Optimizer(SUBSYSTEM)/BRIEF.md) | SUBSYSTEM | :blue_circle: PLANNING | -- | PersistentAST |
| H | [ModuleSystem](ModuleSystem(FEATURE)/BRIEF.md) | FEATURE | :blue_circle: PLANNING | -- | PersistentAST |
| I | [LSPServer](LSPServer(FEATURE)/BRIEF.md) | FEATURE | :blue_circle: PLANNING | -- | PersistentAST + GradualTyping |

**Deliverable**: Compile-time type checking. Real optimizations. IDE support via LSP. Module system.

## Tier 3 — Unlock Performance (months 14-24)

| Phase | Name | Mode | Status | Owner | Blocked By |
|-------|------|------|--------|-------|------------|
| J | [RemoveGIL](RemoveGIL(SUBSYSTEM)/BRIEF.md) | SUBSYSTEM | :blue_circle: PLANNING | -- | GenerationalGC |
| K | [RegisterPcode](RegisterPcode(SUBSYSTEM)/BRIEF.md) | SUBSYSTEM | :blue_circle: PLANNING | -- | PersistentAST + Optimizer |
| L | [InlineCaching](InlineCaching(FEATURE)/BRIEF.md) | FEATURE | :blue_circle: PLANNING | -- | ScalarClasses (recommended) |
| M | [LLVMBackend](LLVMBackend(FEATURE)/BRIEF.md) | FEATURE | :blue_circle: PLANNING | -- | PersistentAST + RegisterPcode |

**Deliverable**: True parallelism. Register-based VM. Inline caching for OO dispatch. Optional LLVM AOT/JIT.

---

## Planned (from original Drydock roadmap, integrated above)

| Name | Integrated Into | Notes |
|------|----------------|-------|
| Reflection | After DrydockObject (A0) | `__Methods()`, `__Data()` as DrydockObject methods |
| EncodingStrings | After ScalarClasses (B) | UTF-8 per-string encoding field |
| Traits/Mixins | After ExtensionMethods (B+) | `TRAIT`/`MIXIN` syntax with method copy |
| BlockScoping | PersistentAST (E) | `LOCAL` inside IF/FOR/WHILE blocks; compile-time scope restriction |
| DAP Debug Server | Independent | Debug Adapter Protocol as contrib module |
| Conditional Breakpoints | Independent | Extend `HB_BREAKPOINT` |

## Completed

| Name | Completed | Notes |
|------|-----------|-------|
| ZigBuild Phase Z.0 | 2026-03-26 | `-MMD -MP` header dependency tracking; incremental builds work (`70d3813`) |
| ZigBuild Phase Z.1 | 2026-03-26 | `build.zig` compiler bootstrap; `zig build` produces working `harbour`; cross-compilation to Windows verified |
| ZigBuild Phase Z.2 | 2026-03-26 | Full C build — 26 static libraries (vm, rtl, macro, rdd, codepage, lang, debug, pcre, zlib, GT drivers) in 5.5s |
| Binary rename | 2026-03-26 | harbour→drydock, hbmk2→ddmake, hbtest→ddtest, hbrun→ddrun, hbpp→ddpp, hbformat→ddformat |
| ZigBuild Phase Z.3 | 2026-03-27 | Two-phase bootstrap: 115 `.prg` → `.c` via `captureStdOut`, ddtest links and runs |
| ScalarClasses Phase 1 | 2026-03-27 | User-facing methods on all scalar types. 75 tests pass. `"hello":Upper()`, `(42):Abs()`, `{1,2,3}:Map()`, etc. |
| DrydockObject | 2026-03-27 | Root class in C. `toString()`, `isScalar()`, `isNil()`, `valType()` on ANY value. 11 scalar classes always available. ddtest 4861/4861 pass. |
| ScalarClasses Phase 2 | 2026-03-28 | 60 methods in C (54 scalar + 6 universal) — ENABLE TYPE CLASS ALL deprecated. Operators: `{1,2}+{3,4}`, `"abc"*3`. tscalar.prg stripped to stubs. |
| ScalarClasses Phase 3 | 2026-03-28 | Benchmarks (int 20ms/1M, Upper 84ms/1M). Zero regression. ENABLE TYPE CLASS ALL deprecation note. STABLE. |
| ExtensionMethods E.1 | 2026-03-28 | `EXTEND CLASS STRING WITH METHOD ... ACTION`. `__clsFindByName()` with STRING/NUMBER/BOOL aliases. Works in .hrb runtime. |
| RefactorHvm R1a | 2026-03-29 | Factor 4 ordering comparisons into `hb_vmCompare()` — ~180 lines saved. ddtest 4861/4861. |
| RefactorHvm R1b | 2026-03-29 | Factor Inc/Dec into `hb_vmIncDec(iDir)` — ~60 lines saved. |
| RefactorHvm Phase 3 | 2026-03-29 | `HB_LIKELY`/`HB_UNLIKELY` branch hints in hbdefs.h. Hot paths annotated in hvm.c. |
| DrydockObject Phase 2 | 2026-03-29 | `compareTo()` (-1/0/1/NIL) and `isComparable()` on any value. 16 tests pass. |
| OO Structure Prep | 2026-03-29 | CLASS.uiVersion, HB_U64 nOpFlags, DD_METHOD_* macros for InlineCaching + RegisterPcode readiness. |
| HRBModern H.5 | 2026-03-29 | INIT procedures auto-execute on .hrb load. Extension methods from INIT work. |
| HRBModern H.3 | 2026-03-29 | `hrbembed` tool generates C embedding from .hrb files. Standalone executables without per-function C generation. |
