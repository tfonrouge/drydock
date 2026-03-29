# DESIGN -- DrydockAPI (SUBSYSTEM)

## 1. Current State

### 1.1 The hb_* API Surface

The Harbour C extension API is defined across multiple headers:

| Header | Exports | Purpose |
|--------|---------|---------|
| `include/hbapi.h` | 433 | Core: items, arrays, hashes, strings, GC, VM |
| `include/hbapiitm.h` | ~40 | Item manipulation |
| `include/hbapicls.h` | ~30 | Class/object system |
| `include/hbapierr.h` | ~20 | Error handling |
| `include/hbapicdp.h` | ~15 | Codepage/encoding |
| `include/hbapifs.h` | ~50 | File system |
| `include/hbapidbg.h` | ~10 | Debugger interface |

### 1.2 Raw Pointer Patterns

The most common C extension pattern exposes raw `PHB_ITEM` pointers:

```c
/* Typical hb_* usage — raw pointer into GC-managed memory */
HB_FUNC( MY_EXTENSION )
{
   PHB_ITEM pArray = hb_param( 1, HB_IT_ARRAY );   /* raw pointer to stack */
   PHB_ITEM pItem = hb_arrayGet( pArray, 1 );       /* raw pointer INTO array buffer */
   double val = hb_itemGetND( pItem );               /* dereference raw pointer */
   /* pItem is valid only because GC hasn't moved anything */
}
```

The pointer returned by `hb_arrayGet()` points directly into
`pBaseArray->pItems[index-1]` — an inline `HB_ITEM` value inside the array's
contiguous buffer (`hbapi.h:418-425`). If the GC moves the array, this pointer
becomes dangling.

### 1.3 Existing GC Safety: hb_gcLock/hb_gcUnlock

Harbour provides a pinning mechanism (`garbage.c:193-206`):

```c
void * hb_gcAllocate( HB_SIZE nSize, const HB_GC_FUNCS * pFuncs )
{
   /* ... */
   pAlloc->locked = 1;            /* starts locked — won't be collected */
   hb_gcLink( &s_pLockedBlock, pAlloc );
   /* ... */
}

void * hb_gcLock( void * pAlloc )    /* pin: GC won't touch this */
void * hb_gcUnlock( void * pAlloc )  /* unpin: GC can collect */
```

Locked blocks are on a separate linked list (`s_pLockedBlock`) and are always
treated as roots during marking. This mechanism exists but is underused — most
C extensions don't explicitly lock/unlock.

### 1.4 HB_ITEM Layout Exposure

`HB_ITEM` is a tagged union (`hbapi.h:393-415`) with 20+ struct variants.
C extensions access it directly:

```c
/* C code that depends on HB_ITEM struct layout */
if( HB_IS_STRING( pItem ) )
{
   char * str = pItem->item.asString.value;    /* direct struct access */
   HB_SIZE len = pItem->item.asString.length;  /* direct struct access */
}
```

Changing `HB_ITEM` layout (e.g., NaN-boxing, pointer tagging, adding fields)
breaks every line of code like this. The `dd_*` API hides this behind opaque
accessors.

---

## 2. Handle Table Design

### 2.1 Structure

```c
/* A slot in the handle table */
typedef struct
{
   PHB_ITEM    pItem;        /* pointer to the actual HB_ITEM (VM-internal) */
   HB_UINT     uiGeneration; /* incremented on release — detects stale handles */
} DD_SLOT;

/* The handle table — one per VM instance */
typedef struct
{
   DD_SLOT *   pSlots;       /* dynamically allocated slot array */
   HB_UINT     uiCapacity;   /* total slots allocated */
   HB_UINT     uiCount;      /* slots in use */
   HB_UINT *   pFreeList;    /* stack of free slot indices */
   HB_UINT     uiFreeTop;    /* top of free list stack */
} DD_HANDLE_TABLE;

/* A handle is a 32-bit value: lower 20 bits = slot index, upper 12 bits = generation */
typedef HB_UINT  DD_HANDLE;

#define DD_HANDLE_INDEX( h )   ( (h) & 0x000FFFFF )
#define DD_HANDLE_GEN( h )     ( (h) >> 20 )
#define DD_HANDLE_MAKE( idx, gen )  ( ( (gen) << 20 ) | ( (idx) & 0x000FFFFF ) )
#define DD_HANDLE_NIL          0xFFFFFFFF

/* Maximum 1M handles (20-bit index), 4K generations (12-bit) before wrap */
```

