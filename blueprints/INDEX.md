# Blueprints Index
**Updated**: 2026-03-26
**North Star**: Make Harbour a modern compiler — unify scalar types through OO dispatch, build a real type-checked compilation pipeline with persistent AST, unlock hardware-level performance, and replace the 26,793-line build system with a single `build.zig`.

**Analysis**: [Compiler assessment](../doc/drydock-compiler-assessment.md) · [Build system assessment](../doc/drydock-build-assessment.md)

---

## Tier 0 — Build Infrastructure (parallel with all tiers)

| Phase | Name | Mode | Status | Owner | Blocked By |
|-------|------|------|--------|-------|------------|
| Z | [ZigBuild](ZigBuild(SUBSYSTEM)/BRIEF.md) | SUBSYSTEM | :yellow_circle: ACTIVE | @tfonrouge | -- (independent) |

**Deliverable**: Replace 26,793 lines of GNU Make + hbmk2 with ~500-line `build.zig`. Correct incremental builds. One-command cross-compilation. 2-5x faster builds.

## Tier 1 — Fix the Foundation (months 1-6)

| Phase | Name | Mode | Status | Owner | Blocked By |
|-------|------|------|--------|-------|------------|
| A | [RefactorHvm](RefactorHvm(SUBSYSTEM)/BRIEF.md) | SUBSYSTEM | :blue_circle: PLANNING | @tfonrouge | -- |
| B | [ScalarClasses](ScalarClasses(SUBSYSTEM)/BRIEF.md) | SUBSYSTEM | :blue_circle: PLANNING | @tfonrouge | RefactorHvm Phases 0-1 (for Phase 3) |
| C | [ComputedGoto](ComputedGoto(SUBSYSTEM)/BRIEF.md) | SUBSYSTEM | :blue_circle: PLANNING | -- | RefactorHvm (recommended) |
| D | [GenerationalGC](GenerationalGC(SUBSYSTEM)/BRIEF.md) | SUBSYSTEM | :blue_circle: PLANNING | -- | RefactorHvm Phase 3 (branch hints) |

**Deliverable**: Every value is an object. Strings handle UTF-8. VM dispatches 5-15% faster. GC pauses < 1ms.

## Tier 2 — Build a Real Compiler (months 6-14)

| Phase | Name | Mode | Status | Owner | Blocked By |
|-------|------|------|--------|-------|------------|
| E | [PersistentAST](PersistentAST(SUBSYSTEM)/BRIEF.md) | SUBSYSTEM | :blue_circle: PLANNING | -- | -- (Tier 2 root) |
| F | [GradualTyping](GradualTyping(FEATURE)/BRIEF.md) | FEATURE | :blue_circle: PLANNING | -- | PersistentAST |
| G | [Optimizer](Optimizer(SUBSYSTEM)/BRIEF.md) | SUBSYSTEM | :blue_circle: PLANNING | -- | PersistentAST |
| H | [ModuleSystem](ModuleSystem(FEATURE)/BRIEF.md) | FEATURE | :blue_circle: PLANNING | -- | PersistentAST (benefits) |
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
| ExtensionMethods | After ScalarClasses (B) | `EXTEND CLASS` syntax; blocked by ScalarClasses |
| Reflection | After ScalarClasses (B) | `__Methods()`, `__Data()` as HBObject methods |
| EncodingStrings | After ScalarClasses (B) | UTF-8 per-string encoding field |
| Traits/Mixins | After ExtensionMethods | `TRAIT`/`MIXIN` syntax with method copy |
| DAP Debug Server | Independent | Debug Adapter Protocol as contrib module |
| Conditional Breakpoints | Independent | Extend `HB_BREAKPOINT` |

## Completed

| Name | Completed | Notes |
|------|-----------|-------|
| ZigBuild Phase Z.0 | 2026-03-26 | `-MMD -MP` header dependency tracking; incremental builds work (`70d3813`) |
| ZigBuild Phase Z.1 | 2026-03-26 | `build.zig` compiler bootstrap; `zig build` produces working `harbour`; cross-compilation to Windows verified |
