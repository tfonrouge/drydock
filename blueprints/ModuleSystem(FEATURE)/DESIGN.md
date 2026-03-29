# DESIGN -- ModuleSystem (FEATURE)

## 1. Current State

### 1.1 Dynamic Symbol Table (`src/vm/dynsym.c`)

All public symbols live in a single flat array sorted by name. The lookup is
binary search on uppercase strings:

```c
/* dynsym.c:53-56 — the array element */
typedef struct {
   PHB_DYNS pDynSym;             /* Pointer to dynamic symbol */
} DYNHB_ITEM, * PDYNHB_ITEM;

/* dynsym.c:86-87 — the global table */
static PDYNHB_ITEM s_pDynItems = NULL;    /* Pointer to dynamic items */
static HB_SYMCNT   s_uiDynSymbols = 0;    /* Number of symbols present */
```

`hb_dynsymPos()` (dynsym.c:133-162) performs binary search using `strcmp()` on
`pDynSym->pSymbol->szName`. All public symbols from all modules share this
single table. Name collisions are resolved by load order — the first module
to register a symbol wins, and later modules link to the existing entry.

### 1.2 Module Symbol Structure (`include/hbvmpub.h`)

```c
/* hbvmpub.h:199-214 — every symbol in a compiled module */
typedef struct _HB_SYMB {
   const char *   szName;           /* the name of the symbol */
   union {
      HB_SYMBOLSCOPE value;         /* the scope of the symbol */
      void *         pointer;       /* filler to force alignment */
   } scope;
   union {
      PHB_FUNC       pFunPtr;       /* C function address */
      PHB_PCODEFUNC  pCodeFunc;     /* PCODE function address */
      void *         pStaticsBase;  /* statics array base */
   } value;
   PHB_DYNS       pDynSym;          /* pointer to its dynamic symbol */
} HB_SYMB, * PHB_SYMB;
```

`szName` is a flat string. No namespace field. No module field. The only
scoping mechanism is `HB_FS_STATIC` (0x0002), which makes a symbol invisible
to other modules — but there is no way to make it visible to *some* modules.

### 1.3 Module Registration (`src/vm/hvm.c:7977-8143`)

```c
PHB_SYMBOLS hb_vmRegisterSymbols( PHB_SYMB pModuleSymbols, HB_USHORT uiSymbols,
                                  const char * szModuleName, HB_ULONG ulID,
                                  HB_BOOL fDynLib, HB_BOOL fClone,
                                  HB_BOOL fOverLoad )
```

Each compiled `.prg` file produces a symbol table registered at VM startup.
`szModuleName` is the source file path — used for debugging only, not for
scoping. Every public symbol is fed to `hb_dynsymNew()`, which inserts it
into the flat global table. The module name is not stored in the dynamic
symbol entry.

### 1.4 Macro Compiler (`src/macro/`)

The macro compiler is a **separate parser** (`macro.y`) with its own lexer
(`macrolex.c`) that compiles Harbour expressions to pcode at runtime. It
resolves symbols via the dynamic symbol table:

```c
/* src/vm/macro.c:1373-1408 — runtime symbol resolution */
void hb_macroGenPushSymbol( const char * szSymbolName,
                            HB_BOOL bFunction, HB_COMP_DECL )
{
   /* ... */
   pSym = hb_dynsymFind( szSymbolName );       /* flat string lookup */
   /* ... or ... */
   pSym = hb_dynsymGetCase( szSymbolName );     /* create-on-demand */
   /* ... */
}
```

The macro lexer (`macrolex.c:106-120`) tokenizes identifiers as `[A-Za-z_][A-Za-z0-9_]*`,
converting to uppercase. It does **not** accept `.` or `::` in identifiers.

### 1.5 Class Registration (`src/vm/classes.c`)

Classes are created via `__CLSNEW` (classes.c:3674-3689):

```c
HB_FUNC( __CLSNEW )
{
   const char * szClassName = hb_parc( 1 );    /* flat name, no namespace */
   /* ... */
}
```

The class name is a flat string stored in the class registry (`s_pClasses`
array). `ClassName()` returns this flat string. There is no namespace
qualification.

### 1.6 Existing Module Primitives