### 2.2 Handle Allocation

```c
DD_HANDLE dd_handle_alloc( DD_HANDLE_TABLE * pTable, PHB_ITEM pItem )
{
   HB_UINT uiIndex;

   if( pTable->uiFreeTop > 0 )
   {
      /* Recycle a freed slot */
      uiIndex = pTable->pFreeList[ --pTable->uiFreeTop ];
   }
   else
   {
      /* Grow the table */
      if( pTable->uiCount >= pTable->uiCapacity )
         dd_handle_table_grow( pTable );
      uiIndex = pTable->uiCount++;
   }

   pTable->pSlots[ uiIndex ].pItem = pItem;
   /* generation already set from previous release (or 0 for new slots) */

   return DD_HANDLE_MAKE( uiIndex, pTable->pSlots[ uiIndex ].uiGeneration );
}
```

### 2.3 Handle Dereference (with stale detection)

```c
PHB_ITEM dd_handle_deref( DD_HANDLE_TABLE * pTable, DD_HANDLE handle )
{
   HB_UINT uiIndex = DD_HANDLE_INDEX( handle );
   HB_UINT uiGen   = DD_HANDLE_GEN( handle );

   if( uiIndex >= pTable->uiCount )
      hb_errInternal( 9001, "DrydockAPI: invalid handle index", NULL, NULL );

   if( pTable->pSlots[ uiIndex ].uiGeneration != uiGen )
      hb_errInternal( 9002, "DrydockAPI: stale handle (use-after-free)", NULL, NULL );

   return pTable->pSlots[ uiIndex ].pItem;
}
```

### 2.4 Handle Release

```c
void dd_handle_release( DD_HANDLE_TABLE * pTable, DD_HANDLE handle )
{
   HB_UINT uiIndex = DD_HANDLE_INDEX( handle );

   /* Increment generation — future uses of this handle will detect staleness */
   pTable->pSlots[ uiIndex ].uiGeneration++;
   pTable->pSlots[ uiIndex ].pItem = NULL;

   /* Push index onto free list for reuse */
   pTable->pFreeList[ pTable->uiFreeTop++ ] = uiIndex;
}
```

---

## 3. Scope Management

Scopes provide automatic handle lifetime management, similar to V8's
`HandleScope` or Lua's stack discipline.

```c
typedef struct
{
   HB_UINT  uiHandleBase;    /* handle count when scope was entered */
} DD_SCOPE;

DD_SCOPE dd_scope_enter( DD_VM * vm )
{
   DD_SCOPE scope;
   scope.uiHandleBase = vm->handleTable.uiCount;
   return scope;
}

void dd_scope_leave( DD_VM * vm, DD_SCOPE scope )
{
   /* Release all handles allocated since scope entry */
   while( vm->handleTable.uiCount > scope.uiHandleBase )
   {
      DD_HANDLE h = DD_HANDLE_MAKE(
         vm->handleTable.uiCount - 1,
         vm->handleTable.pSlots[ vm->handleTable.uiCount - 1 ].uiGeneration
      );
      dd_handle_release( &vm->handleTable, h );
      vm->handleTable.uiCount--;
   }
}
```

**Nested scopes** work naturally — each scope saves the handle count at entry
and releases everything above it on exit. Inner scopes release their handles
before outer scopes.

**Root handles** (handles that survive scope exit) are created with
`dd_root_handle()` and must be explicitly released with `dd_release()`.

---

## 4. Core API Functions

### 4.1 Signatures

