# BRIEF -- RemoveGIL (SUBSYSTEM)

## Identity

| Field | Value |
|-------|-------|
| **Name** | RemoveGIL |
| **Mode** | SUBSYSTEM |
| **Tier** | 3 — Unlock Performance |
| **Phase** | J |
| **Component** | VM — `src/vm/hvm.c`, `src/vm/thread.c`, `src/vm/garbage.c` |
| **Status** | PLANNING |

---

## 1. Motivation

Harbour has a Global VM Lock (`HB_VM_LOCK()`). Only one thread executes pcode
at a time, regardless of core count. This is Python's GIL problem. Multi-threaded
Harbour applications get zero parallel speedup on compute-bound workloads.

Removing the GIL enables true parallel execution, making Harbour viable for
modern multi-core server workloads.

---

## 2. Scope

- Replace global VM lock with fine-grained per-object locking or lock-free
  data structures
- Thread-local allocation pools (per-thread nurseries from GenerationalGC)
- Lock-free symbol table reads (read-copy-update or similar)
- Per-thread stack and frame management
- Atomic reference counting or concurrent GC tracing

This is the hardest change in the entire roadmap. It touches every shared data
structure in the VM.

---

## 3. Dependencies

| Dependency | Status | Notes |
|------------|--------|-------|
| GenerationalGC (Phase D) | PLANNING | **Required** — per-thread nurseries are the foundation for lock-free allocation |
| ComputedGoto (Phase C) | PLANNING | Recommended — cleaner dispatch loop simplifies thread-safety analysis |

## 4. Estimated Scope

**12 weeks** — the largest single workstream in the roadmap.

---

[<- Index](../INDEX.md) · [Map](../MAP.md) · **BRIEF**
