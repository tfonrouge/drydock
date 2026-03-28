# DESIGN -- HRBModern (FEATURE)

## 1. Current State

### .hrb Writer (`src/compiler/genhrb.c`, 171 lines)

Binary format v2:
```
Offset  Size    Field
[0:4]   4       Signature: 0xC0 'H' 'R' 'B'
[4:6]   2       Version: uint16 LE (currently 2)
[6:10]  4       Symbol count: uint32 LE
[10:?]  var     Symbol table:
                  name: null-terminated string
                  scope: 1 byte ← TRUNCATED from HB_USHORT
                  type: 1 byte (SYM_NOLINK=0, SYM_FUNC=1, SYM_EXTERN=2, SYM_DEFERRED=3)
[?:?+4] 4       Function count: uint32 LE
[?:EOF] var     Function data:
                  name: null-terminated string
                  size: uint32 LE
                  pcode: raw bytes
```

### Scope Truncation Bug (`genhrb.c:94-101`)

```c
/* FIXME: this conversion strips upper byte from symbol scope [...] */
*ptr++ = ( HB_BYTE ) pSym->cScope;    /* only low 8 bits saved */
```

The `HB_FS_*` flags are a 16-bit bitmask:
```
Preserved (low byte):       Lost (high byte):
  HB_FS_PUBLIC    0x0001      HB_FS_PCODEFUNC 0x0100
  HB_FS_STATIC   0x0002      HB_FS_LOCAL     0x0200
  HB_FS_FIRST    0x0004      HB_FS_DYNCODE   0x0400
  HB_FS_INIT     0x0008      HB_FS_DEFERRED  0x0800
  HB_FS_EXIT     0x0010      HB_FS_FRAME     0x1000
  HB_FS_MESSAGE  0x0020      HB_FS_USED      0x2000
  HB_FS_MEMVAR   0x0080
```

`runner.c` has workarounds (line 459): it reconstructs `HB_FS_PCODEFUNC` and
`HB_FS_LOCAL` from the symbol type field during linking. But this is fragile
and cannot reconstruct `HB_FS_DEFERRED`, `HB_FS_DYNCODE`, or `HB_FS_FRAME`.

### .hrb Reader (`src/vm/runner.c`, 881 lines)

`hb_hrbLoad()` (line 305-557):
1. Reads header signature and version (line 322)
2. Reads symbol count (line 339)
3. First pass: calculates string table size (line 351-366)
4. Second pass: reads symbol names, scope bytes, type bytes (line 373-391)
5. Reads function count and function bodies (line 394-434)
6. Links symbols: resolves SYM_FUNC/SYM_EXTERN/SYM_DEFERRED (line 446-500)
7. Registers module symbols via `hb_vmRegisterSymbols()` (line 521)
8. Initializes statics via `hb_hrbInitStatic()` (line 544)

INIT/EXIT handling already exists in `hb_hrbInit()` (line 196-240) and
`hb_hrbExit()` (line 242-268) — but these are only called via
`hb_hrbDo()`, not automatically on load.

---

## 2. Proposed Changes — Phase H.1

### 2.1 New .hrb v3 Format

**Implemented (Phase H.1)**:

```
Offset  Size    Field
[0:4]   4       Signature: 0xC0 'H' 'R' 'B'
[4:6]   2       Version: uint16 LE = 3
[6:8]   2       Pcode version: uint16 LE (HB_PCODE_VER)
[8:?]   var     Module name: null-terminated string (source file path)
[?:?+4] 4       Symbol count: uint32 LE
[?:?]   var     Symbol table:
                  name: null-terminated string
                  scope: 2 bytes (uint16 LE) ← FULL scope, no truncation
                  type: 1 byte (SYM_NOLINK/SYM_FUNC/SYM_EXTERN/SYM_DEFERRED)
[?:?+4] 4       Function count: uint32 LE
[?:EOF] var     Function data:
                  name: null-terminated string
                  size: uint32 LE
                  pcode: raw bytes
```

Changes from v2 (implemented in Phase H.1):
- Version field: 2 → 3
- Added: pcode version (2 bytes) after version field
- Added: module name (null-terminated string) after pcode version
- Scope field: 1 byte → 2 bytes (uint16 LE)

**Planned (Phase H.1b)** — will be inserted between module name and symbol count:
- Declared namespace (null-terminated string) — stores the `MODULE` declaration
  name for ModuleSystem (Phase H); empty string if no MODULE declaration.
  See [ModuleSystem DESIGN.md](../ModuleSystem(FEATURE)/DESIGN.md) §6.

### 2.2 Writer Changes (`genhrb.c`)

```c
/* Size calculation — add pcode version (2) + module name + scope expanded to 2 */
nSize = 10;  /* signature[4] + version[2] + pcode_version[2] + */
             /* module_name is added separately */
nSize += strlen( szModuleName ) + 1;  /* module name + null */
nSize += strlen( szNamespace ) + 1;  /* declared namespace + null (empty if none) */
nSize += 4;  /* symbol count */
/* per symbol: name + \0 + scope[2] + type[1] = name_len + 4 */
```

Key change in symbol writing:
```c
/* v3: write full 16-bit scope */
HB_PUT_LE_UINT16( ptr, pSym->cScope );
ptr += 2;
```

### 2.3 Reader Changes (`runner.c`)

Version dispatch in `hb_hrbLoad()`:
```c
int iVersion = hb_hrbReadHead( szHrbBody, nBodySize, &nBodyOffset );
if( iVersion == 0 )
   /* error */
else if( iVersion >= 3 )
{
   /* v3: read pcode version (2 bytes) */
   /* v3: read module name (null-terminated) */
   /* v3: read declared namespace (null-terminated, "" if none) */
}
/* symbol reading: */
if( iVersion >= 3 )
   scope = HB_GET_LE_UINT16( ptr ); ptr += 2;  /* full 16-bit scope */
else
   scope = (HB_BYTE) *ptr++;                     /* v2: truncated 8-bit */
```

### 2.4 No Struct Changes

`HRB_BODY`, `HB_DYNF`, `HB_SYMB` are unchanged. The format change is purely
in serialization/deserialization. The in-memory representation is already
correct (scope is `HB_SYMBOLSCOPE` which is 16-bit).

---

## 3. Memory Layout Impact

None. No struct changes. The `.hrb` file format is a serialization format,
not a memory layout.

---

## 4. Backward Compatibility

- **v2 .hrb files**: continue to load — `runner.c` dispatches by version
  number. The existing truncation workaround remains for v2.
- **v3 .hrb files on old runner**: will fail with "corruption" error (version
  check returns non-zero but old code doesn't handle v3 fields). This is
  expected — v3 files require updated runtime.
- **No change to C path**: `genc.c` / `gencc.c` are untouched.

---

[<- Index](../INDEX.md) · [Map](../MAP.md) · [BRIEF](BRIEF.md) · **DESIGN** · [API](C_API.md) · [PLAN](IMPLEMENTATION_PLAN.md) · [TESTS](TEST_PLAN.md) · [AUDIT](AUDIT.md)