| Mechanism | Where | What it does |
|-----------|-------|-------------|
| `ANNOUNCE name` | compiler/harbour.y:458 | Sets `HB_COMP_PARAM->szAnnounce` — module identity marker |
| `REQUEST name` | std.ch:293 | Preprocessor sugar for `EXTERNAL name` — forces symbol linking |
| `.hbx` files | contrib/\*/*.hbx | Auto-generated export lists using ANNOUNCE + DYNAMIC macros |
| `STATIC FUNCTION` | HB_FS_STATIC flag | File-local scope — invisible to other modules |
| `HB_FUN_` prefix | hbdefs.h:1612-1633 | C-level pseudo-namespace for PRG functions |

These provide module *identity* (ANNOUNCE) and link-time *pulling* (REQUEST)
but zero module *scoping* — all public symbols merge into the flat table.

---

## 2. Symbol Table Design

### 2.1 Options Considered

**Option A — Flat dotted names (recommended)**

Store namespace-qualified names as dotted strings in `szName`:
`"MYAPP.USERS.GETUSER"`. The dynsym table remains a flat sorted array.
`hb_dynsymPos()` continues to use `strcmp()` — dotted names sort correctly.

| Pro | Con |
|-----|-----|
| Zero structural change to dynsym.c | Longer strings = slightly slower lookup |
| Binary compatible — PHB_DYNS unchanged | No structured namespace queries without parsing dots |
| Macro compiler works (pass full dotted name) | Mangling convention becomes de facto ABI |
| Backward compatible — unqualified names unchanged | |

**Option B — Hierarchical namespace table**

Add a `szNamespace` field to `HB_DYNS` or create a two-level map
(namespace → symbol table). `hb_dynsymFind()` becomes
`hb_dynsymFindQualified(szNamespace, szName)`.

| Pro | Con |
|-----|-----|
| Structured namespace queries | Changes PHB_DYNS layout — ABI break |
| Clean separation of concerns | Every dynsym caller must be updated |
| Enables namespace iteration/listing | Macro compiler needs significant rework |
| | Thread safety for two-level lookup is complex |

**Option C — Hybrid (A now, B later if needed)**

Ship Option A in Phase H.1-H.3. Add a namespace registry (side table mapping
namespace prefix → symbol list) in Phase H.4 for tools that need structured
queries (LSP, debugger). The mangling convention is documented and parseable.

### 2.2 Recommended Approach: Option A (Flat Dotted Names)

**Name format**: `NAMESPACE.SYMBOL` (single dot separating namespace segments).

The dot (`.`) is currently invalid in Harbour identifiers, so there is zero
collision risk with existing symbol names. The compiler emits the qualified
name for symbols declared in a `MODULE` block; unqualified names remain
unchanged for backward compatibility.

**Resolution rules** (applied in order):

1. **Qualified call** (`MyApp.Users.GetUser()`): look up `"MYAPP.USERS.GETUSER"`
   directly in dynsym table. No ambiguity.

2. **Unqualified call in MODULE file** (`GetUser()`):
   a. Search current module's exported symbols first
   b. Search explicitly imported symbols (from IMPORT declarations)
   c. Search the built-in namespace (see Section 5)
   d. Search the global namespace (all unqualified symbols)
   e. If not found: compile-time error (when PersistentAST available)
      or runtime EG_NOFUNC (fallback)

3. **Unqualified call in non-MODULE file** (`GetUser()`): current behavior —
   flat dynsym lookup. Zero change.

**Disambiguation with message-send syntax**: `obj:method()` uses `:` (colon)
for object message sends. `Namespace.Func()` uses `.` (dot) for namespace
qualification. These are syntactically unambiguous:
- `:` always follows an expression (the receiver)
- `.` in namespace context follows an identifier and precedes another identifier
- The parser distinguishes them during expression parsing

### 2.3 Side-Table Namespace Registry (Phase H.4, for tooling)

A secondary data structure mapping namespace names to their symbol lists:

```c
typedef struct _HB_NAMESPACE
{
   const char *   szName;           /* e.g., "MYAPP.USERS" */
   HB_SYMCNT     uiSymbols;        /* count of symbols in this namespace */
   PHB_DYNS *    pSymbols;          /* array of pointers into the flat table */
   const char *   szSourceFile;     /* source .prg file that declares this module */
} HB_NAMESPACE;
```

Built lazily at first query (LSP, debugger) by scanning dotted names in the
dynsym table. Not on the critical function-call path.

---

## 3. Macro Compiler Integration

The macro compiler (`src/macro/`) evaluates expressions like `&(cExpr)` at
runtime. If `cExpr` is `"MyApp.Users.GetUser()"`, the macro compiler must
resolve the qualified name.

### 3.1 Lexer Changes (`src/macro/macrolex.c`)

`hb_lexIdentCopy()` (macrolex.c:106-120) currently accepts only
`[A-Za-z0-9_]`. Must also accept `.` when followed by an identifier character,
producing a single qualified-identifier token:

```c
/* Proposed change in hb_lexIdentCopy() */
else if( ch == '.' && pLex->nSrc + 1 < pLex->nLen )
{
   char chNext = pLex->pString[ pLex->nSrc + 1 ];
   if( ( chNext >= 'A' && chNext <= 'Z' ) ||
       ( chNext >= 'a' && chNext <= 'z' ) || chNext == '_' )
   {
      *pLex->pDst++ = '.';    /* keep dot as namespace separator */
      pLex->nSrc++;
      continue;
   }
   else
      break;                  /* dot followed by non-ident = not namespace */
}
```

### 3.2 Disambiguation Limitation

The macro grammar is FROZEN (67 rules). The lexer change makes
`MyApp.Users.GetUser()` a single IDENTIFIER token containing dots.
This works for FUNCTION CALLS (the FunCall rule handles it).

**However**, the following ambiguity CANNOT be resolved in macro code:
```prg
&("MyApp.Config.Value")     /* namespace-qualified variable? or hash access? */
```

**Design decision**: In macro code, dotted names are ALWAYS treated as
namespace-qualified identifiers (never as hash/object field access).
Hash access in macros must use explicit bracket syntax: `hash["key"]`.
This is acceptable because macro code is already a constrained subset
of the language.

### 3.3 Grammar Changes (`src/macro/macro.y`)

No new grammar rule needed. The lexer produces a single IDENTIFIER token
containing the dotted name (e.g., `"MYAPP.USERS.GETUSER"`). The existing
`FunCall` rule (macro.y:451) handles it:

```c
FunCall : IDENTIFIER '(' ArgList ')'  { ... }
```

The `IDENTIFIER` value is the full dotted string — passed through to
`hb_macroGenPushSymbol()` which calls `hb_dynsymFind()` with the dotted name.

### 3.3 Runtime Resolution

`hb_macroGenPushSymbol()` (src/vm/macro.c:1373) already calls
`hb_dynsymFind(szSymbolName)` with whatever string the parser produces.
If the string is `"MYAPP.USERS.GETUSER"`, the flat dynsym table lookup works
unchanged — the qualified name is just a longer string that sorts normally.

**No changes to `hb_macroGenPushSymbol()` are needed.** The lexer change is
sufficient.

### 3.4 Namespace Context for Unqualified Macros

When a macro expression uses an unqualified name (`&("GetUser()")`) inside
a MODULE-declaring file, the macro compiler needs the calling file's namespace
context to apply the resolution rules from Section 2.2.

**Proposed solution**: Add `szNamespace` to `HB_MACRO` struct (include/hbmacro.h):

```c
typedef struct HB_MACRO_ {
   /* ... existing fields ... */
   const char * szNamespace;     /* namespace context from calling file, or NULL */
} HB_MACRO;
```

When `hb_macroCompile()` is called from a MODULE-declaring file, the VM
passes the current module's namespace. The macro compiler uses it to attempt
qualified lookup before falling back to global lookup.

---

## 4. Class System Interaction

### 4.1 Class Registration Under Qualified Names

When a class is declared inside a `MODULE` block:

```harbour
MODULE MyApp.Models

