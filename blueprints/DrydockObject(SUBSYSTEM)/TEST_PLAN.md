# TEST_PLAN -- DrydockObject (SUBSYSTEM)

## Phase D.1: toString Built-In Message

### TEST-D1-001: toString on All Types (No Includes)
- **Type**: New — the fundamental test
- **Covers**: D.1.1-D.1.4
- **Setup**: Compile .prg with NO includes, NO REQUEST, NO ENABLE
- **Action**:
  ```prg
  PROCEDURE MAIN()
     ? "hello":toString()      // "hello"
     ? (42):toString()         // "42"
     ? (3.14):toString()       // "3.14"
     ? .T.:toString()          // ".T."
     ? .F.:toString()          // ".F."
     ? NIL:toString()          // "NIL"
     ? Date():toString()       // date string
     ? {1,2,3}:toString()      // "{ ... }"
     ? {=>}:toString()         // "{ => }"
     RETURN
  ```
- **Expected**: All lines produce output. No errors. No includes needed.

### TEST-D1-002: No Regression
- **Type**: Regression
- **Action**: `ddtest`
- **Expected**: 4861/4861 pass

---

## Phase D.2: DrydockObject Root Class

### TEST-D2-001: Universal Methods
- **Type**: New
- **Action**:
  ```prg
  ? "hello":isScalar()        // .T.
  ? (42):isScalar()           // .T.
  ? NIL:isNil()               // .T.
  ? "hello":isNil()           // .F.
  ? "hello":valType()         // "C"
  ? (42):valType()            // "N"
  ? .T.:valType()             // "L"
  ```
- **Expected**: All correct values returned

### TEST-D2-002: className via Class Method
- **Type**: New
- **Action**:
  ```prg
  ? "hello":className()       // "CHARACTER"
  ? (42):className()          // "NUMERIC"
  ? NIL:className()           // "NIL"
  ? {}:className()            // "ARRAY"
  ```
- **Expected**: Same values as before (no change in behavior)

### TEST-D2-003: No Regression
- **Type**: Regression
- **Action**: `ddtest`
- **Expected**: 4861/4861 pass

---

## Phase D.3: Scalar Classes in C

### TEST-D3-001: ClassH Non-Zero Without Linking
- **Type**: New — proves scalar classes are always registered
- **Action**:
  ```prg
  /* No ENABLE TYPE CLASS ALL, no REQUEST */
  ? "hello":classH()          // > 0
  ? (42):classH()             // > 0
  ? NIL:classH()              // > 0
  ? .T.:classH()              // > 0
  ? {}:classH()               // > 0
  ? {=>}:classH()             // > 0
  ```
- **Expected**: All ClassH values > 0 (classes exist)

### TEST-D3-002: Inheritance from DrydockObject
- **Type**: New
- **Action**: Verify scalar classes inherit DrydockObject methods
  ```prg
  ? "hello":toString()        // works via inherited method
  ? "hello":isScalar()        // works via inherited method
  ```

### TEST-D3-003: No Regression
- **Type**: Regression
- **Action**: `ddtest`
- **Expected**: 4861/4861 pass

---

## Phase D.4: hb_clsDoInit Extend-Not-Create

### TEST-D4-001: Rich Methods With ENABLE TYPE CLASS ALL
- **Type**: Regression
- **Action**: Run existing tests/scalar.prg (uses ENABLE TYPE CLASS ALL)
- **Expected**: 55/55 tests pass (Upper, Lower, Split, etc.)

### TEST-D4-002: Base Methods Without ENABLE
- **Type**: New
- **Action**: Compile test with NO ENABLE:
  ```prg
  ? "hello":toString()        // works
  ? "hello":className()       // works
  ? "hello":isScalar()        // works
  ```
- **Expected**: Base methods work

### TEST-D4-003: Rich Methods Without ENABLE Error Correctly
- **Type**: New
- **Action**: Without ENABLE TYPE CLASS ALL:
  ```prg
  ? "hello":Upper()           // should error — rich method not linked
  ```
- **Expected**: Error BASE/1004 (method not found)

### TEST-D4-004: No Regression
- **Type**: Regression
- **Action**: `ddtest`
- **Expected**: 4861/4861 pass

---

[<- Index](../INDEX.md) · [Map](../MAP.md) · [BRIEF](BRIEF.md) · [DESIGN](DESIGN.md) · [PLAN](IMPLEMENTATION_PLAN.md) · **TESTS** · [AUDIT](AUDIT.md)
