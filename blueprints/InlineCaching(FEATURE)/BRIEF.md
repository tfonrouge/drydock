# BRIEF -- InlineCaching (FEATURE)

## Identity

| Field | Value |
|-------|-------|
| **Name** | InlineCaching |
| **Mode** | FEATURE |
| **Tier** | 3 — Unlock Performance |
| **Phase** | L |
| **Component** | VM — `src/vm/classes.c`, `src/vm/hvm.c` |
| **Status** | PLANNING |

---

## 1. Motivation

Every method call in Harbour goes through a hash table lookup in
`hb_objGetMethod()` (`classes.c:1802-2209`). This involves:

1. Get the object's class handle
2. Hash the method name symbol
3. Probe the class's method table (bucket-based, BUCKETSIZE=4)
4. Compare symbols until match found
5. Return the function pointer

This is O(1) amortized but has high constant overhead: hash computation,
memory indirection, cache misses on the method table. For polymorphic code
(e.g., iterating over mixed-type collections), this cost dominates.

**Inline caching** stores the result of method lookup at the call site:

- **Monomorphic**: cache one (class, method) pair. If the receiver's class
  matches, skip lookup entirely.
- **Polymorphic**: cache N pairs (typically 4-8). Handles common polymorphism.
- **Megamorphic**: fall back to hash lookup (current behavior).

Published results from V8, SpiderMonkey, and YJIT show **2-5x speedup** on
OO-heavy code with inline caching.

---

## 2. Scope

- Add inline cache structure to `HB_P_MESSAGE`/`HB_P_SEND` opcode sites
- Monomorphic cache: 1 class + 1 function pointer per call site
- Cache invalidation on class modification (`__clsAddMsg`, `__clsDelMsg`)
- Polymorphic upgrade when monomorphic cache misses on a different class
- Megamorphic fallback preserves current behavior

**Module system note**: Inline caches are keyed on (class handle, method
symbol) pairs. Namespace-qualified class names resolve to the same class
handles at runtime — namespaces are a compile-time concept. Therefore,
inline caching does not need invalidation when modules are loaded, because
class identity is unchanged by namespace qualification.

---

## 3. Dependencies

| Dependency | Status | Notes |
|------------|--------|-------|
| ScalarClasses (Phase B) | PLANNING | Recommended — scalar classes add more dispatch sites that benefit from caching |
| ComputedGoto (Phase C) | PLANNING | Recommended — threaded dispatch reduces overhead per cached call |

## 4. Estimated Scope

**4 weeks** — cache structure, hit/miss logic, invalidation protocol.

---

[<- Index](../INDEX.md) · [Map](../MAP.md) · **BRIEF**
