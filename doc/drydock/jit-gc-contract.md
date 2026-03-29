# JIT-GC Integration Contract

**Status**: Design reference (not a blueprint — cross-cuts multiple blueprints)
**Purpose**: Define the contract between JIT-compiled code and the garbage
collector. Referenced by GenerationalGC, LLVMBackend, InlineCaching, RemoveGIL,
and DrydockAPI blueprints.

---

## Why This Document Exists

Choosing good JIT and GC algorithms separately is not enough — they must be
designed together. A JIT that doesn't emit GC metadata produces code that
crashes during collection. A GC that doesn't coordinate with compiled code
corrupts live objects. This document defines the 5 integration points that
every blueprint touching JIT or GC must respect.

---

## 1. Stack Maps (GC Maps)

**What**: Metadata emitted by the JIT at each **safepoint** describing which
registers and stack slots contain GC references (handles or raw pointers).

**Why**: Without stack maps, the GC cannot trace the stack of compiled frames.
Objects referenced only from registers would be missed during marking and
incorrectly collected.

```
SafepointInfo {
    pc_offset: 0x1A30,
    live_refs: [
        { location: REG_R12,   type: DD_HANDLE },
        { location: STACK_-16, type: DD_HANDLE },
        { location: STACK_-24, type: DD_HANDLE }
    ]
}
```

**Who implements**: LLVMBackend (Phase M) emits stack maps. GenerationalGC
(Phase D) and future concurrent GC consume them during marking.

**Drydock-specific note**: Because the `dd_*` API uses handles (indices into a
table), stack maps for handle-based code are simpler — the GC traces the handle
table, not individual stack slots. Stack maps are only needed for JIT code that
uses raw `PHB_ITEM` pointers internally (e.g., interpreter fast paths).

---

## 2. Write Barriers

**What**: Code emitted by the JIT (or inlined in the interpreter) after every
pointer store that may create a cross-generational reference.

**Why**: In a generational GC, the young gen is collected independently of the
old gen. If an old-gen object points to a young-gen object, the GC must know
about it — otherwise it might collect the young-gen object (thinking it's
unreachable) while the old-gen object still references it.

**Two barriers needed**:

### 2.1 Generational Barrier (for GenerationalGC)

After storing a reference from old → young, record it in the remembered set:

```c
/* Pseudocode — emitted by JIT or inlined in VM */
void dd_write_barrier( PHB_ITEM pObj, PHB_ITEM pValue )
{
   if( dd_is_old_gen( pObj ) && dd_is_young_gen( pValue ) )
      dd_remembered_set_add( pObj );
}
```

**Drydock-specific note**: Because Harbour's allocator uses `malloc()` (objects
scattered across heap), generation identity is stored as a bit in the
`HB_GARBAGE` header — not determined by address range. The barrier checks
this bit, not address comparisons.

### 2.2 SATB Barrier (for incremental/concurrent marking)

During an ongoing tri-color marking phase, if the mutator overwrites a
reference, the **old** value must be marked gray (snapshot-at-the-beginning)
to prevent the GC from missing reachable objects:

```c
void dd_satb_barrier( PHB_ITEM pOldValue )
{
   if( dd_marking_in_progress() && dd_is_white( pOldValue ) )
      dd_mark_gray( pOldValue );
}
```

**Who implements**: GenerationalGC (Phase D) implements the generational
barrier. Future concurrent marking adds the SATB barrier. Both are inserted
at every `hb_itemCopy()`, `hb_arraySet()`, `hb_hashAdd()`, and equivalent
`dd_*` functions.

---

## 3. Safepoint Coordination

**What**: Points in compiled code where the mutator can be safely suspended
for GC. At a safepoint, all GC references are described by stack maps and
no object is in an inconsistent state.

**Why**: The GC needs to stop the mutator to trace roots (even in an
incremental collector, some phases require a brief pause). Without safepoints,
the GC cannot stop the mutator in a consistent state.

**Safepoint placement**:
- Loop back-edges (every loop iteration checks the flag)
- Function entry (every call checks the flag)
- Allocation sites (every `dd_*_new()` or `hb_gcAllocRaw()`)

**Implementation**:
```c
/* Safepoint poll — one load + one conditional branch */
if( *vm->pSafepointFlag )
   dd_safepoint_handler( vm );   /* suspend, let GC run, resume */
```

**Overhead**: ~1 instruction per safepoint (load + branch-not-taken). On modern
CPUs this is essentially free when the flag is not set (branch predictor learns
the not-taken path).

