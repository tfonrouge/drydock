# BRIEF -- DrydockAPI (SUBSYSTEM)

## Identity

| Field | Value |
|-------|-------|
| **Name** | DrydockAPI |
| **Mode** | SUBSYSTEM |
| **Tier** | 1 — Fix the Foundation (late) |
| **Phase** | A1 |
| **Component** | VM — `src/vm/ddapi.c` (new), `include/hbddapi.h` (new), `src/vm/garbage.c` |
| **Status** | PLANNING |

---

## 1. Motivation

Every modernization goal in Drydock's roadmap hits the same wall: the Harbour
C extension API (`hb_*` functions in `include/hbapi.h`) exposes **raw
`PHB_ITEM*` pointers** into GC-managed memory.

| Goal | How `hb_*` API blocks it |
|------|--------------------------|
| Moving/copying GC | `PHB_ITEM` pointers into array buffers become dangling |
| Concurrent GC | C extensions read objects while GC modifies them — data races |
| JIT object layout optimization | C code assumes `HB_ITEM` struct layout (`sizeof`, union offsets) |
| Register-based pcode | C extensions push/pop the operand stack directly |
| NaN-boxing / pointer tagging | Internal representation change breaks all `PHB_ITEM` consumers |

The current API surface is massive: **433 exported functions** in `hbapi.h`
alone, plus `hbapicls.h`, `hbapiitm.h`, `hbapierr.h`, `hbapicdp.h`, etc.
These are used by 70+ contrib modules and an unknown number of external
extensions.

**The core insight:** PRG code never touches the C API. It compiles to pcode,
which the VM executes. The PRG→pcode contract is the stability boundary — not
the C API. Drydock can change its internals freely as long as pcode semantics
are preserved.

---

## 2. The Three-Layer Model

```
┌──────────────────────────────────────────────────┐
│               PRG Code (100% compat)              │
│  Compiles to pcode. Never touches C API.          │
│  Always GC-safe. This contract never breaks.      │
├──────────────────────────────────────────────────┤
│            Drydock API (dd_*)                      │
│  Handle-based. GC-safe by construction.            │
│  New extensions use this. Stable ABI.              │
├──────────────────────────────────────────────────┤
│         Harbour API (hb_*) — transitional          │
│  Raw pointers. Works under constraints:            │
│  - Objects pinned during C extension access         │
│  - Non-moving allocation for pinned objects         │
│  - Deprecated: new code must use dd_*              │
├──────────────────────────────────────────────────┤
│               VM Internals                         │
│  Free to change. GC strategy, object layout,       │
│  dispatch mechanism — only accessed via dd_*/hb_*  │
└──────────────────────────────────────────────────┘
```

**PRG layer**: 100% backward compatible, forever. The Compatibility Covenant
applies here.

**dd_* layer**: New, handle-based API. All object references are opaque
`DD_HANDLE` values — indices into a VM-managed handle table. The GC can move,
compact, or reorganize objects freely because handles are indirect. This is the
API new extensions, contrib modules, and embedding applications use.

**hb_* layer**: The existing 433+ function API. Continues to work under
constraints: objects accessed via `hb_*` functions are automatically pinned
(non-moving) for the duration of the C extension call. New code should not use
this API. Eventually, `hb_*` functions become thin wrappers around `dd_*`.

---

## 3. Core dd_* API (Phase 1 — 10 functions)

```c
/* === Scope management === */
DD_SCOPE   dd_scope_enter( DD_VM * vm );
void       dd_scope_leave( DD_VM * vm, DD_SCOPE scope );

/* === Value creation === */
DD_HANDLE  dd_number( DD_VM * vm, double value );
DD_HANDLE  dd_string( DD_VM * vm, const char * str, HB_SIZE len );
DD_HANDLE  dd_logical( DD_VM * vm, HB_BOOL value );
DD_HANDLE  dd_array_new( DD_VM * vm, HB_SIZE len );
DD_HANDLE  dd_nil( DD_VM * vm );

/* === Value access === */
double     dd_to_number( DD_VM * vm, DD_HANDLE handle );
const char * dd_to_string( DD_VM * vm, DD_HANDLE handle, HB_SIZE * pLen );

/* === Array operations === */
DD_HANDLE  dd_array_get( DD_VM * vm, DD_HANDLE array, HB_SIZE index );
void       dd_array_set( DD_VM * vm, DD_HANDLE array, HB_SIZE index,
                         DD_HANDLE value );

/* === Function registration === */
void       dd_register_func( DD_VM * vm, const char * name,
                             DD_CFUNC pFunc );

/* === Return value === */
void       dd_return( DD_VM * vm, DD_HANDLE value );
```

**Design principles:**
- Every function takes `DD_VM *` as first argument (no global state)
- Handles created within a scope are automatically released on `dd_scope_leave()`
- `dd_to_string()` returns a pointer valid only until the next GC point — copy
  if you need to keep it
- `dd_register_func()` registers a C function callable from PRG code

