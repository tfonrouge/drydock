# BRIEF -- ComputedGoto (SUBSYSTEM)

## Identity

| Field | Value |
|-------|-------|
| **Name** | ComputedGoto |
| **Mode** | SUBSYSTEM |
| **Tier** | 1 — Fix the Foundation |
| **Phase** | C |
| **Component** | VM — `src/vm/hvm.c` |
| **Status** | PLANNING |

---

## 1. Motivation

The Harbour VM interpreter (`hb_vmExecute` in `hvm.c:1387-2964`) dispatches
181 opcodes via a single `switch` statement. While GCC/Clang may optimize this
to a jump table, the compiler is not guaranteed to do so — and even when it
does, the `switch` model forces an indirect branch through a single dispatch
point, defeating CPU branch prediction.

Modern interpreters (CPython 3.12, Lua 5.4, Ruby YJIT baseline) use **computed
goto** (GCC's `&&label` extension) to implement **threaded dispatch**: each
opcode handler jumps directly to the next handler's address, eliminating the
central dispatch branch entirely.

Published benchmarks show **5-15% improvement** on interpreter-bound workloads.
This is free performance with minimal code change.

---

## 2. Current State

```c
/* hvm.c — current dispatch (simplified) */
for( ;; )
{
   /* periodic key poll every 65536 ops */
   switch( *pCode )
   {
      case HB_P_PLUS:
         hb_vmPlus( ... );
         pCode++;
         break;
      case HB_P_MINUS:
         hb_vmMinus( ... );
         pCode++;
         break;
      /* ... 179 more cases ... */
   }
}
```

Problems:

- **Single branch predictor entry** — all 181 opcodes compete for the same
  indirect branch prediction slot, causing frequent mispredictions
- **No tail dispatch** — every case exits to the switch top, adding one
  unconditional jump per opcode
- **Key poll check** — the counter check and modulo at the loop top adds
  overhead on every iteration
- **MSVC compatibility** — the `switch` works everywhere, but so does the
  fallback (see Portability below)

---

## 3. Proposed Change

### 3.1 Dispatch Table

```c
#if defined(__GNUC__) || defined(__clang__)
#  define HB_VM_THREADED_DISPATCH
#endif

#ifdef HB_VM_THREADED_DISPATCH

static const void * s_dispatchTable[ HB_P_LAST_PCODE ] = {
   [HB_P_AND]          = &&op_and,
   [HB_P_PLUS]         = &&op_plus,
   [HB_P_MINUS]        = &&op_minus,
   /* ... all 181 opcodes ... */
};

#define DISPATCH()       goto *s_dispatchTable[ *pCode ]
#define OPCODE( name )   op_##name:
#define NEXT()           DISPATCH()

#else /* switch fallback for MSVC */

#define DISPATCH()       break
#define OPCODE( name )   case HB_P_##name:
#define NEXT()           break

#endif
```

### 3.2 Handler Pattern

```c
OPCODE( PLUS )
{
   hb_vmPlus( hb_stackItemFromTop( -2 ),
              hb_stackItemFromTop( -2 ),
              hb_stackItemFromTop( -1 ) );
   hb_stackPop();
   pCode++;
   NEXT();
}
```

With `HB_VM_THREADED_DISPATCH`, `NEXT()` expands to `goto *s_dispatchTable[*pCode]`
— a direct jump to the next handler. Without it, `NEXT()` expands to `break`,
which falls through to the existing `switch`.

### 3.3 Key Poll Integration

Move the periodic key poll into a dedicated opcode or inline it with a
decrement-and-branch pattern:

```c
#define HB_VM_CHECK_POLL()                           \
   do {                                               \
      if( HB_UNLIKELY( --nPollCounter == 0 ) )        \
      {                                                \
         nPollCounter = 65536;                         \
         /* key poll, thread request check, profiler */ \
      }                                                \
   } while( 0 )
```

This replaces the modulo check (`ulCurrCount++ % 65536`) with a simple
decrement, which is cheaper on all architectures.

---

## 4. Portability

| Compiler | Support | Strategy |
|----------|---------|----------|
| GCC 3.1+ | Computed goto (`&&label`) | Threaded dispatch |
| Clang 3.0+ | Computed goto | Threaded dispatch |
| MSVC | No computed goto | Switch fallback (identical to current) |
| Watcom | No computed goto | Switch fallback |
| Intel ICC | Computed goto | Threaded dispatch |

The `#ifdef HB_VM_THREADED_DISPATCH` guard ensures **zero regression** on
compilers that don't support computed goto — they get exactly the current code.

---

## 5. Affected Files

| File | Lines | Change |
|------|-------|--------|
| `src/vm/hvm.c` | 12,572 | Refactor `hb_vmExecute` switch to macro-based dispatch |
| `include/hbdefs.h` | ~600 | Add `HB_VM_THREADED_DISPATCH` detection macro |

## 6. Affected Structs

None. Pure control-flow refactoring.

## 7. Compatibility Stance

**Target: 100% source and ABI compatibility.**

No behavior change. No new opcodes. No struct changes. The dispatch table
contains the same opcodes in the same order, executing the same handlers.

## 8. Performance Stance

**Must improve or match. Must not regress.**

- Benchmark: tight arithmetic loop (`n := n + 1` x 10M), string ops, method
  dispatch, mixed workload
- Expected: 5-15% improvement on GCC/Clang
- MSVC: identical performance (switch fallback)
- The key poll optimization (decrement vs modulo) benefits all platforms

## 9. Dependencies

| Dependency | Status | Notes |
|------------|--------|-------|
| RefactorHvm Phases 0-1 | PLANNING | Cleaner hvm.c makes the macro refactoring safer; not strictly required but strongly recommended |

## 10. Estimated Scope

| Phase | Effort | Can Ship Independently |
|-------|--------|----------------------|
| Dispatch table + macros | 2-3 days | Yes |
| Key poll optimization | 0.5 day | Yes |
| Benchmarking | 1 day | — |
| **Total** | **3-4 days** | |

---

[<- Index](../INDEX.md) · [Map](../MAP.md) · **BRIEF**
