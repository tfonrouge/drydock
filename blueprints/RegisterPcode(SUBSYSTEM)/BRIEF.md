# BRIEF -- RegisterPcode (SUBSYSTEM)

## Identity

| Field | Value |
|-------|-------|
| **Name** | RegisterPcode |
| **Mode** | SUBSYSTEM |
| **Tier** | 3 — Unlock Performance |
| **Phase** | K |
| **Component** | Compiler — `src/compiler/`, VM — `src/vm/hvm.c` |
| **Status** | PLANNING |

---

## 1. Motivation

Harbour uses a **stack-based** pcode machine. Every operation pushes and pops
from a central stack. This is simple to implement but generates ~30% more
instructions than a register-based machine, because intermediate values must
bounce through the stack:

```
/* Stack: a + b * c */
PUSH a          /* stack: [a] */
PUSH b          /* stack: [a, b] */
PUSH c          /* stack: [a, b, c] */
MULT            /* stack: [a, b*c] */
PLUS            /* stack: [a+b*c] */

/* Register: a + b * c */
MUL r1, b, c   /* r1 = b * c */
ADD r0, a, r1  /* r0 = a + b * c */
```

Register machines also enable register allocation, which keeps hot values in
CPU registers rather than memory (the VM's logical registers map to physical
registers when JIT-compiled).

---

## 2. Scope

- Design register-based instruction set (targeting 256 virtual registers)
- New code generator from AST (requires PersistentAST Phase E)
- Register allocator (linear scan or graph coloring)
- New VM dispatch loop for register instructions
- Backward compatibility: retain stack-based pcode for `.hrb` files;
  register pcode for compiled C output only

---

## 3. Dependencies

| Dependency | Status | Notes |
|------------|--------|-------|
| PersistentAST (Phase E) | PLANNING | **Required** — register allocation needs AST/CFG |
| Optimizer (Phase G) | PLANNING | Recommended — optimized AST produces better register code |

**Blocks**: LLVMBackend (Phase M) — LLVM lowering works much better from
register-based IR than stack-based pcode.

## 4. Estimated Scope

**8 weeks** — new instruction set design, code generator, register allocator,
VM loop.

---

[<- Index](../INDEX.md) · [Map](../MAP.md) · **BRIEF**