**Who implements**: GenerationalGC (Phase D) installs the safepoint flag check
in the interpreter loop (already has `hb_vmThreadRequest` at `hvm.c:1382-1385`).
LLVMBackend (Phase M) emits safepoint polls in compiled code.

**Drydock-specific note**: The current interpreter already has a GC check point
at `hvm.c:1382-1385` (`if(hb_vmThreadRequest) hb_vmRequestTest()`). This is
effectively a safepoint. The contract formalizes it.

---

## 4. Inline Cache Slots as Weak GC Roots

**What**: Inline caches (ICs) store references to classes and method pointers
observed at call sites. These references must be visible to the GC but must
not prevent collection of dead classes.

**Why**: If an IC holds a strong reference to a class, that class can never be
GC'd — even if all instances and all code referencing it are gone. This leaks
memory proportional to the number of call sites × classes observed.

**Solution**: IC slots are **weak GC roots**. During GC marking:
1. The GC walks all IC slots
2. If a slot references a white (unreachable) object, the slot is cleared
   (set to empty/megamorphic)
3. The IC transitions to megamorphic state and will re-specialize on the
   next call

**Who implements**: InlineCaching (Phase L) manages IC slots. The GC weak
reference processing phase (in GenerationalGC or future concurrent GC)
clears dead IC entries.

**Drydock-specific note**: Harbour classes are never truly "collected" in the
current implementation — the class registry (`s_pClasses` in `classes.c`)
holds them permanently. If DrydockAPI enables dynamic class loading/unloading
in the future, IC weak references become critical.

---

## 5. Deoptimization Safety

**What**: When JIT-compiled code makes a speculative assumption that turns out
to be false (e.g., "this variable is always NUMERIC"), it must **deoptimize**:
abandon the compiled frame and resume in the interpreter.

**Why**: During deoptimization, objects referenced only in the compiled frame
(registers, stack slots) must be transferred to the interpreter frame. If a GC
runs during this transfer, those objects must not be collected.

**Solution**: Every safepoint that is also a potential deoptimization point
includes a **full frame state** in its stack map — enough information to
reconstruct the interpreter's stack, locals, and PC from the compiled frame.

**Deoptimization protocol**:
1. Compiled code detects assumption violation (e.g., type guard fails)
2. Call `dd_deoptimize( vm, safepoint_id )`
3. `dd_deoptimize()` reads the stack map for `safepoint_id`
4. Reconstructs interpreter frame: locals, stack, PC
5. Transfers all GC references to the interpreter frame (now traceable by GC)
6. Resumes execution in the interpreter at the corresponding pcode offset

**Who implements**: LLVMBackend (Phase M) emits deoptimization metadata.
The VM's deoptimization handler (new code in `hvm.c` or `ddapi.c`)
reconstructs interpreter state.

**Drydock-specific note**: Because the `dd_*` API uses handles, deoptimization
is simpler — handle values (indices) are transferred directly. No pointer
adjustment is needed. The handle table ensures the referenced objects remain
alive.

---

## How DrydockAPI Fits

The `dd_*` API (DrydockAPI blueprint, Phase A1) is the **extension boundary**
that separates GC-aware code from GC-unaware code:

| Code Type | Uses | GC Interaction |
|-----------|------|----------------|
| PRG code | Pcode (via VM) | Automatically GC-safe — VM manages everything |
| dd_* extensions | Handles | GC-safe — handles are indirect, table is a root |
| hb_* extensions | Raw pointers (pinned) | GC-constrained — pinned objects can't move |
| JIT-compiled code | Handles + stack maps | GC-cooperative — safepoints + maps |
| VM internals | Raw pointers | GC-aware — written by VM authors with full knowledge |

The handle table is the central data structure that makes all 5 integration
points work:
1. **Stack maps** reference handles (indices), not addresses
2. **Write barriers** fire on `dd_array_set()` / `dd_hash_set()`
3. **Safepoints** in `dd_*` functions are automatic (every allocation is a
   safepoint)
4. **IC slots** use weak handles via `dd_weak_handle()`
5. **Deoptimization** transfers handles (stable indices, not fragile pointers)

---

## References

- [DrydockAPI Blueprint](../../blueprints/DrydockAPI(SUBSYSTEM)/BRIEF.md)
- [GenerationalGC Blueprint](../../blueprints/GenerationalGC(SUBSYSTEM)/BRIEF.md)
- [InlineCaching Blueprint](../../blueprints/InlineCaching(FEATURE)/BRIEF.md)
- [LLVMBackend Blueprint](../../blueprints/LLVMBackend(FEATURE)/BRIEF.md)
- [RemoveGIL Blueprint](../../blueprints/RemoveGIL(SUBSYSTEM)/BRIEF.md)
