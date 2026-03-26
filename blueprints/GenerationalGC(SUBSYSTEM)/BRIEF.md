# BRIEF -- GenerationalGC (SUBSYSTEM)

## Identity

| Field | Value |
|-------|-------|
| **Name** | GenerationalGC |
| **Mode** | SUBSYSTEM |
| **Tier** | 1 — Fix the Foundation |
| **Phase** | D |
| **Component** | VM — `src/vm/garbage.c`, `src/vm/hvm.c` |
| **Status** | PLANNING |

---

## 1. Motivation

Harbour's garbage collector (`garbage.c`, 814 lines) is a **non-generational,
non-incremental, stop-the-world mark-and-sweep** collector. Every collection:

1. Suspends all threads via `hb_vmSuspendThreads()` (`garbage.c:581`)
2. Walks the entire heap — every `HB_GARBAGE` block ever allocated
3. Marks reachable blocks by toggling a flag bit (`s_uUsedFlag` XOR trick)
4. Sweeps unmarked blocks into a deletion list
5. Calls cleanup functions on deleted blocks
6. Resumes all threads

**The problem**: collection time is O(total heap objects), not O(live objects).
For applications with large working sets (database apps with open result sets,
GUI apps with widget trees), GC pauses grow linearly with heap size and are
unpredictable.

The generational hypothesis — "most objects die young" — is well-established
(measured across Java, .NET, Python, Ruby, Lua, V8). A young generation that
collects frequently and cheaply would eliminate >90% of full-heap scans.

---

## 2. Current GC Architecture

### Allocation

```c
/* garbage.c — simplified */
PHB_GARBAGE hb_gcAllocate( HB_SIZE nSize, const HB_GC_FUNCS * pFuncs )
{
   PHB_GARBAGE pAlloc = ( PHB_GARBAGE ) hb_xgrab( nSize + sizeof( HB_GARBAGE ) );
   pAlloc->pFuncs = pFuncs;
   pAlloc->locked = 0;
   pAlloc->used = s_uUsedFlag;
   HB_GC_LOCK();
   /* link into global list */
   pAlloc->pNext = s_pCurrBlock;
   s_pCurrBlock->pPrev = pAlloc;
   s_pCurrBlock = pAlloc;
   s_ulBlocks++;
   HB_GC_UNLOCK();
   return pAlloc;
}
```

- Every allocation contends on `HB_GC_LOCK()` (spinlock or mutex)
- All blocks live in a single doubly-linked list (`s_pCurrBlock`)
- No segregation by age, size, or allocation site

### Collection Trigger

```c
if( s_ulBlocks > s_ulBlocksMarked + HB_GC_AUTO )
   hb_gcCollectAll();
```

Triggered when allocation count exceeds last-collection count + threshold.
No adaptive sizing, no incremental progress between collections.

### Mark Phase

Uses a clever bit-flip strategy: toggle `s_uUsedFlag` each cycle. Blocks
whose `used` field matches `s_uUsedFlag` are alive. This avoids the cost of
clearing all mark bits at cycle start — but still requires visiting every
reachable object.

### Sweep Phase

Linear scan of the global block list. Unvisited blocks (wrong `used` flag)
are unlinked and moved to a deletion list. Cleanup functions called. Reference
cycles detected post-hoc.

---

## 3. Proposed Change: Two-Generation Collector

### 3.1 Architecture

```
                    ┌──────────────────────────┐
                    │        Old Generation     │
                    │   (existing M&S collector) │
                    │   Collected infrequently   │
                    └──────────┬───────────────┘
                               │ promotion
                    ┌──────────┴───────────────┐
                    │       Young Generation    │
                    │   (new: copy collector)    │
                    │   Collected frequently     │
                    │   Semi-space or bump-alloc │
                    └───────────────────────────┘
```

- **Young generation**: bump-pointer allocation into a fixed-size nursery
  (e.g., 256KB-1MB). No lock contention for allocation. Collected by copying
  live objects to a survivor space or promoting to old generation.
- **Old generation**: the existing mark-and-sweep collector, unchanged.
  Triggered less frequently (only when old-gen threshold exceeded or
  young-gen promotion fills it).

### 3.2 Write Barriers

When an old-generation object stores a reference to a young-generation object,
we must record this in a **remembered set** so minor GC can find all young
roots without scanning the entire old generation.

```c
#define HB_GC_WRITE_BARRIER( pOld, pYoung )          \
   do {                                                \
      if( HB_GC_IS_OLD( pOld ) && HB_GC_IS_YOUNG( pYoung ) ) \
         hb_gcRememberSet( pOld );                     \
   } while( 0 )
```

Write barriers must be inserted at every pointer store:
- `hb_arraySet()` / `hb_arrayAdd()` — array element assignment
- `hb_hashAdd()` — hash table insertion
- `hb_itemCopy()` / `hb_itemMove()` — item assignment
- `hb_vmPush*()` — stack pushes (stack is always a root, so these may not
  need barriers — TBD)
- `hb_codeblockEvaluate()` — detached variable capture

This is the most invasive part of the change. Every pointer store in `itemapi.c`,
`arrays.c`, `hash.c`, `codeblck.c`, and parts of `hvm.c` needs a barrier call.

