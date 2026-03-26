# BRIEF -- Optimizer (SUBSYSTEM)

## Identity

| Field | Value |
|-------|-------|
| **Name** | Optimizer |
| **Mode** | SUBSYSTEM |
| **Tier** | 2 — Build a Real Compiler |
| **Phase** | G |
| **Component** | Compiler — `src/compiler/hbopt.c`, `src/compiler/hbdead.c` |
| **Status** | PLANNING |

---

## 1. Motivation

The current optimizer (`hbopt.c`, 1,746 lines) is peephole-only: it
pattern-matches on the linear pcode byte stream. It can eliminate redundant
push/pop pairs and narrow variable offsets. That's it.

`hbdead.c` (609 lines) marks syntactically unreachable code with NOOPs after
unconditional jumps. It cannot eliminate dead branches based on constant
conditions, because it has no data-flow information.

With the persistent AST (Phase E) and CFG, real optimizations become possible.

---

## 2. Proposed Optimizations

### Phase G.1: Constant Folding (2 weeks)

Evaluate constant expressions at compile time:

```harbour
LOCAL n := 24 * 60 * 60    /* fold to 86400 */
LOCAL c := "FOO" + "BAR"   /* fold to "FOOBAR" */
```

AST walker replaces constant binary/unary expressions with their computed
result. Supports numeric arithmetic, string concatenation, logical operations.

### Phase G.2: Constant Propagation (2 weeks)

Track constant assignments through the CFG:

```harbour
LOCAL n := 10
LOCAL m := n * 2       /* n is known to be 10 → m = 20 */
IF m > 15              /* constant comparison → always true */
   ...                 /* dead branch eliminated */
ENDIF
```

Requires reaching-definitions analysis on the CFG from Phase E.3.

### Phase G.3: Dead Code Elimination (2 weeks)

Replace the current `hbdead.c` NOOP-filling with proper DCE:

- Remove assignments to variables that are never read (dead stores)
- Eliminate branches with constant conditions
- Remove unreachable code after proven-unconditional paths
- Actually shrink the pcode output (don't just NOOP-fill)

### Phase G.4: Common Subexpression Elimination (2 weeks)

Identify repeated expressions with identical operands:

```harbour
LOCAL a := Sqrt(x * x + y * y)
LOCAL b := Sqrt(x * x + y * y)   /* reuse computation from a */
```

Requires available-expressions analysis on the CFG.

---

## 3. Affected Files

| File | Lines | Change |
|------|-------|--------|
| `src/compiler/hbopt.c` | 1,746 | Retain existing peephole; add AST-based passes |
| `src/compiler/hbdead.c` | 609 | Replace NOOP-fill with proper DCE |
| `src/compiler/hbexpr.c` | new | Constant folder, propagator, CSE walker |

## 4. Dependencies

| Dependency | Status | Notes |
|------------|--------|-------|
| PersistentAST (Phase E) | PLANNING | **Required** — all optimizations walk the AST/CFG |

## 5. Estimated Scope

**8 weeks** total across 4 sub-phases, each shippable independently.

---

[<- Index](../INDEX.md) · [Map](../MAP.md) · **BRIEF**