CLASS User
   DATA name
ENDCLASS
```

The compiler passes `"MYAPP.MODELS.USER"` as the class name to `__CLSNEW`
(classes.c:3674). This is the same dotted-name convention as functions.

**Implications**:
- `ClassName()` returns `"MYAPP.MODELS.USER"` (the full qualified name)
- `hb_clsFindMsg()` resolves methods on `"MYAPP.MODELS.USER"` — no change
  needed, class lookup is by handle (integer), not by name
- Class handle assignment via `hb_objSetClass()` is unaffected — handles are
  opaque integers

### 4.2 Inheritance Across Namespaces

```harbour
MODULE MyApp.Views

IMPORT MyApp.Models: User

CLASS UserView FROM User
   DATA template
ENDCLASS
```

The compiler resolves `User` to `"MYAPP.MODELS.USER"` via the IMPORT
declaration, then passes the resolved class handle (not name) to the
inheritance machinery in `hb_clsNew()`. The runtime inheritance system
works on handles — it never needs to parse dotted names.

### 4.3 FRIEND Declarations Across Module Boundaries

```harbour
MODULE MyApp.Models

CLASS Account
   HIDDEN DATA balance
   FRIEND CLASS MyApp.Audit.Inspector
ENDCLASS
```

`FRIEND CLASS` (hbclass.ch) compiles to `__clsAddFriend()` which takes
a class name string. The dotted name `"MYAPP.AUDIT.INSPECTOR"` is passed
as-is. When the friend check occurs at runtime (`hb_clsValidScope()`,
classes.c), it compares class names — dotted names compare correctly.

### 4.4 Extension Methods and Namespace Scoping

```harbour
MODULE MyApp.Formatting