### 3.3 Nursery Allocation

```c
/* Fast path: bump-pointer allocation */
PHB_GARBAGE hb_gcAllocate( HB_SIZE nSize, const HB_GC_FUNCS * pFuncs )
{
   HB_SIZE nTotal = nSize + sizeof( HB_GARBAGE );

   if( HB_LIKELY( s_pNurseryFree + nTotal <= s_pNurseryEnd ) )
   {
      /* No lock needed — nursery is per-thread or single-threaded */
      PHB_GARBAGE pAlloc = ( PHB_GARBAGE ) s_pNurseryFree;
      s_pNurseryFree += nTotal;
      pAlloc->pFuncs = pFuncs;
      pAlloc->used = HB_GC_YOUNG;
      return pAlloc;
   }
   /* Nursery full — trigger minor GC */
   hb_gcMinorCollect();
   /* retry */
   return hb_gcAllocate( nSize, pFuncs );
}
```

### 3.4 Minor Collection

1. Pause (short — only scan young gen + remembered set)
2. Copy live young objects to survivor space or promote to old gen
3. Update all pointers (stack, remembered set, young-gen internal refs)
4. Reset nursery bump pointer
5. Clear remembered set

Expected pause: <1ms for typical nursery sizes.

### 3.5 Promotion Policy

- Objects surviving N minor collections (e.g., N=2) get promoted to old gen
- Large objects (>nursery threshold) allocated directly in old gen
- This avoids copying large buffers repeatedly

---

## 4. Affected Files

| File | Lines | Change |
|------|-------|--------|
| `src/vm/garbage.c` | 814 | Add nursery allocator, minor GC, remembered set, promotion |
| `src/vm/hvm.c` | 12,572 | Write barriers on stack operations (if needed) |
| `src/vm/itemapi.c` | 3,038 | Write barriers on `hb_itemCopy`, `hb_itemMove` |
| `src/vm/arrays.c` | ~1,500 | Write barriers on `hb_arraySet`, `hb_arrayAdd` |
| `src/vm/hash.c` | ~2,000 | Write barriers on `hb_hashAdd` |
| `src/vm/codeblck.c` | ~800 | Write barriers on detached variable capture |
| `include/hbapi.h` | 1,257 | Add `HB_GC_YOUNG`/`HB_GC_OLD` flags to `HB_GARBAGE` |

## 5. Affected Structs

| Struct | File | Change |
|--------|------|--------|
| `HB_GARBAGE` | `include/hbapi.h` | Add generation flag (1 bit — can use existing padding or `used` field bits) |

## 6. Compatibility Stance

**Target: 100% source and ABI compatibility.**

- All public GC APIs (`hb_gcAllocate`, `hb_gcCollectAll`, `hb_gcLock`, etc.)
  retain their signatures
- `hb_gcCollectAll()` becomes "collect both generations" — same external effect
- Write barriers are internal — no API change for C extensions
- C extensions that store `PHB_ITEM` pointers in their own structs and call
  `hb_gcItemRef()` during mark phase continue to work — their items are either
  in old gen (marked normally) or young gen (found via remembered set)

## 7. Performance Stance

**Must reduce pause times. Must not regress throughput by more than 2%.**

- Write barrier overhead: 1-3 instructions per pointer store (branch + possible
  remembered-set insert). Estimated throughput cost: 1-2%.
- Minor GC pause: <1ms for 256KB nursery (vs. current 10-100ms for full sweep)
- Major GC frequency reduced by 10-50x (most garbage collected in minor GC)
- Allocation fast path: bump-pointer is faster than current `hb_xgrab` + list
  insertion + lock

## 8. Dependencies

| Dependency | Status | Notes |
|------------|--------|-------|
| RefactorHvm Phase 3 (branch hints) | PLANNING | `HB_LIKELY`/`HB_UNLIKELY` macros needed for write barrier fast path |
| ScalarClasses | PLANNING | Not required, but scalar class dispatch may add new pointer stores that need barriers |

**Blocks**: RemoveGIL (Tier 3) — generational GC with per-thread nurseries is a
prerequisite for removing the global VM lock.

## 9. Risks

| Risk | Severity | Mitigation |
|------|----------|------------|
| Missing write barriers | High — silent corruption | Audit every pointer store; debug mode that verifies barrier presence |
| Nursery too small for large apps | Medium | Configurable via `HB_GC_NURSERY_SIZE` env var |
| Promotion storms (all objects promoted) | Medium | Adaptive promotion threshold; fallback to full M&S |
| C extensions storing raw pointers | Medium | Document requirement to call `hb_gcItemRef()` or `hb_gcLock()` |

## 10. Estimated Scope

| Phase | Effort | Can Ship Independently |
|-------|--------|----------------------|
| Nursery allocator + minor GC | 2 weeks | No |
| Write barriers (all pointer stores) | 2 weeks | No |
| Remembered set implementation | 1 week | No |
| Integration + testing | 1 week | — |
| **Total** | **6 weeks** | Ships as single unit |

---

[<- Index](../INDEX.md) · [Map](../MAP.md) · **BRIEF**
