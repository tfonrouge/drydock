# COMPAT -- DrydockAPI (SUBSYSTEM)

## Compatibility Target

- **PRG level**: 100% source compatibility. PRG code never touches the C API.
  No PRG program changes behavior because of DrydockAPI.
- **dd_* API**: New API — no backward compatibility concerns.
- **hb_* API**: Transitional. Continues to work under pinning constraints.
  Deprecated for new code. Eventually becomes dd_* wrappers.

---

## Compatibility Covenant

All 7 rules from `doc/drydock/vision.md` are satisfied:

| Rule | Satisfied? | Notes |
|------|-----------|-------|
| 1. `ValType()` never changes | Yes | dd_* API doesn't affect PRG-level semantics |
| 2. `Len()` always returns bytes | Yes | No string semantics change |
| 3. `HB_IS_OBJECT()` returns `.F.` for scalars | Yes | Internal macro, not part of dd_* |
| 4. New keywords are context-sensitive | N/A | No new keywords |
| 5. New warnings require explicit opt-in | Yes | hb_* deprecation warnings require `-w3` |
| 6. User-defined methods shadow scalar class methods | Yes | No dispatch change |
| 7. ABI breaks gated behind pcode version bump | Yes | No pcode change; C API change is additive |

---

## Fracture Analysis

### Fracture 1: hb_* Deprecation Warnings — Risk: NONE (opt-in)

**What changes**: C extensions compiled with `-w3` (or future Drydock compiler
flag) see deprecation warnings when using hb_* functions that have dd_*
equivalents.

**Who is affected**: C extension authors who compile with high warning levels.

**Discoverability**: Compile time — explicit warnings with migration hints.

**Mitigation**: Warnings are opt-in. No warning at default warning level.

### Fracture 2: GC Behavior Under Pinning — Risk: LOW

**What changes**: Objects accessed via hb_* functions are implicitly pinned
during C extension execution. The GC skips pinned objects during young gen
collection, treating them as old gen.

**Who is affected**: No one — this formalizes the existing behavior (GC never
runs during C extension calls in the current stop-the-world model).

**Discoverability**: Invisible — behavior is identical to current.

**Mitigation**: The pinning protocol is designed to match the existing GC
contract exactly. Only a future concurrent GC would make pinning semantically
meaningful, and by then extensions should have migrated to dd_*.

### Fracture 3: HB_FUNC Scope Boundary — Risk: LOW

**What changes**: The VM formally guarantees that raw `PHB_ITEM` pointers
from `hb_param()`, `hb_arrayGet()`, etc. are valid only within the
`HB_FUNC()` call that obtained them. Storing them in global variables or
returning them as function results is undefined behavior.

**Who is affected**: C extensions that store `PHB_ITEM` pointers in global/
static variables. This is already a latent bug (the pointed-to item can be
overwritten on the next VM call), but it happens to work in the current
single-threaded, non-moving GC.

**Discoverability**: Runtime — use-after-free or incorrect values. Same
symptoms as today's latent bugs.

**Mitigation**: Document the scope rule. Provide `dd_root()` for handles
that must outlive a scope. Audit contrib modules for global `PHB_ITEM`
storage.

### Fracture 4: sizeof(DD_HANDLE) vs sizeof(PHB_ITEM) — Risk: NONE

**What changes**: Extensions using dd_* API store `DD_HANDLE` (4 bytes)
instead of `PHB_ITEM` (8 bytes on 64-bit). Data structures sized by
`sizeof(PHB_ITEM)` would be wrong for handles.

**Who is affected**: Only new code using dd_* — and it would naturally use
`sizeof(DD_HANDLE)`. No existing code affected.

---

## Migration Guide

### Step 1: Identify hb_* Usage

```bash
grep -rn "hb_param\|hb_arrayGet\|hb_itemGet\|hb_ret" my_extension.c
```

### Step 2: Wrap in Scope

```c
/* Before */
HB_FUNC( MY_FUNC )
{
   PHB_ITEM pArg = hb_param( 1, HB_IT_STRING );
   const char * str = hb_itemGetCPtr( pArg );
   hb_retc( str );
}

/* After */
static void my_func_dd( DD_VM * vm )
{
   DD_SCOPE scope = dd_scope_enter( vm );

   DD_HANDLE hArg = dd_param( vm, 1 );
   HB_SIZE len;
   const char * str = dd_to_string( vm, hArg, &len );
   dd_return( vm, dd_string( vm, str, len ) );

   dd_scope_leave( vm, scope );
}
```

### Step 3: Register via dd_*

```c
/* Old: HB_FUNC macro creates linker symbol HB_FUN_MY_FUNC */
HB_FUNC( MY_FUNC ) { ... }

/* New: explicit registration */
void my_extension_init( DD_VM * vm )
{
   dd_register_func( vm, "MY_FUNC", my_func_dd );
}
```

### Step 4: Remove hb_* Includes

Replace `#include "hbapi.h"` with `#include "hbddapi.h"`. The dd_* header
is self-contained — it doesn't pull in HB_ITEM layout or other internals.

### Incremental Migration

Extensions can be migrated one function at a time. A single C file can contain
both `HB_FUNC()` functions (using hb_*) and dd_* registered functions. The
old and new APIs coexist in the same process.

---

[<- Index](../INDEX.md) · [BRIEF](BRIEF.md) · [DESIGN](DESIGN.md) · **COMPAT**