EXTEND CLASS CHARACTER
   METHOD slug()
   METHOD titleCase()
ENDCLASS
```

**Design decision**: Extension methods declared in a MODULE are **globally
visible** — they extend the target class for all callers, not just callers
within the declaring module. Rationale:

- Extension methods modify the class's method table via `__clsAddMsg()`,
  which is a global operation on a shared class handle.
- Module-scoped extensions would require per-module method table overlays,
  which is architecturally incompatible with the hash-based dispatch system.
- Precedent: Swift, Kotlin, and C# all make extension methods globally
  visible once linked (Swift) or imported (Kotlin/C#).

If scoped extensions are desired in the future, they can be explored as a
separate feature (Tier 3+) via inline caching overlays.

---

## 5. Built-In Namespace Exceptions

These symbols are always available without IMPORT, regardless of MODULE
context. They form the `BUILTIN` pseudo-namespace.

### 5.1 DrydockObject Methods

Always-available via the built-in default message mechanism in
`hb_objGetMethod()` (classes.c:2165-2224). These bypass the dynamic symbol
table entirely — they are static `HB_SYMB` entries resolved in the method
dispatch path:

`toString`, `className`, `isScalar`, `isNil`, `valType`, `compareTo`,
`isComparable`

**No namespace interaction**: These are resolved by the message dispatch
system, not by the function call path. IMPORT is irrelevant.

### 5.2 Scalar Class Methods

Scalar class methods (Upper, Lower, Split, Map, Filter, Reduce, etc.) are
registered on scalar type classes via `__clsAddMsg()` during VM init or
when `tscalar.prg` is linked. They are resolved via `hb_objGetMethod()` on
scalar values.

**No namespace interaction**: Message sends (`:Upper()`) are resolved by the
class method table, not by the dynsym function lookup. IMPORT is irrelevant.

### 5.3 RTL Functions

The RTL (Runtime Library) exposes ~300 built-in functions. These are linked
via `hb_vmRegisterSymbols()` from the main executable's symbol table. They
are always present in the dynsym table with unqualified names:

`Upper`, `Lower`, `Len`, `ValType`, `QOut`, `QQOut`, `Str`, `Val`,
`Date`, `Time`, `Empty`, `Type`, `hb_ntos`, etc.

**Implementation**: RTL symbols are registered without namespace qualification
(they predate the module system). In the resolution rules (Section 2.2,
step 2c), the "built-in namespace" check is simply: if the unqualified name
exists in the dynsym table and was registered by a non-MODULE source (i.e.,
it has no dot in its `szName`), treat it as built-in.

### 5.4 Summary

| Category | Resolution Path | Needs IMPORT? |
|----------|----------------|---------------|
| DrydockObject methods | `hb_objGetMethod()` built-in messages | No — always available |
| Scalar class methods | `hb_objGetMethod()` class method table | No — always available |
| RTL functions | `hb_dynsymFind()` global table | No — always available |
| User functions in MODULE | `hb_dynsymFind()` with qualified name | Yes — requires IMPORT |
| User classes in MODULE | Class registry with qualified name | Yes — requires IMPORT |

---

## 6. `.hrb` v3 Namespace Alignment

### 6.1 Format Extension

The `.hrb` v3 format (defined in HRBModern DESIGN.md) already stores a
"Module name" field (the source file path). Add a second null-terminated
string for the declared namespace:

```
Offset  Size    Field
[0:4]   4       Signature: 0xC0 'H' 'R' 'B'
[4:6]   2       Version: uint16 LE = 3
[6:8]   2       Pcode version: uint16 LE
[8:?]   var     Module name: null-terminated (source file path)
[?:?]   var     Declared namespace: null-terminated (MODULE name, or "" if none)
[?:?+4] 4       Symbol count: uint32 LE
[?:?]   var     Symbol table (with 16-bit scope)
[?:?+4] 4       Function count: uint32 LE
[?:EOF] var     Function data
```

When no `MODULE` declaration exists, the declared namespace is an empty
string (single `\0` byte).

### 6.2 Writer (`src/compiler/genhrb.c`)

The compiler stores the MODULE name in a new field `HB_COMP_PARAM->szModule`
(or reuses `szAnnounce` if semantics align). The writer emits it after the
source file path:

```c
/* After writing module name (source file path) */
if( HB_COMP_PARAM->szModule )
{
   nSize = strlen( HB_COMP_PARAM->szModule ) + 1;
   memcpy( ptr, HB_COMP_PARAM->szModule, nSize );
   ptr += nSize;
}
else
   *ptr++ = '\0';    /* empty namespace */
