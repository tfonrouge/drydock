# ARCHITECTURE -- ScalarClasses (SUBSYSTEM)

## 1. Class Hierarchy

```mermaid
graph TD
    DO[DrydockObject<br/>C, always available<br/>toString, className, isScalar, isNil, valType]

    DO --> A[HBArray]
    DO --> BL[HBBlock]
    DO --> C[HBCharacter]
    DO --> D[HBDate]
    DO --> TS[HBTimeStamp]
    DO --> H[HBHash]
    DO --> L[HBLogical]
    DO --> N[HBNumeric]
    DO --> NI[HBNil]
    DO --> S[HBSymbol]
    DO --> P[HBPointer]

    DO -.-> UC["User classes<br/>(default parent)"]

    C -.->|"when tscalar.prg linked"| CM["+ Upper, Lower, Trim,<br/>Split, Reverse, etc."]
    N -.->|"when tscalar.prg linked"| NM["+ Abs, Int, Round,<br/>Between, etc."]
    A -.->|"when tscalar.prg linked"| AM["+ Map, Filter, Sort,<br/>Tail, Each, etc."]
```

Solid arrows = C-level inheritance (always available).
Dashed arrows = PRG-level extension (when linked).

## 2. Initialization Sequence

```mermaid
sequenceDiagram
    participant main as main()
    participant hvm as hb_vmInit()
    participant cls as hb_clsInit()
    participant do as hb_clsDoInit()
    participant prg as tscalar.prg

    main->>hvm: VM startup
    hvm->>cls: Initialize OO system
    cls->>cls: Register operator symbols
    cls->>cls: Create DrydockObject (root class)
    cls->>cls: Add toString, className, isScalar, isNil, valType
    cls->>cls: Create 11 scalar classes inheriting from DrydockObject
    cls->>cls: Associate each with HB_TYPE (s_uiCharacterClass, etc.)
    Note right of cls: Scalar classes are NOW LIVE<br/>toString() works on all values

    hvm->>hvm: hb_vmDoInitStatics()
    hvm->>hvm: hb_vmDoInitHVM()
    hvm->>do: Initialize PRG class factories
    do->>prg: If HBCHARACTER is linked:<br/>extend Character class with Upper, Lower, etc.
    do->>prg: If HBNUMERIC is linked:<br/>extend Numeric class with Abs, Int, etc.
    Note right of do: Rich methods now available<br/>(only if tscalar.prg linked)

    hvm->>hvm: hb_vmDoInitFunctions()
    hvm->>hvm: Execute user MAIN()
```

## 3. Method Dispatch Flow

```mermaid
flowchart TD
    CALL["'hello':toString()"] --> SEND["hb_vmSend()"]
    SEND --> GETM["hb_objGetMethod()"]

    GETM --> CHECK_ARRAY{"HB_IS_ARRAY?"}
    CHECK_ARRAY -->|Yes, uiClass != 0| OBJ_LOOKUP["Lookup in object's class"]
    CHECK_ARRAY -->|Yes, uiClass == 0| SCALAR_ARRAY["hb_clsScalarMethod(s_uiArrayClass)"]
    CHECK_ARRAY -->|No| CHECK_TYPE{"Check HB_TYPE"}

    CHECK_TYPE -->|HB_IS_STRING| SCALAR_CHAR["hb_clsScalarMethod(s_uiCharacterClass)"]
    CHECK_TYPE -->|HB_IS_NUMERIC| SCALAR_NUM["hb_clsScalarMethod(s_uiNumericClass)"]
    CHECK_TYPE -->|other types...| SCALAR_OTHER["hb_clsScalarMethod(s_ui*Class)"]

    SCALAR_CHAR --> FIND["hb_clsFindMsg(class, 'TOSTRING')"]
    SCALAR_NUM --> FIND
    SCALAR_ARRAY --> FIND
    SCALAR_OTHER --> FIND
    OBJ_LOOKUP --> FIND

    FIND -->|Found| EXEC["HB_VM_EXECUTE(method)"]
    FIND -->|Not found| DEFAULT{"Default messages?"}
    DEFAULT -->|toString| BUILTIN["Return &s___msgToString"]
    DEFAULT -->|className| BUILTIN2["Return &s___msgClassName"]
    DEFAULT -->|Not found| NOMETHOD["&s___msgNoMethod → error"]

    BUILTIN --> EXEC
    BUILTIN2 --> EXEC

    style CALL fill:#4CAF50,color:white
    style EXEC fill:#2196F3,color:white
    style NOMETHOD fill:#f44336,color:white
```

## 4. Two-Layer Method Resolution

**Layer 1 (C, always available):** DrydockObject methods are inherited by
all scalar classes. `toString()` is also a built-in default message (like
`className()`), so it works even on values whose scalar class has no explicit
toString method.

**Layer 2 (PRG, optional extension):** When `tscalar.prg` is linked, it
extends the pre-existing scalar classes with rich methods (Upper, Lower,
Split, Map, Filter, etc.) via `hb_clsAddMsg()`.

If a class defines its own `toString()`, it overrides the DrydockObject
default. This is standard method dispatch — subclass methods shadow parent
methods.

---

[<- Index](../INDEX.md) · [Map](../MAP.md) · [BRIEF](BRIEF.md) · [DESIGN](DESIGN.md) · **ARCH** · [API](C_API.md) · [COMPAT](COMPAT.md) · [PLAN](IMPLEMENTATION_PLAN.md) · [TESTS](TEST_PLAN.md) · [MATRIX](TRACEABILITY.md) · [AUDIT](AUDIT.md)
