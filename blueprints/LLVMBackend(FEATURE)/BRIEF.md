# BRIEF -- LLVMBackend (FEATURE)

## Identity

| Field | Value |
|-------|-------|
| **Name** | LLVMBackend |
| **Mode** | FEATURE |
| **Tier** | 3 — Unlock Performance |
| **Phase** | M |
| **Component** | Compiler — `src/compiler/`, new `src/compiler/genllvm.c` |
| **Status** | PLANNING |

---

## 1. Motivation

Harbour currently generates C source code (`genc.c`) containing embedded pcode
byte arrays, which are then compiled by GCC/Clang and interpreted by the VM at
runtime. This means you pay the cost of C compilation but get none of its
optimization benefits — the C compiler sees opaque byte arrays, not optimizable
code.

An LLVM backend would emit LLVM IR directly from the AST, enabling:

- **AOT compilation** — compile Harbour directly to native code, eliminating
  VM interpretation overhead entirely
- **JIT compilation** — compile hot functions at runtime via LLVM's ORC JIT
- **Full optimization suite** — LLVM's optimization passes (SROA, GVN, LICM,
  vectorization) applied to Harbour code
- **Native debugging** — DWARF debug info for source-level debugging in GDB/LLDB

This is the end-state for performance: Harbour code compiled to the same quality
as C code, with the same optimization passes.

---

## 2. Scope

- New code generator: `genllvm.c` emitting LLVM IR from AST
- Runtime library bindings: map `hb_vm*` functions to LLVM-callable symbols
- Type mapping: `HB_ITEM` → LLVM struct types with known layout
- GC integration: stack maps for LLVM-compiled frames
- Incremental: start with AOT for hot functions, expand to full-program compilation

---

## 3. Dependencies

| Dependency | Status | Notes |
|------------|--------|-------|
| PersistentAST (Phase E) | PLANNING | **Required** — LLVM IR emission needs AST, not pcode |
| RegisterPcode (Phase K) | PLANNING | **Strongly recommended** — register IR maps cleanly to LLVM IR; stack pcode requires decompilation |
| Optimizer (Phase G) | PLANNING | Recommended — pre-optimized AST produces cleaner LLVM IR |

## 4. Estimated Scope

**16 weeks** — the largest compiler workstream. Broken into: basic IR emission
(6w), runtime integration (4w), optimization pipeline (4w), JIT support (2w).

---

[<- Index](../INDEX.md) · [Map](../MAP.md) · **BRIEF**
