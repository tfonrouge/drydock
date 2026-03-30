# IMPLEMENTATION_PLAN -- GradualTyping (FEATURE)

## Phase F.1: Compile-Time Type Warnings (opt-in via -kt)

- **Milestone**: `drydock -kt` emits warnings for provable type mismatches.
  Code still compiles. Warnings cover assignments, returns, call args,
  and operator compatibility.

### Steps

- [x] **F.1a** Assignment type checking — warn when RHS literal type
  differs from LHS variable's declared AS TYPE. (2026-03-29, `222c310`)
- [ ] **F.1b** Return type checking — warn when RETURN expression type
  differs from function's declared return type. (Deferred — RETURN is a
  statement without an AST node; needs HB_ET_RETURN or grammar change.)
- [ ] **F.1c** Function call argument checking — warn when argument
  literal type differs from parameter's declared AS TYPE. (Deferred —
  needs HB_HDECLARED lookup during AST walk.)
- [x] **F.1d** Operator type compatibility — warn on provably incompatible
  operands (e.g., string + numeric, logical * numeric). Allows valid
  cross-type ops (date + numeric). Uses W0010 warning.

### Files touched

| File | Change |
|------|--------|
| `src/compiler/hbastwalk.c` | Type checking visitors for each check type |
| `src/compiler/cmdcheck.c` | `-kt` flag parsing (done) |
| `src/compiler/hbmain.c` | Type checker invocation (done) |
| `include/hbcompdf.h` | `fTypeCheck` flag (done) |

---

## Phase F.2: Flow-Sensitive Narrowing

- [ ] **F.2.1** Recognize `HB_IsString(x)` / `HB_IsNumeric(x)` guard patterns.
- [ ] **F.2.2** Track type state through IF/ELSE branches.
- [ ] **F.2.3** Reset narrowing at branch merge points (conservative).

---

## Phase F.3: Runtime Guards (strict mode)

- [ ] **F.3.1** Parse `!` suffix on type annotations (`AS String!`).
- [ ] **F.3.2** Add `HB_P_TYPECHECK` opcode to `hbpcode.h`.
- [ ] **F.3.3** Handle `HB_P_TYPECHECK` in `hvm.c` — runtime type assertion.
- [ ] **F.3.4** Pcode version bump.

---

[<- Index](../INDEX.md) · [Map](../MAP.md) · [BRIEF](BRIEF.md) · [DESIGN](DESIGN.md) · **PLAN** · [AUDIT](AUDIT.md)
