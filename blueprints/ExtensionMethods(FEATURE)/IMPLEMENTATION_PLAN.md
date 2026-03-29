# IMPLEMENTATION_PLAN -- ExtensionMethods (FEATURE)

## Phase E.1: Preprocessor Approach -- DONE (2026-03-28, `0140f8a`)

- **Milestone**: Users can extend any class with `EXTEND CLASS STRING WITH
  METHOD ... ACTION {|Self| ...}` syntax. `__clsFindByName()` resolves class
  handles by name with alias support (STRING→CHARACTER, NUMBER→NUMERIC,
  BOOL→LOGICAL). Always available — works in .hrb runtime too.

### Steps (all complete)

- [x] **E1.1** Add `__clsFindByName()` to `src/vm/classes.c` — resolves class
  handle from name string. Supports modern aliases.
- [x] **E1.2** Register `__clsFindByName` as dynsym in `hb_clsInit()` so it's
  discoverable by .hrb runtime.
- [x] **E1.3** Export `HB_FUN___CLSFINDBYNAME` in `src/harbour.def`.
- [x] **E1.4** Add `EXTEND CLASS ... WITH METHOD ... ACTION` preprocessor
  command to `include/hbclass.ch` (inline code block form).
- [x] **E1.5** Add `EXTEND CLASS ... WITH METHOD ... FUNCTION` preprocessor
  command (function reference form).
- [x] **E1.6** Test: inline extensions, function extensions, alias resolution.
  11/11 tests pass in ddrun.

---

## Phase E.2: Class Name Aliases -- DONE (2026-03-29)

- **Milestone**: STRING, NUMBER, BOOL recognized in EXTEND CLASS syntax.

### Steps (all complete)

- [x] **E2.1** Add `#xcommand` rules in hbclass.ch: `EXTEND CLASS STRING`
  → `EXTEND CLASS CHARACTER`, etc. Runtime aliases in `__clsFindByName()`
  already handle the `__clsAddMsg()` call.
- [x] **E2.2** Test: `EXTEND CLASS STRING WITH METHOD ...` works.

---

## Phase E.3: Native Parser Support (deferred to PersistentAST)

- **Milestone**: `FUNCTION STRING.method()` syntax supported natively in the
  parser. No preprocessor needed. Self binding is automatic.

### Steps

- [ ] **E3.1** Grammar changes in `harbour.y` for dotted function names.
- [ ] **E3.2** Code generation for method registration at module load.
- [ ] **E3.3** Proper Self binding in function context.

---

[<- Index](../INDEX.md) · [Map](../MAP.md) · [BRIEF](BRIEF.md) · **PLAN** · [TESTS](TEST_PLAN.md) · [AUDIT](AUDIT.md)