```c
/* --- Types --- */
typedef HB_UINT    DD_HANDLE;
typedef struct     DD_SCOPE_;   /* opaque */
typedef struct     DD_VM_;      /* opaque — wraps HB_STACK/VM state */
typedef void       (* DD_CFUNC)( DD_VM * vm );

/* --- VM context --- */
DD_VM *    dd_vm_current( void );

/* --- Scope --- */
DD_SCOPE   dd_scope_enter( DD_VM * vm );
void       dd_scope_leave( DD_VM * vm, DD_SCOPE scope );

/* --- Value creation (handles auto-released on scope exit) --- */
DD_HANDLE  dd_nil( DD_VM * vm );
DD_HANDLE  dd_number( DD_VM * vm, double value );
DD_HANDLE  dd_integer( DD_VM * vm, HB_MAXINT value );
DD_HANDLE  dd_string( DD_VM * vm, const char * str, HB_SIZE len );
DD_HANDLE  dd_logical( DD_VM * vm, HB_BOOL value );
DD_HANDLE  dd_array_new( DD_VM * vm, HB_SIZE len );
DD_HANDLE  dd_hash_new( DD_VM * vm );

/* --- Value access --- */
double     dd_to_number( DD_VM * vm, DD_HANDLE handle );
HB_MAXINT  dd_to_integer( DD_VM * vm, DD_HANDLE handle );
const char * dd_to_string( DD_VM * vm, DD_HANDLE handle, HB_SIZE * pLen );
HB_BOOL    dd_to_logical( DD_VM * vm, DD_HANDLE handle );
HB_SIZE    dd_len( DD_VM * vm, DD_HANDLE handle );

/* --- Type checking --- */
HB_BOOL    dd_is_nil( DD_VM * vm, DD_HANDLE handle );
HB_BOOL    dd_is_number( DD_VM * vm, DD_HANDLE handle );
HB_BOOL    dd_is_string( DD_VM * vm, DD_HANDLE handle );
HB_BOOL    dd_is_array( DD_VM * vm, DD_HANDLE handle );
HB_BOOL    dd_is_object( DD_VM * vm, DD_HANDLE handle );

/* --- Array --- */
DD_HANDLE  dd_array_get( DD_VM * vm, DD_HANDLE array, HB_SIZE index );
void       dd_array_set( DD_VM * vm, DD_HANDLE array, HB_SIZE index,
                         DD_HANDLE value );

/* --- Parameters and return --- */
DD_HANDLE  dd_param( DD_VM * vm, int iParam );
int        dd_param_count( DD_VM * vm );
void       dd_return( DD_VM * vm, DD_HANDLE value );
void       dd_return_nil( DD_VM * vm );

/* --- Function registration --- */
void       dd_register_func( DD_VM * vm, const char * szName,
                             DD_CFUNC pFunc );

/* --- Root handles (survive scope exit) --- */
DD_HANDLE  dd_root( DD_VM * vm, DD_HANDLE handle );
void       dd_release( DD_VM * vm, DD_HANDLE handle );
```

### 4.2 Error Handling

All `dd_*` functions that can fail follow this convention:
- Type mismatch on access (e.g., `dd_to_number()` on a string) raises a
  Harbour runtime error (`EG_ARG`) — consistent with existing Harbour behavior
- Invalid/stale handles raise `EG_INTERNAL` with a descriptive message
- No NULL returns — errors are always signaled via the Harbour error system

---

## 5. Transitional hb_* Strategy

### 5.1 Pinning Protocol

When a `HB_FUNC()` C extension is called, the VM implicitly enters a "legacy
scope" that pins objects on the stack and in parameters. The protocol:

1. `HB_FUNC` entry → GC marks all stack items and parameters as pinned
2. Any `PHB_ITEM` obtained via `hb_param()`, `hb_arrayGet()`, etc. is valid
   for the duration of the `HB_FUNC` call
3. `HB_FUNC` return → pins are released

This is **already effectively true** — the current GC is stop-the-world and
only runs between pcode instructions, never during C extension execution. The
pinning protocol formalizes this guarantee so future concurrent/moving GC can
respect it.

### 5.2 hb_* as dd_* Wrappers (Phase A1.4)

Once the `dd_*` API is stable, `hb_*` functions become thin wrappers:

```c
/* hb_arrayGet() — wrapper that returns pinned raw pointer */
PHB_ITEM hb_arrayGet( PHB_ITEM pArray, HB_SIZE nIndex )
{
   DD_VM * vm = dd_vm_current();
   DD_HANDLE hArray = dd_handle_from_item( vm, pArray );  /* wrap raw ptr */
   DD_HANDLE hItem = dd_array_get( vm, hArray, nIndex );
   return dd_pin_as_item( vm, hItem );  /* pin and return raw pointer */
}
```

