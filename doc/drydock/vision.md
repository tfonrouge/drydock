# Drydock — Harbour Modernization Plan

This is a fork of the original [Harbour compiler](https://github.com/harbour/core).
This fork (`https://github.com/tfonrouge/core`) is the home of the Drydock initiative
— a focused effort to modernize the Harbour compiler internals while preserving
compatibility with the upstream codebase and the broader Harbour ecosystem.

**North star:** Modernize the Harbour compiler — make it more usable,
debuggable, and pluggable while maintaining **99.5% backward compatibility**.

> Why not 100%? Because that is a lie anyone tells themselves to avoid
> hard decisions. Every meaningful improvement has a blast radius. The honest
> question is not "does it break anything?" but "does it break anything that
> matters, and is the breakage discoverable before production?" Drydock targets
> 99.5% — the remaining 0.5% is documented, mitigatable, and caught at
> compile-time or first test run. Zero silent data corruption. Zero runtime
> surprises for correct code.

---

## The Core Problem

Harbour has two type systems that do not talk to each other. The VM
(`src/vm/hvm.c`) handles primitive types through if/else cascades — 64
occurrences of `hb_objOperatorCall` as the last-resort fallback. Meanwhile,
`src/vm/classes.c` implements a sophisticated OO system (multiple inheritance,
operator overloading, scoping, delegation, SYNC methods) that scalars never
benefit from.

The existing scalar wrapper classes in `src/rtl/tscalar.prg` (written 2004,
C bindings 2007) prove the concept works — 12 classes covering every type.
They just aren't wired into VM operator dispatch. Drydock finishes what was
started 20 years ago.

For the full technical analysis, see [drydock-analysis.md](drydock-analysis.md).

---

## Workstreams

### SUBSYSTEM (deep structural changes)

| # | Workstream | What Changes | Effort |
|---|-----------|-------------|--------|
| 1 | **Scalar Classes** | Wire `tscalar.prg` classes into VM dispatch; unify operator handling through `hb_objOperatorCall`; keep arithmetic fast paths inline | 2 wk |
| 2 | **Gradual Typing** | Make the existing `AS` type annotations functional; compile-time warnings for mismatches; opt-in `HB_P_TYPECHECK` opcode | 6 wk |
| 3 | **Encoding-Aware Strings** | Add `encoding` byte to `hb_struString`; `U"..."` literals; `Len()` stays bytes, new `:Chars()` method | 5 wk |
| 4 | **VM Dispatch Table** | Replace 181-case switch with computed goto dispatch table; split `hvm.c` (12K lines) into per-category handler files | 3 wk |

### FEATURE (self-contained additions)

| # | Workstream | What It Adds | Effort |
|---|-----------|-------------|--------|
| 5 | **Structured Reflection** | `__Methods()`, `__Data()`, `__ClassTree()`, `__Implements()` as HBObject methods, wrapping existing `__cls*` functions | 1 wk |
| 6 | **Extension Methods** | `EXTEND CLASS <name>` syntax routing to `__clsAddMsg()` — lets contribs add methods to any class | 2 wk |
| 7 | **Conditional Breakpoints** | Extend `HB_BREAKPOINT` with condition, hit count, logpoint fields | 1 wk |
| 8 | **DAP Debug Server** | Debug Adapter Protocol server as contrib module; pluggable via `HB_DBG_CALLBACKS` interface | 7 wk |
| 9 | **Traits / Mixins** | `TRAIT`/`ENDTRAIT`/`MIXIN` syntax; compile-time method copy via `__clsAddMsg()` | 3 wk |
| 10 | **Module System** | `MODULE`/`IMPORT`/`EXPORT` syntax; namespace-qualified symbols; compile-time import verification | 13 wk |

### Dependencies

```
ScalarClasses ──→ ExtensionMethods ──→ Traits
ScalarClasses ──→ Reflection
ScalarClasses ──→ EncodingStrings
ConditionalBreakpoints ──→ DAP
PersistentAST ──→ ModuleSystem
ModuleSystem ──→ LSPServer (for auto-import)
```

### Priority Matrix

| # | Workstream | Usability | Debug | Pluggability |
|---|-----------|-----------|-------|--------------|
| 1 | Scalar Classes | Transformative | High | Transformative |
| 5 | Reflection | High | High | High |
| 6 | Extension Methods | High | Low | Transformative |
| 7 | Conditional Breakpoints | Low | Transformative | Low |
| 8 | DAP Server | Medium | Transformative | Medium |
| 4 | VM Dispatch | Low | Medium | Low |
| 2 | Gradual Typing | High | High | Medium |
| 3 | Encoding Strings | High | Low | Medium |
| 9 | Traits | Medium | Low | Transformative |
| 10 | Module System | High | Medium | Transformative |

---

## Compatibility Covenant

These rules are non-negotiable. If a change cannot satisfy all seven, it does
not ship.

1. `ValType()` never changes its return value for any existing type.
2. `Len()` always returns bytes.
3. `HB_IS_OBJECT()` returns `.F.` for scalar values.
4. New keywords are context-sensitive — never break existing identifiers.
5. New warnings require explicit opt-in via compiler flag.
6. User-defined methods always shadow scalar class methods.
7. All ABI breaks are gated behind a pcode version bump.

For the full fracture analysis with grep-counted call sites and risk
percentages, see [drydock-analysis.md](drydock-analysis.md#compatibility-fracture-map).

---

## Key Files Affected

| File | Changes |
|------|---------|
| `src/vm/hvm.c` | Reduce operator cascades, dispatch table, file split |
| `src/vm/classes.c` | Register scalar classes, extension methods, traits |
| `src/compiler/harbour.y` | EXTEND CLASS, TRAIT, MIXIN, U"..." syntax |
| `src/compiler/complex.c` | Lexer support for new keywords |
| `src/compiler/expropta.c` | Type validation pass |
| `include/hbapi.h` | String encoding field |
| `include/hbapicls.h` | Scalar class registration API |
| `include/hbapidbg.h` | Debug callback interface |
| `include/hbcomp.h` | Variable declared type field |
| `src/debug/dbgentry.c` | Callback dispatch, conditional breakpoints |
| `contrib/hbdap/` | New: DAP server module |

---

## Related Documents

| Document | Purpose |
|----------|---------|
| [drydock-analysis.md](drydock-analysis.md) | Full technical analysis, per-workstream deep dive, compatibility fracture map |
| `blueprints/INDEX.md` | Per-workstream status board (created when implementation begins) |
| `blueprints/MAP.md` | Dependency graph and sprint focus (created when implementation begins) |
| `CLAUDE.md` | Claude Code guidance for working in this repository |