```

### 6.3 Reader (`src/vm/runner.c`)

```c
if( iVersion >= 3 )
{
   /* read pcode version */
   /* read module name (existing) */
   /* read declared namespace (NEW) */
   szNamespace = ( const char * ) ptr;
   ptr += strlen( szNamespace ) + 1;
   /* Store szNamespace in HRB_BODY for registration */
}
```

The namespace is used during `hb_vmRegisterSymbols()` to qualify symbol
names if the file declares a MODULE.

### 6.4 `.hbx` Format Evolution

Current `.hbx` files use ANNOUNCE/DYNAMIC macros with flat symbol names:

```harbour
DYNAMIC GetUser
DYNAMIC ValidateId
```

For namespaced modules, `.hbx` files emit qualified names:

```harbour
ANNOUNCE __HBEXTERN__MYAPP_USERS__
DYNAMIC MYAPP.USERS.GETUSER
```

The `.hbx` generator (`utils/hbmk2/hbmk2.prg` or Zig build equivalent)
reads the compiled `.hrb` or `.c` output's symbol table and emits the
qualified names when a declared namespace is present.

---

## 7. Alternatives Considered

### 7.1 C++ Style Name Mangling

Encode namespace + name into an opaque mangled string (e.g., `_N4MYAPP5USERS7GETUSER`).

**Rejected**: Harbour has a strong tradition of human-readable symbols. The
debugger, profiler, and error messages all display symbol names directly.
Mangled names would degrade the developer experience. The dotted convention
preserves readability.

### 7.2 Runtime Namespace Objects

Make namespaces first-class objects that can be stored, passed, and queried:
`ns := GetNamespace("MyApp.Users"); ns:GetUser(cId)`.

**Deferred**: Interesting but unnecessary for the core module system. Can be
explored as a Tier 3 extension if demand exists. The side-table registry
(Section 2.3) provides the infrastructure.

### 7.3 Package Manager / Dependency Resolution

Build a full package system with versioned dependencies, semver constraints,
and a registry.

**Out of scope**: ModuleSystem is a language-level feature (compile-time
symbol scoping). Package management is a build-system feature (dependency
resolution and distribution). The two are orthogonal. Package management
belongs in ZigBuild or a dedicated tool, not in the compiler.

---

[<- Index](../INDEX.md) · [Map](../MAP.md) · [BRIEF](BRIEF.md) · **DESIGN**
