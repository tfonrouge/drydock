# COMPAT -- ModuleSystem (FEATURE)

## Compatibility Target

- **Files without MODULE declaration**: 100% source + ABI backward compatibility.
  Zero behavioral change. All existing `.prg` files compile and run identically.
- **Files with MODULE declaration**: 99.5% compatibility. The 0.5% is intentional
  encapsulation — private functions in MODULE files become inaccessible from
  outside the module. This is the entire point of the feature.

---

## Compatibility Covenant

All 7 rules from `doc/drydock/vision.md` are satisfied:

| Rule | Satisfied? | Notes |
|------|-----------|-------|
| 1. `ValType()` never changes | Yes | No type system changes |
| 2. `Len()` always returns bytes | Yes | No string changes |
| 3. `HB_IS_OBJECT()` returns `.F.` for scalars | Yes | No object model changes |
| 4. New keywords are context-sensitive | Yes | MODULE/IMPORT/EXPORT only at statement start |
| 5. New warnings require explicit opt-in | Yes | Namespace warnings require `-km` flag |
| 6. User-defined methods shadow scalar class methods | Yes | No method dispatch changes |
| 7. ABI breaks gated behind pcode version bump | Yes | No new opcodes; `.hrb` v3 field is additive |

**Additional rules for ModuleSystem**:

| Rule | Description |
|------|-------------|
| 8. Files without MODULE unchanged | Global namespace behavior is the default. No existing file changes scope |
| 9. Global namespace always accessible | MODULE files can access global symbols via resolution fallback (Section 2.2 rule 4 in BRIEF) or `IMPORT Global: *` |
| 10. Context-sensitive keywords | `MODULE`, `IMPORT`, `EXPORT` as variable/function names continue to work in non-statement-start positions |

---

## Fracture Analysis

### Fracture 1: Name Resolution Order Change — Risk: MEDIUM

**What changes**: When a file declares `MODULE`, unqualified function calls
follow a new resolution order: module exports → imports → built-in → global.
This could cause an unqualified call to resolve to a different function than
before (a module-local function shadowing a global one).

**Who is affected**: Only files that opt in to `MODULE`. No existing code is
affected until it adds a MODULE declaration.

**Discoverability**: Compile time (with PersistentAST) or first test run.
The compiler can emit a warning when a module-local symbol shadows a global
symbol (`-km` flag).

**Mitigation**: Shadowing warnings. Developers can use fully qualified names
(`Global.FuncName()`) to force global resolution.

### Fracture 2: `ClassName()` Returns Qualified Name — Risk: LOW

**What changes**: A class declared in `MODULE MyApp.Models` returns
`"MYAPP.MODELS.USER"` from `ClassName()` instead of `"USER"`.

**Who is affected**: Code that compares `ClassName()` against hardcoded
strings (e.g., `IF o:ClassName() == "USER"`). This is uncommon — most
code uses `o:IsDerivedFrom("USER")` or class handle comparison.

**Discoverability**: Test time — the comparison fails visibly.

**Mitigation**: Provide a `ShortClassName()` method that strips the namespace
prefix, or compare with the unqualified name as suffix match.

### Fracture 3: Macro Compiler Namespace Resolution — Risk: MEDIUM

**What changes**: `&("GetUser()")` inside a MODULE file may not find functions
in other namespaces if they are registered with qualified names. The macro
compiler currently does flat dynsym lookup — if `GetUser` was registered as
`"MYAPP.USERS.GETUSER"`, the unqualified lookup fails.

**Who is affected**: Code that uses runtime macro compilation (`&()`) to call
functions by unqualified string names across module boundaries.

**Discoverability**: Runtime — `EG_NOFUNC` error.

**Mitigation**: The macro compiler receives namespace context (see DESIGN.md
Section 3.4). It attempts qualified lookup by prepending the calling file's
namespace, then falls back to global lookup. Developers can also pass fully
qualified strings: `&("MyApp.Users.GetUser()")`.

### Fracture 4: `.hbx` Format Change — Risk: LOW

**What changes**: `.hbx` export files for namespaced modules will emit
qualified symbol names (`DYNAMIC MYAPP.USERS.GETUSER` instead of
`DYNAMIC GETUSER`).

**Who is affected**: Third-party tools that parse `.hbx` files (unlikely —
`.hbx` files are consumed by the Harbour preprocessor, not external tools).

**Discoverability**: Build time — the tool fails to parse the dotted name.

**Mitigation**: Dotted names in `.hbx` are valid Harbour syntax (the dot
terminates an identifier, but the preprocessor treats DYNAMIC arguments
as raw text). No `.hbx` parser changes are needed for the Harbour
preprocessor itself.

---

## Migration Guide

### Step 1: Add MODULE declaration

```harbour
/* Before */
FUNCTION GetUser( cId )
   ...

/* After */
MODULE MyApp.Users

EXPORT FUNCTION GetUser( cId )
   ...
```

### Step 2: Mark public API with EXPORT

Functions without `EXPORT` in a MODULE file become module-private (equivalent
to `STATIC FUNCTION`). Review each function and add `EXPORT` to those that
should be accessible from other modules.

### Step 3: Add IMPORT declarations to consumers

```harbour
/* Before */
FUNCTION ShowUser()
   LOCAL u := GetUser( "123" )
   ...

/* After */
MODULE MyApp.Views

IMPORT MyApp.Users: GetUser

FUNCTION ShowUser()
   LOCAL u := GetUser( "123" )
   ...
```

### Step 4: Run with `-km` flag

The `-km` (module warnings) compiler flag reports:
- Shadowing warnings (module symbol shadows global symbol)
- Unused imports
- Unresolved imports (imported module not found)

### Incremental Adoption

Modules can be adopted one file at a time. A MODULE-declaring file can call
functions in non-MODULE files (they are in the global namespace). Non-MODULE
files can call exported functions in MODULE files using qualified names
(`MyApp.Users.GetUser()`). Full adoption is not required — the system is
designed for gradual migration.

---

[<- Index](../INDEX.md) · [BRIEF](BRIEF.md) · [DESIGN](DESIGN.md) · **COMPAT**
