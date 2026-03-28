# IMPLEMENTATION_PLAN -- DrydockObject (SUBSYSTEM)

## Phase D.1: toString Built-In Message (0.5 day)

- **Milestone**: `"hello":toString()` works on ANY value without any includes,
  REQUEST, or ENABLE. Works even if no scalar classes are registered.

### Steps

- [ ] **D.1.1** Add `s___msgToString` static symbol declaration in classes.c.
- [ ] **D.1.2** Register dynsym in `hb_clsInit()`.
- [ ] **D.1.3** Add check in `hb_objGetMethod()` default messages section.
- [ ] **D.1.4** Implement `msgToString()` with type-switch cascade.
- [ ] **D.1.5** Test: compile minimal .prg with `? "hello":toString()`, no includes.
- [ ] **D.1.6** Verify: `ddtest` 4861/4861 pass.

### Files touched

| File | Change |
|------|--------|
| `src/vm/classes.c` | +1 symbol, +1 dynsym registration, +1 dispatch check, +1 function (~60 lines) |

---

## Phase D.2: DrydockObject Root Class (1 day)

- **Milestone**: DrydockObject class exists at VM startup. Has toString,
  className, isScalar, isNil, valType methods. Set as `s_uiObjectClass`.

### Steps

- [ ] **D.2.1** Add `s_uiDrydockObjectClass` static variable.
- [ ] **D.2.2** Add `msgIsScalar()`, `msgIsNil()`, `msgValType()` C functions.
- [ ] **D.2.3** Add `hb_clsInitDrydockObject()` function — creates root class,
  adds methods via `hb_clsAdd()`, sets `s_uiObjectClass`.
- [ ] **D.2.4** Call `hb_clsInitDrydockObject()` from `hb_clsInit()` after
  class pool allocation.
- [ ] **D.2.5** Test: `"hello":isScalar()`, `NIL:isNil()`, `(42):valType()`.
- [ ] **D.2.6** Verify: `ddtest` 4861/4861 pass.

---

## Phase D.3: Scalar Classes in C (1 day)

- **Milestone**: All 11 scalar classes exist at VM startup, inheriting from
  DrydockObject. `"hello":classH()` returns non-zero. No linking dependency.

### Steps

- [ ] **D.3.1** In `hb_clsInitDrydockObject()`, create 11 scalar classes
  using `hb_clsNew()` with DrydockObject as super. Assign to
  `s_uiArrayClass`, `s_uiCharacterClass`, etc.
- [ ] **D.3.2** Test: `"hello":classH()` returns > 0.
  `"hello":className()` returns "CHARACTER" via class method (not built-in).
- [ ] **D.3.3** Verify: `ddtest` 4861/4861 pass.

---

## Phase D.4: Modify hb_clsDoInit (1 day)

- **Milestone**: When tscalar.prg IS linked, its methods extend the
  C-created scalar classes. When NOT linked, base methods still work.

### Steps

- [ ] **D.4.1** Modify `hb_clsDoInit()` to skip handle assignment if handle
  already non-zero (class already created by C init).
- [ ] **D.4.2** Verify that tscalar.prg factory functions extend (not replace)
  the C-created classes.
- [ ] **D.4.3** Test: with ENABLE TYPE CLASS ALL, `"hello":Upper()` still works.
- [ ] **D.4.4** Test: WITHOUT ENABLE TYPE CLASS ALL, `"hello":toString()` works
  but `"hello":Upper()` errors (expected — rich methods not linked).
- [ ] **D.4.5** Verify: `ddtest` 4861/4861 pass.
- [ ] **D.4.6** Update `tests/scalar.prg` to test both modes.

---

## Phase D.5: Cleanup + Verification (0.5 day)

- [ ] **D.5.1** Remove the `ENABLE TYPE CLASS ALL` requirement from tests
  that only use base methods (toString, className, etc.).
- [ ] **D.5.2** Verify: `zig build` works.
- [ ] **D.5.3** Run full scalar test suite: 55+ tests pass.
- [ ] **D.5.4** Update all blueprint artifacts.

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
