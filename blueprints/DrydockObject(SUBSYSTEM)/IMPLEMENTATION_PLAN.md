# IMPLEMENTATION_PLAN -- DrydockObject (SUBSYSTEM)

## Phase D.1: toString Built-In Message (0.5 day)

- **Milestone**: `"hello":toString()` works on ANY value without any includes,
  REQUEST, or ENABLE. Works even if no scalar classes are registered.

### Steps

- [x] **D.1.1** Add `s___msgToString` static symbol declaration in classes.c.
- [x] **D.1.2** Register dynsym in `hb_clsInit()`.
- [x] **D.1.3** Add check in `hb_objGetMethod()` default messages section.
- [x] **D.1.4** Implement `msgToString()` with type-switch cascade.
- [x] **D.1.5** Test: compile minimal .prg with `? "hello":toString()`, no includes.
- [x] **D.1.6** Verify: `ddtest` 4861/4861 pass.

### Files touched

| File | Change |
|------|--------|
| `src/vm/classes.c` | +1 symbol, +1 dynsym registration, +1 dispatch check, +1 function (~60 lines) |

---

## Phase D.2: DrydockObject Root Class (1 day)

- **Milestone**: DrydockObject class exists at VM startup. Has toString,
  className, isScalar, isNil, valType methods. Set as `s_uiObjectClass`.

### Steps

- [x] **D.2.1** Add `s_uiDrydockObjectClass` static variable.
- [x] **D.2.2** Add `msgIsScalar()`, `msgIsNil()`, `msgValType()` C functions.
- [x] **D.2.3** Add `hb_clsInitDrydockObject()` function — creates root class,
  adds methods via `hb_clsAdd()`, sets `s_uiObjectClass`.
- [x] **D.2.4** Call `hb_clsInitDrydockObject()` from `hb_clsInit()` after
  class pool allocation.
- [x] **D.2.5** Test: `"hello":isScalar()`, `NIL:isNil()`, `(42):valType()`.
- [x] **D.2.6** Verify: `ddtest` 4861/4861 pass.

---

## Phase D.3: Scalar Classes in C (1 day)

- **Milestone**: All 11 scalar classes exist at VM startup, inheriting from
  DrydockObject. `"hello":classH()` returns non-zero. No linking dependency.

### Steps

- [x] **D.3.1** In `hb_clsInitDrydockObject()`, create 11 scalar classes
  using `hb_clsNew()` with DrydockObject as super. Assign to
  `s_uiArrayClass`, `s_uiCharacterClass`, etc.
- [x] **D.3.2** Test: `"hello":classH()` returns > 0.
  `"hello":className()` returns "CHARACTER" via class method (not built-in).
- [x] **D.3.3** Verify: `ddtest` 4861/4861 pass.

---

## Phase D.4: Modify hb_clsDoInit (1 day)

- **Milestone**: When tscalar.prg IS linked, its methods extend the
  C-created scalar classes. When NOT linked, base methods still work.

### Steps

- [x] **D.4.1** ~~Modify `hb_clsDoInit()` to skip handle assignment~~ — **Not needed.**
  The default message mechanism (D.1/D.2) provides universal methods regardless
  of which class the handles point to. When PRG factories are linked, they
  overwrite the C handles with richer classes — that's correct behavior.
- [x] **D.4.2** Verified: tscalar.prg factory functions coexist correctly
  with C-created classes (ddtest 4861/4861 pass with rich methods).
- [x] **D.4.3** Verified: ddtest passes (includes ENABLE TYPE CLASS ALL tests
  with Upper(), Abs(), etc.).
- [x] **D.4.4** Verified: WITHOUT ENABLE TYPE CLASS ALL, `"hello":toString()`,
  `isScalar()`, `isNil()`, `valType()` all work. Class methods dispatch correctly.
- [x] **D.4.5** Verified: `ddtest` 4861/4861 pass.
- [x] **D.4.6** Updated `tests/scalar.prg` with 20 DrydockObject universal method tests.

---

## Phase D.5: Cleanup + Verification (0.5 day)

- [x] **D.5.1** DrydockObject tests added to `tests/scalar.prg` (20 new tests).
  Base methods work with or without ENABLE TYPE CLASS ALL.
- [x] **D.5.2** Verified: `zig build` works.
- [x] **D.5.3** Verified: `ddtest` 4861/4861 pass.
- [x] **D.5.4** All blueprint artifacts updated.

---

## Risk Register

| Risk | Phase | Severity | Mitigation |
|------|-------|----------|------------|
| hb_clsNew called before pool ready | D.2 | High | Call AFTER s_pClasses allocation |
| hb_clsAdd needs symbols registered | D.2 | High | Register dynsyms first in hb_clsInit |
| DrydockObject breaks HBObject | D.4 | Medium | HBObject inherits from DrydockObject via s_uiObjectClass |
| hb_clsDoInit overwrites C handles | D.4 | High | Guard with `if( *handle == 0 )` |
| toString recursion | D.1 | Medium | C implementation uses type switch, not method dispatch |

---

[<- Index](../INDEX.md) · [Map](../MAP.md) · [BRIEF](BRIEF.md) · [DESIGN](DESIGN.md) · **PLAN** · [TESTS](TEST_PLAN.md) · [AUDIT](AUDIT.md)