The `dd_pin_as_item()` function:
1. Marks the handle as a root (won't be scope-released)
2. Returns the raw `PHB_ITEM` from the slot
3. The item stays pinned until the legacy scope exits (end of `HB_FUNC`)

### 5.3 Migration Helpers

Provide convenience macros for common migration patterns:

```c
/* Old pattern */
PHB_ITEM pItem = hb_param( 1, HB_IT_STRING );
const char * str = hb_itemGetCPtr( pItem );

/* New pattern — one-liner */
const char * str = dd_param_string( vm, 1, &len );
```

---

## 6. GC Integration

### 6.1 Handle Table as Root Source

During GC marking (`hb_gcCollectAll` in `garbage.c:574-716`), the handle table
is walked as an additional root source:

```c
/* Add to root marking phase in garbage.c */
void hb_gcMarkHandleTable( DD_HANDLE_TABLE * pTable )
{
   HB_UINT i;
   for( i = 0; i < pTable->uiCount; i++ )
   {
      if( pTable->pSlots[ i ].pItem != NULL )
      {
         hb_gcItemRef( pTable->pSlots[ i ].pItem );
      }
   }
}
```

### 6.2 Enabling Moving GC (Future)

When `GenerationalGC` (Phase D) implements a moving young gen, the handle
table provides the indirection needed:

1. GC copies a young-gen object to old gen (or to the other semi-space)
2. GC walks the handle table and updates `pSlots[i].pItem` for every handle
   pointing to the moved object
3. Extension code uses handles — the handle value (index + generation) doesn't
   change, only the internal `pItem` pointer changes
4. Raw `PHB_ITEM` pointers from the hb_* shim are pinned — the GC skips them

**This is why DrydockAPI must come before GenerationalGC in the roadmap.**

### Handle Table GC Sync

When GenerationalGC moves an object (young → old promotion or semi-space copy):
1. The GC walks the handle table linearly (O(n) where n = live handles)
2. For each handle whose pItem points to the moved object, update pItem
   to the new location
3. The handle table is a GC ROOT — all live handles keep their objects alive
4. Weak handles (dd_weak_handle) are NOT updated — they become NULL on collection
5. Performance: handle table walk is O(live_handles), not O(heap_size)

### 6.3 Weak Handles (for InlineCaching)

`dd_weak_handle()` creates a handle that does not prevent GC collection. If
the referenced object is collected, the weak handle becomes `DD_HANDLE_NIL`.
This is used by inline caches (Phase L) to cache class/method references
without keeping dead classes alive.

---

## 7. JIT Integration (Future)

When `LLVMBackend` (Phase M) generates native code, JIT-compiled functions
use handles for all object access:

```llvm
; JIT-compiled array access — uses dd_array_get (handle-based)
%handle = call i32 @dd_array_get(%vm, %arr_handle, i64 1)
%value  = call double @dd_to_number(%vm, %handle)
```

**Stack maps** at safepoints describe which registers/stack slots contain
handles. The GC walks these during marking.

**Deoptimization** from JIT to interpreter transfers handle values (not raw
pointers) — handles remain valid across the transition because they're
indices, not addresses.

See [JIT-GC Contract](../../doc/drydock/jit-gc-contract.md) for the full
integration specification.

---

## 8. Alternatives Considered

### 8.1 Keep hb_* API, add GC constraints only

Don't create a new API — just add pinning rules to the existing one.

**Rejected**: This permanently limits the GC to non-moving strategies. Every
future optimization (moving young gen, compaction, NaN-boxing) remains blocked
by raw pointers. The fundamental problem is that `PHB_ITEM` is a raw address,
not an indirection — no amount of constraints changes this.

### 8.2 Handle-based API replacing all of hb_*

Rewrite every hb_* function as dd_* and remove hb_* entirely.

**Rejected**: 433+ functions, 70+ contrib modules, unknown external extensions.
The migration is too large for a single phase. The transitional approach (hb_*
as dd_* wrappers) achieves the same end state incrementally.

### 8.3 Separate embedding API only

Create dd_* only for embedding (calling Drydock from C/Zig), keep hb_* for
extensions (called from Drydock).

**Rejected**: The GC problem exists in both directions. Extensions hold raw
pointers too. A half-measure doesn't unblock the GC improvements.

---

[<- Index](../INDEX.md) · [Map](../MAP.md) · [BRIEF](BRIEF.md) · [COMPAT](COMPAT.md) · **DESIGN**
