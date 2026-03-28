# TEST_PLAN -- ScalarClasses (SUBSYSTEM)

## Phase 1: User-Facing Methods

### TEST-SC1-001: Existing Scalar Methods Still Work
- **Type**: Regression
- **Covers**: Phase 1 — no existing behavior broken
- **Action**: `ddtest`
- **Expected**: 4861/4861 tests pass

### TEST-SC1-002: Character Methods
- **Type**: New
- **Covers**: S1.2 — Character class user-facing methods
- **Action**: Compile and run test program:
  ```prg
  ? "hello":Upper()       // "HELLO"
  ? "HELLO":Lower()       // "hello"
  ? "  hi  ":Trim()       // "hi"
  ? "hello":Left(3)       // "hel"
  ? "hello":Right(3)      // "llo"
  ? "hello":SubStr(2,3)   // "ell"
  ? "hello":Len()         // 5
  ? "hello":Empty()       // .F.
  ? "":Empty()            // .T.
  ? "hello":At("ll")      // 3
  ? "ha":Replicate(3)     // "hahaha"
  ? "a,b,c":Split(",")   // {"a","b","c"}
  ```
- **Expected**: All expressions return the documented values

### TEST-SC1-003: Numeric Methods
- **Type**: New
- **Covers**: S1.3 — Numeric class methods
- **Action**:
  ```prg
  ? (-5):Abs()            // 5
  ? (3.7):Int()           // 3
  ? (3.14159):Round(2)    // 3.14
  ? (42):Str()            // "42"
  ? (5):Min(3)            // 3
  ? (5):Max(10)           // 10
  ? (0):Empty()           // .T.
  ```

### TEST-SC1-004: Date/TimeStamp Methods
- **Type**: New
- **Covers**: S1.4 — Date class methods
- **Action**:
  ```prg
  LOCAL d := CToD("01/15/2026")
  ? d:AddDays(10)         // date 10 days later
  ? d:DOW()               // 5 (Thursday)
  ? d:Empty()             // .F.
  ```

### TEST-SC1-005: Array Methods
- **Type**: New
- **Covers**: S1.5 — Array class methods
- **Action**:
  ```prg
  LOCAL a := {1,2,3,4,5}
  ? a:Len()               // 5
  ? a:Empty()             // .F.
  ? a:Tail()              // 5
  ? a:Map({|x| x*2})     // {2,4,6,8,10}
  ? a:Filter({|x| x>3})  // {4,5}
  ```

### TEST-SC1-006: Hash Methods
- **Type**: New
- **Covers**: S1.6 — Hash class methods
- **Action**:
  ```prg
  LOCAL h := {"a"=>1, "b"=>2}
  ? h:Len()               // 2
  ? h:HasKey("a")         // .T.
  ? h:Keys()              // {"a","b"}
  ? h:Values()            // {1,2}
  ```

### TEST-SC1-007: hb_objGetScalarClass API
- **Type**: New
- **Covers**: S1.1 — public C API function
- **Action**: Verify the function exists via:
  `grep "hb_objGetScalarClass" include/hbapicls.h src/harbour.def`
- **Expected**: Found in both files

---

## Phase 1b: DrydockObject Root Class + Always-Available Scalars

### TEST-SC1b-001: toString Works Without Any Includes
- **Type**: New — the core test
- **Covers**: S1b.1 — toString as built-in message
- **Action**: Compile and run a .prg with NO includes, NO REQUEST, NO ENABLE:
  ```prg
  PROCEDURE MAIN()
     ? "hello":toString()     // "hello"
     ? (42):toString()        // "42"
     ? .T.:toString()         // ".T."
     ? NIL:toString()         // "NIL"
     ? Date():toString()      // date string
     ? {1,2,3}:toString()     // "{...}"
     RETURN
  ```
- **Expected**: All lines produce output. No errors.

### TEST-SC1b-002: className Works on All Types
- **Type**: New
- **Covers**: S1b.2 — DrydockObject base methods
- **Action**:
  ```prg
  ? "hello":className()      // "CHARACTER"
  ? (42):className()         // "NUMERIC"
  ? .T.:className()          // "LOGICAL"
  ? NIL:className()          // "NIL"
  ? {}:className()           // "ARRAY"
  ? {=>}:className()         // "HASH"
  ```

### TEST-SC1b-003: isScalar and isNil
- **Type**: New
- **Covers**: S1b.2 — universal methods
- **Action**:
  ```prg
  ? "hello":isScalar()       // .T.
  ? (42):isScalar()          // .T.
  ? NIL:isNil()              // .T.
  ? "hello":isNil()          // .F.
  ```

### TEST-SC1b-004: Scalar ClassH Is Non-Zero
- **Type**: New
- **Covers**: S1b.3 — scalar classes registered in C
- **Action**:
  ```prg
  ? "hello":classH()         // non-zero (class exists)
  ? (42):classH()            // non-zero
  ? NIL:classH()             // non-zero
  ```
- **Expected**: All ClassH values > 0

### TEST-SC1b-005: No Regression
- **Type**: Regression
- **Action**: `ddtest`
- **Expected**: 4861/4861 tests pass

### TEST-SC1b-006: Rich Methods Still Work When Linked
- **Type**: Regression
- **Covers**: S1b.4 — tscalar.prg extends C-created classes
- **Action**: Run tests/scalar.prg (which uses ENABLE TYPE CLASS ALL)
- **Expected**: 55/55 tests pass (same as Phase 1a)

---

## Phase 2: Operator Methods

### TEST-SC2-001: Recursion Safety
- **Type**: New — the critical safety test
- **Covers**: S2.6 — inline cascade prevents infinite recursion
- **Action**: After adding OPERATOR "+" to Character class, run:
  ```prg
  ? "hello" + " world"   // must return "hello world", not stack overflow
  ```
- **Expected**: Returns "hello world" — inline cascade handles str+str before
  operator dispatch. No infinite recursion.

### TEST-SC2-002: Operator Flags Set
- **Type**: New
- **Covers**: S2.1-S2.5 — nOpFlags bits set for scalar classes
- **Action**: Check that `hb_objHasOperator` returns .T. for scalar types:
  ```prg
  ? "hello":ClassName()   // "CHARACTER" — scalar class is registered
  ```
  (Operator flag verification requires C-level check or a test PRG that
  exercises cross-type operations.)

### TEST-SC2-003: No Regression
- **Type**: Regression
- **Action**: `ddtest`
- **Expected**: 4861/4861 tests pass

---

## Phase 4: Performance

### TEST-SC4-001: Integer Arithmetic Baseline
- **Type**: Performance
- **Action**: `n := n + 1` x 10M iterations
- **Threshold**: < 1% regression vs pre-ScalarClasses baseline

### TEST-SC4-002: String Concatenation Baseline
- **Type**: Performance
- **Action**: `c := c + c` x 1M iterations
- **Threshold**: 0% regression (inline path unchanged)

### TEST-SC4-003: Scalar Method Dispatch
- **Type**: Performance — new baseline
- **Action**: `"hello":Upper()` x 1M iterations
- **Threshold**: Establish baseline (no prior measurement)

---

[<- Index](../INDEX.md) · [Map](../MAP.md) · [BRIEF](BRIEF.md) · [DESIGN](DESIGN.md) · [API](C_API.md) · [COMPAT](COMPAT.md) · **TESTS** · [MATRIX](TRACEABILITY.md) · [AUDIT](AUDIT.md)
