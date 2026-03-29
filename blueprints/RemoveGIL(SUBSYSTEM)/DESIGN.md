# DESIGN -- RemoveGIL (SUBSYSTEM)

## 1. Current State

Single global VM lock (HB_VM_LOCK/HB_VM_UNLOCK in hbthread.h). Only one thread executes pcode at a time. Other threads wait. This is the GIL (Global Interpreter Lock).

Shared data structures protected by the GIL:
- Symbol table (hb_dynsym* in dynsym.c)
- Class registry (s_pClasses[] in classes.c)
- Statics array
- Module symbol tables
- GC mark state

## 2. Concurrency Model: Lock-Free Reads + Mutex Writes

### 2.1 Design Choice

NOT per-object locks (too much overhead, deadlock risk).
NOT full lock-free (too complex for all data structures).

Hybrid: lock-free READS of shared structures + mutex-protected WRITES.

### 2.2 Symbol Table (dynsym.c)

- Reads: lock-free. The dynsym array is sorted and append-only.
  New symbols are added at the end, then the array is re-sorted.
  Read-copy-update (RCU): readers see a consistent snapshot.
  Writers create a new array, copy, sort, atomic-swap the pointer.
- Writes: global dynsym mutex (rare — only new symbol registration)

### 2.3 Class Registry (classes.c)

- s_pClasses[]: same RCU pattern as dynsym. Readers get stable pointer.
  New classes append to a new copy, atomic-swap.
- Method tables: IMMUTABLE after class creation. No lock needed for reads.
  EXTEND CLASS creates a new method table copy, atomic-swaps.
  CLASS.uiVersion incremented atomically (for inline cache invalidation).

Clarification on RCU + uiVersion: EXTEND CLASS creates a NEW CLASS struct
copy. The old struct is frozen (immutable). The new struct has version+1.
The s_pClasses[] array pointer is atomic-swapped to point to the new array
containing the new CLASS pointer. Inline caches compare (class_handle, version)
— if the class pointer changed (RCU swap), the cached version mismatches
and the cache is invalidated. uiVersion is NEVER modified in place.

- DDClass singletons: created under lock, then immutable. Thread-safe.

### 2.4 Per-Thread Structures

- Each thread gets its own: VM stack, stack frames, local variables
- Thread-local allocation pool (nursery) from GenerationalGC
- No sharing of stack/frame data between threads

### 2.5 Object Access

- Objects themselves are NOT locked by default
- SYNC methods use per-object mutex (existing Harbour feature, unchanged)
- For unsynchronized access: programmer responsibility (same as Java/Go)
- Atomic reference counting for thread-safe object sharing (when passing between threads)

### 2.6 Memory Ordering

- Acquire/release semantics for pointer swaps (RCU)
- Sequential consistency NOT required (too expensive)
- Platform-specific: use __atomic_* builtins (GCC/Clang), _InterlockedCompareExchange (MSVC)

### 2.7 RCU Pseudocode for Symbol Table

```c
/* Writer (rare — only new symbol registration) */
void hb_dynsymRegister_RCU( const char * szName )
{
   hb_threadMutexLock( s_dynsymMutex );    /* exclusive write lock */

   PHB_DYNS * pNewTable = hb_xgrab( (s_uiDynSymCount + 1) * sizeof(PHB_DYNS) );
   memcpy( pNewTable, s_pDynSymTable, s_uiDynSymCount * sizeof(PHB_DYNS) );
   pNewTable[ s_uiDynSymCount ] = create_new_symbol( szName );
   sort_table( pNewTable, s_uiDynSymCount + 1 );

   /* Atomic swap — readers see either old or new, never partial */
   __atomic_store_n( &s_pDynSymTable, pNewTable, __ATOMIC_RELEASE );
   __atomic_store_n( &s_uiDynSymCount, s_uiDynSymCount + 1, __ATOMIC_RELEASE );

   /* Old table freed after grace period (all readers done) */
   hb_rcu_defer_free( pOldTable );

   hb_threadMutexUnlock( s_dynsymMutex );
}

/* Reader (frequent — every symbol lookup) */
PHB_DYNS hb_dynsymFind_RCU( const char * szName )
{
   /* No lock needed — atomic read of consistent snapshot */
   PHB_DYNS * pTable = __atomic_load_n( &s_pDynSymTable, __ATOMIC_ACQUIRE );
   HB_SIZE nCount = __atomic_load_n( &s_uiDynSymCount, __ATOMIC_ACQUIRE );

   return binary_search( pTable, nCount, szName );
}
```

## 3. GC Integration

- GenerationalGC required — per-thread nurseries eliminate allocation contention
- Stop-the-world for major GC only (minor GC is per-thread)
- Write barriers are thread-local (no contention on barrier fast path)

## 4. Files Modified

- src/vm/hbthread.c — Replace GIL with fine-grained locks
- src/common/dynsym.c — RCU for symbol table
- src/vm/classes.c — RCU for class registry, atomic uiVersion
- src/vm/hvm.c — Per-thread VM stack, remove GIL acquire/release around pcode execution
- src/vm/garbage.c — Thread-safe GC with per-thread nurseries

## 5. Compatibility

Thread-safe behavior should be identical for single-threaded code. Multi-threaded code gains true parallelism. SYNC methods unchanged.

---

[<- Index](../INDEX.md) · [Map](../MAP.md) · [BRIEF](BRIEF.md) · **DESIGN**
