# DESIGN -- GradualTyping (FEATURE)

## 1. Type System Choice: Nominal

Drydock uses nominal typing -- types are identified by class name, not structure.
- `AS String` means "must be an instance of CHARACTER class (or subclass)"
- `AS Number` means "must be NUMERIC"
- `AS Person` means "must be instance of Person class (or subclass)"
- Union types via `|`: `AS String | Number` means "either CHARACTER or NUMERIC"

### Why Nominal (not Structural)

- Matches existing `AS TYPE` syntax in Harbour
- Aligns with DDClass design (classes are named entities)
- Simpler to implement -- class handle comparison, not structural matching
- Structural subtyping can be added later as enhancement

---

## 2. Type Representation

```c
typedef struct {
   HB_USHORT  uiTypeClass;    /* class handle, 0 = any/untyped */
   HB_BOOL    fNullable;      /* can be NIL? */
   HB_BOOL    fStrict;        /* runtime check (! suffix) */
} DD_TYPE;
```

---

## 3. Checking Phases

### Phase F.1: Compile-Time Warnings (opt-in via -kt flag)

- Walk AST after symbol resolution
- For each assignment: check if RHS type is compatible with LHS declared type
- For each return: check if return value matches function's declared return type
- For each function call: check argument types against parameter declarations
- Emit warnings (not errors) for mismatches. Code still compiles.

### Phase F.2: Flow-Sensitive Narrowing

- Recognize guard patterns:
  ```prg
  IF HB_IsString( x )
     /* x is narrowed to STRING in this branch */
  ENDIF
  ```
- Track type state through IF/ELSE branches
- Reset narrowing at branch merge points (conservative)

### Phase F.3: Runtime Guards (strict mode)

- `AS String!` (with `!`) generates `HB_P_TYPECHECK` opcode
- At runtime: checks type, throws error on mismatch
- Pcode version bump required (new opcode)

---

## 4. What's NOT Checked

- Untyped variables (no inference from usage)
- Dynamic dispatch (method calls resolved at runtime)
- Array/hash element types (no generics yet)
- Macro-compiled code (runtime compilation, no AST)

---

## 5. Cross-Module Type References

- `AS MyApp.Models.User` requires ModuleSystem (Phase H) for resolution
- Without ModuleSystem: only local and globally-visible class names work
- Forward-compatible: type annotations stored in AST; resolved when ModuleSystem lands

---

## 6. Files Modified

- `src/compiler/hbexpr.c` -- Type checking walker
- `src/compiler/harbour.y` -- Parse `!` suffix on type annotations
- `include/hbpcode.h` -- Add `HB_P_TYPECHECK` (Phase F.3)
- `src/vm/hvm.c` -- Handle `HB_P_TYPECHECK` (Phase F.3)

---

## 7. Compatibility

100% backward. Warnings off by default (`-kt` opt-in). Strict mode (`!` suffix) is new syntax -- existing code unaffected. `HB_P_TYPECHECK` requires pcode version bump (F.3 only).

---

[<- Index](../INDEX.md) · [Map](../MAP.md) · [BRIEF](BRIEF.md) · **DESIGN**