**Extension example:**
```c
/* A simple extension: UPPER() implemented via dd_* API */
static void dd_upper( DD_VM * vm )
{
   DD_SCOPE scope = dd_scope_enter( vm );

   DD_HANDLE arg = dd_param( vm, 1 );
   HB_SIZE len;
   const char * str = dd_to_string( vm, arg, &len );

   char * result = dd_alloc( vm, len + 1 );
   for( HB_SIZE i = 0; i < len; i++ )
      result[ i ] = toupper( str[ i ] );
   result[ len ] = '\0';

   dd_return( vm, dd_string( vm, result, len ) );
   dd_free( vm, result );

   dd_scope_leave( vm, scope );
}
```

---

## 4. Handle Table Design

```c
typedef struct {
   HB_ITEM *   pItem;       /* pointer to the actual HB_ITEM (internal) */
   HB_UINT     generation;  /* incremented on release — detects stale handles */
} DD_SLOT;

typedef HB_UINT  DD_HANDLE;  /* index into slot table + generation */
```

A `DD_HANDLE` encodes a slot index (lower bits) and a generation counter
(upper bits). When a handle is released, the slot's generation is incremented.
Attempting to use a stale handle (generation mismatch) triggers a runtime error
instead of use-after-free. This is the same pattern used by ECS frameworks
(generational indices) and is proven in production.

**GC interaction:** During GC marking, the handle table is a root source. Every
live slot (generation matches) is marked as a GC root. When the GC moves an
object (future moving GC), it updates `pItem` in the slot — the handle value
itself (the index) never changes.

---

## 5. Transitional hb_* Strategy

### Phase 1: Constraints (immediate)

The existing `hb_gcLock()` / `hb_gcUnlock()` mechanism already pins GC blocks.
Extend this so that:

1. Every `HB_FUNC()` C extension entry point implicitly enters a "legacy scope"
   that pins objects accessed via `hb_*` functions
2. The GC treats pinned objects as non-moving (old gen, mark-and-sweep only)
3. No C extension code changes needed — existing code continues to work

### Phase 2: Deprecation warnings (0.1.0)

When compiling C extensions that use `hb_*` functions marked as deprecated,
emit compiler warnings pointing to the `dd_*` equivalent.

### Phase 3: hb_* as dd_* wrappers (0.2.0)

Reimplement `hb_*` functions on top of `dd_*`. For example:
```c
/* hb_arrayGet() becomes a dd_* wrapper */
PHB_ITEM hb_arrayGet( PHB_ITEM pArray, HB_SIZE nIndex )
{
   /* Pin the result so the raw pointer stays valid */
   DD_HANDLE h = dd_array_get( dd_vm_current(), /* ... */ );
   return dd_pin_item( dd_vm_current(), h );  /* returns raw pointer, pinned */
}
```

This inverts the dependency: `dd_*` is the real API, `hb_*` is the shim.

---

## 6. Affected Files

| File | Lines | Change |
|------|-------|--------|
| `include/hbddapi.h` | NEW ~200 | dd_* function declarations, DD_HANDLE/DD_SCOPE/DD_VM types |
| `src/vm/ddapi.c` | NEW ~500 | Handle table, scope management, core dd_* implementations |
| `src/vm/garbage.c` | ~814 | Mark handle table as GC root source; pinning protocol |
| `include/hbapi.h` | ~1,257 | Deprecation markers on hb_* functions (Phase 2) |
| `src/harbour.def` | ~3,800 | Export dd_* symbols |

## 7. Dependencies

| Dependency | Status | Notes |
|------------|--------|-------|
| DrydockObject (Phase A0) | STABLE | dd_* API operates on DrydockObject value model |
| ScalarClasses (Phase B) | STABLE | Scalar methods available via handles |

## 8. What This Unlocks

| Blueprint | How DrydockAPI enables it |
|-----------|--------------------------|
| GenerationalGC (Phase D) | Moving young gen — handles survive object relocation |
| RemoveGIL (Phase J) | Handle table is thread-safe; no raw pointers across threads |
| LLVMBackend (Phase M) | JIT-compiled code uses handles; object layout can change |
| InlineCaching (Phase L) | IC slots registered as weak handles; GC can invalidate |

## 9. Estimated Scope

| Phase | Effort | Description |
|-------|--------|-------------|
| A1.1 | 2 weeks | Handle table + scope management + core 10 functions |
| A1.2 | 1 week | Function/class registration API |
| A1.3 | 2 weeks | Migrate hbjson contrib as proof of concept |
| A1.4 | 1 week | hb_* compatibility shim (hb_* on top of dd_*) |
| **Total** | **6 weeks** | |

## 10. Compatibility

See [COMPAT.md](COMPAT.md) for full analysis. Summary:

- **PRG level**: 100% compatible — PRG code never touches the C API
- **dd_* API**: New API, no backward compatibility concerns
- **hb_* API**: Transitional — continues to work under pinning constraints;
  deprecated for new code; eventually becomes dd_* wrapper

---

[<- Index](../INDEX.md) · [Map](../MAP.md) · [DESIGN](DESIGN.md) · [COMPAT](COMPAT.md) · **BRIEF**
