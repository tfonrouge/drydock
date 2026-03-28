# Drydock Object-Oriented System Specification

**Status**: Living document
**Purpose**: Authoritative specification for all OO-related work in Drydock
**Audience**: Contributors working on DrydockObject, ScalarClasses, ExtensionMethods,
Reflection, GradualTyping, InlineCaching, or any feature that touches the class system

---

## 1. Current OO Capabilities (Inherited from Harbour)

The Harbour OO engine is a mature, message-based object system implemented in C
(`src/vm/classes.c`, ~5,600 lines) with PRG-level class management (`src/rtl/tclass.prg`,
`src/rtl/tobject.prg`). It supports multiple inheritance, operator overloading,
delegation, synchronization, and runtime reflection.

### Feature Matrix

| Feature | Status | Implementation |
|---------|--------|----------------|
| Single inheritance | Yes | Primary superclass (first in FROM list) |
| Multiple inheritance | Yes | Depth-first, first-parent primary; additional parents merged |
| Virtual methods | Yes | Default behavior; dynamic dispatch at runtime |
| Non-virtual methods | Yes | `@:method()` syntax forces parent-class dispatch |
| Abstract/deferred methods | Partial | `VIRTUAL` message compiles to stub; no instantiation check |
| Constructors | Yes | `CONSTRUCTOR` keyword; `:New()` / `:Init()` pattern |
| Destructors | Yes | Auto-called by GC; timing unpredictable |
| Instance variables (DATA) | Yes | Per-instance storage in array slots |
| Class variables (CLASSDATA) | Yes | Shared or per-subclass; `SHARED` keyword |
| Properties | Yes | `PROPERTY` keyword; auto getter/setter with `PERSIST` flag |
| Method visibility | Yes | EXPORTED (public), PROTECTED (subclass), HIDDEN (same class only) |
| Read-only members | Yes | `READONLY` keyword |
| Operator overloading | Yes | 30 operators: arithmetic, comparison, logical, indexing, enumeration |
| Delegation | Yes | `MESSAGE x TO oDelegate` — message forwarding |
| Synchronized methods | Yes | `SYNC` keyword — mutex-protected; per-instance or per-class |
| Friend access | Yes | `FRIEND CLASS` / `FRIEND FUNCTION` — bypasses visibility checks |
| Inline methods | Yes | `MESSAGE x INLINE code` — codeblock-based methods |
| Error handling (OnError) | Yes | `ON ERROR handler` — fallback for unknown messages |
| Perform (dynamic dispatch) | Yes | `:Perform(cMsg, ...)` — runtime message name resolution |
| FOR EACH support | Yes | 8 enumeration operators (__ENUMSTART through __ENUMISLAST) |
| Scalar type classes | Yes | `ASSOCIATE CLASS x WITH TYPE y` — methods on strings, numbers, etc. |
| Reflection | Yes | `:ClassName()`, `:ClassH()`, `:ClassSel()`, `hb_objHasMsg()` |
| Type declarations | Partial | `AS type` compiles but is NOT enforced at runtime |
| Class methods | No | `HB_OO_MSG_CLSMTHD` reserved but unimplemented |
| Interfaces | No | No `INTERFACE` keyword; use `VIRTUAL` messages as workaround |
| Generics | No | Not supported |
| Metaclass protocol | No | HBClass is a builder, not a true metaclass |

### Operator Overloading Detail (30 Operators)

**Arithmetic (0-7):** `+`, `-`, `*`, `/`, `%`, `^`, `++`, `--`
**Comparison (8-14):** `=`, `==`, `!=`, `<`, `<=`, `>`, `>=`
**Assignment/Membership (15-17):** `:=`, `$` (substring), `$` (containment)
**Logical (18-20):** `!`/`.NOT.`, `.AND.`, `.OR.`
**Indexing (21):** `[]`
**Enumeration (22-29):** `__ENUMINDEX`, `__ENUMBASE`, `__ENUMVALUE`,
`__ENUMSTART`, `__ENUMSKIP`, `__ENUMSTOP`, `__ENUMISFIRST`, `__ENUMISLAST`

Each class tracks overloaded operators via a 32-bit `nOpFlags` bitmask.

### Visibility Scoping

| Scope | Accessible From | Inherited? |
|-------|----------------|------------|
| EXPORTED | Anywhere | Yes |
| PROTECTED | Same class + subclasses | Yes |
| HIDDEN | Same class only | No |

Scope is checked at **runtime** by `hb_clsValidScope()`. No compile-time enforcement.

---

## 2. Gap Analysis

### 2.1 No Root Class With Universal Methods

**Problem**: There is no guaranteed base class with methods that work on every value.
`HBObject` exists but is PRG-level, optional (requires linking), and doesn't cover
scalar types. A debugger can't call `toString()` on an arbitrary value.

**Impact**: Every tool that needs string representation of values (debugger, logger,
error handler, REPL) must implement its own type-switch cascade.

**Resolution**: DrydockObject (Tier 1, FOCUSED)

### 2.2 Scalar Classes Require Explicit Linking

**Problem**: `"hello":Upper()` only works if `tscalar.prg` is linked via
`ENABLE TYPE CLASS ALL` or `REQUEST HBCharacter`. Scalar classes are a library
feature, not a language feature.

**Impact**: Cannot assume methods exist on scalar values. Every program that uses
scalar methods must include boilerplate setup.

**Resolution**: DrydockObject creates scalar classes in C during VM init (Tier 1)

### 2.3 No Abstract Classes or Interfaces

**Problem**: `VIRTUAL` messages compile to empty stubs. There's no way to declare
"this class cannot be instantiated" or "implementors must provide these methods."
Contract violations are discovered at runtime, not at compile time.

**Impact**: Large codebases can't enforce API contracts. Refactoring is risky because
missing method implementations aren't caught until execution.

**Resolution**: GradualTyping (Tier 2) — add `ABSTRACT CLASS` and `INTERFACE` keywords

### 2.4 Type Declarations Not Enforced

**Problem**: `DATA name AS CHARACTER` compiles and runs but the type constraint is
never checked. Any type can be assigned to any DATA regardless of declaration.

**Impact**: Type annotations are documentation, not contracts. Developers get false
confidence from declarations that are actually ignored.

**Resolution**: GradualTyping (Tier 2) — compile-time warnings, optional runtime checks

### 2.5 CLASS METHOD Unimplemented

**Problem**: `HB_OO_MSG_CLSMTHD = 7` is reserved in hboo.ch but never implemented.
Class methods (methods on the class itself, not instances) are fundamental in every
major OO language.

**Impact**: No factory patterns via class methods. No class-level initialization.
Workaround: use module-level functions instead.

**Resolution**: DrydockObject Phase 2 or dedicated blueprint

### 2.6 No Metaclass Protocol

**Problem**: Classes are functions, not objects. `MyClass` is callable but not
messageable. You can't call `MyClass:instances()` or `MyClass:subclasses()`.

**Impact**: No true reflection at the class level. Can't build frameworks that
operate on classes as first-class values.

**Resolution**: Future work — requires making classes themselves be DrydockObject instances

### 2.7 Unpredictable Destructor Timing

**Problem**: Destructors run during GC, which can happen at any time. Resources
(file handles, database connections, network sockets) may not be released promptly.

**Impact**: Resource leaks in long-running applications. Same problem that led Java
to deprecate finalizers.

**Resolution**: Add `dispose()` protocol to DrydockObject. `WITH object ... END WITH`
auto-calls dispose. Destructor remains as safety net.

### 2.8 No Standard Equality/Hashing Protocol

**Problem**: `==` on objects compares identity (array reference), not value equality.
There's no `equals()` or `hashCode()` convention. Objects can't be used as hash keys
based on their content.

**Impact**: Can't build value-based collections. Can't compare objects semantically.

**Resolution**: DrydockObject Phase 2 — add `equals(other)` and `hashCode()` as
universal methods with overridable defaults.

### 2.9 Runtime-Only Scope Checking

**Problem**: PROTECTED and HIDDEN visibility is checked at dispatch time, not compile
time. A method call to a HIDDEN member compiles successfully but errors at runtime.

**Impact**: No IDE or compiler can catch visibility violations. Developers discover
access errors only during testing.

**Resolution**: GradualTyping (Tier 2) — scope checking as compile-time warnings

### 2.10 Method Lookup Performance

**Problem**: Method dispatch uses hash tables with 4-element bucket chains. Every
method call involves hash computation, pointer chasing, and comparison. No inline
caching or vtable optimization.

**Impact**: OO dispatch is measurably slower than direct function calls. Tight loops
with method calls are performance-sensitive.

**Resolution**: InlineCaching (Tier 3) — monomorphic/polymorphic caches at call sites

### 2.11 Method/Property Ambiguity

**Problem**: `obj:name` and `obj:name()` are syntactically identical — both are
message sends. The caller cannot distinguish a cheap DATA read from an expensive
METHOD computation. The `DATA name` declaration creates getter/setter method
pairs (`NAME` / `_NAME`), but nothing distinguishes them from regular methods.
Parentheses are optional on method calls, further blurring the line.

**Impact**: Code readability suffers — the reader must know the class definition
to understand whether `obj:count` is O(1) data access or O(n) computation.
Serializers and debuggers can't distinguish stored vs computed values without
class metadata. No property validation exists — `obj:age := -500` silently
accepts invalid values.

**Resolution** (phased):
- DrydockObject Phase 2: `isProperty()`, `isReadOnly()` reflection methods
- Tier 1: PROPERTY VALIDATE blocks for assignment constraints
- Tier 1: Computed properties via `PROPERTY x GET expr SET expr`
- Tier 2 (GradualTyping): AS type enforcement, optional strict parentheses warnings

### 2.12 No Property Validation

**Problem**: Instance variables declared with `DATA name AS CHARACTER` accept any
type on assignment — the `AS type` annotation is decorative, never enforced. There
is no built-in mechanism to validate property values on assignment.

**Impact**: Data integrity relies entirely on developer discipline. Invalid states
are silently accepted and propagate through the application until they cause a
runtime error far from the source.

**Resolution** (phased):
- Tier 1: PROPERTY VALIDATE `{ |value| constraint }` blocks executed on assignment
- Tier 2 (GradualTyping): AS type enforcement at compile time with optional runtime checks

### 2.13 Function Parameters Are Untyped and Unchecked

**Problem**: Harbour function parameters have no type enforcement, no count
validation, no default values, no named parameter support, and no overloading.
`AS type` annotations are decorative — never checked by compiler or runtime.
Callers can pass too few arguments (silently NIL) or too many (silently ignored).
Parameter names are lost in compiled output.

```prg
FUNCTION Calculate(a AS NUMERIC, b AS NUMERIC)
   RETURN a + b

Calculate("hello")          // No error — a="hello", b=NIL, crashes on +
Calculate(1, 2, 3, 4, 5)    // No error — extras silently ignored
```

**Impact**: Functions are black boxes. The caller has no contract to follow.
Bugs from wrong argument types or counts are discovered only at runtime. No IDE
can provide meaningful autocomplete or validation. Every function must manually
check for NIL to implement defaults.

**Resolution** (Tier 2, requires PersistentAST + GradualTyping):
- Default parameter values: `FUNCTION f(x, y := 10)`
- Parameter type warnings: `AS NUMERIC` checked at compile time
- Parameter count warnings: too few / too many arguments
- Union types: `AS NUMERIC | CHARACTER` for multi-type parameters
- Named parameters: `f(width: 100, height: 200)` via hash sugar
- Parameter name preservation in AST for debugger/reflection

### 2.14 No Function Overloading

**Problem**: Harbour's symbol table maps each function name to a single function
pointer. There is no mechanism for multiple functions with the same name but
different parameter signatures. Developers use `SWITCH ValType()` inside a
single function to handle different types.

**Impact**: Common patterns like `Format(number)` vs `Format(date)` vs
`Format(string)` require manual type dispatch. This is verbose, error-prone,
and not discoverable by tools.

**Resolution**: Function overloading is **not planned** for Drydock. The
language's dynamic nature, single-entry symbol table, and macro/code-block
system all assume one function per name. Instead, Drydock provides equivalent
capability through:
- Union types: `FUNCTION Format(x AS NUMERIC | CHARACTER | DATE)`
- MATCH expression: type-aware pattern matching inside functions
- Named parameters: solve the "too many positional args" problem
- Default values: solve the "optional args" problem

### 2.15 No Module-Level Encapsulation

**Problem**: All public functions and classes are globally visible. There is no
file-level or module-level boundary beyond `STATIC FUNCTION` (which provides
file-local hiding but no controlled export). The dynamic symbol table
(`src/vm/dynsym.c`) is a flat namespace where name collisions are resolved by
load order. There is no way to explicitly import/export symbols between
compilation units.

This interacts with the OO system in several ways:
- `FRIEND CLASS` declarations (Feature Matrix, row 37) currently take flat
  class names. When classes live in namespaces, FRIEND declarations must
  reference qualified names across module boundaries.
- Extension methods (`EXTEND CLASS`, Section 4 target state) have scoping
  questions: does an extension declared in one module apply globally or only
  within the declaring module?
- `INTERFACE` (Section 2.3 resolution) will need to be referenced across
  namespace boundaries — a class in one module implementing an interface
  from another requires import.

**Impact**: Large codebases suffer from accidental name shadowing. The contrib
ecosystem (74 packages) avoids collisions through naming conventions (prefixes
like `hbct_`, `hbwin_`) rather than language-level encapsulation. Encapsulation
— a core OO principle — stops at the class boundary.

**Resolution**: ModuleSystem (Tier 2) — `MODULE`/`IMPORT`/`EXPORT` syntax with
namespace-qualified symbol resolution. See
[ModuleSystem blueprint](../../blueprints/ModuleSystem(FEATURE)/BRIEF.md).

---

## 3. Universal Protocols

Every value in Drydock should support these methods, inherited from DrydockObject:

### Core Protocols (DrydockObject Phase 1)

| Method | Returns | Default Behavior | Override? |
|--------|---------|-----------------|-----------|
| `toString()` | String | Type-appropriate representation | Yes |
| `className()` | String | Class/type name | Rarely |
| `isScalar()` | Logical | `.T.` for scalars, `.F.` for objects | No |
| `isNil()` | Logical | `.T.` only for NIL | No |
| `valType()` | String | Traditional type code ("C", "N", etc.) | No |
| `compareTo(other)` | Numeric/NIL | -1, 0, or 1 for ordered types; NIL for incomparable | Yes |
| `isComparable()` | Logical | `.T.` for string, numeric, date, timestamp, logical | No |

### Extended Protocols (DrydockObject Phase 2, future)

| Method | Returns | Default Behavior | Override? |
|--------|---------|-----------------|-----------|
| `equals(other)` | Logical | Identity comparison (same reference) | Yes |
| `hashCode()` | Numeric | Based on identity | Yes (must be consistent with equals) |
| `clone()` | Same type | Shallow copy | Yes |
| `deepClone()` | Same type | Recursive deep copy | Yes |
| `dispose()` | NIL | Explicit resource cleanup | Yes |
| `isProperty(cName)` | Logical | `.T.` if message is a DATA getter/setter | No |
| `isReadOnly(cName)` | Logical | `.T.` if message is read-only (no setter) | No |

### Protocol Rules

1. `equals()` and `hashCode()` must be consistent: if `a:equals(b)` then
   `a:hashCode() == b:hashCode()`.
2. `clone()` returns a new object; `a:clone():equals(a)` should be `.T.`
   but `a:clone() == a` (identity) should be `.F.`.
3. `dispose()` must be idempotent (safe to call multiple times).
4. `toString()` must never error or recurse infinitely.
5. `compareTo()` must define a total ordering when overridden.

---

## 4. Target State

When all planned work is complete, Drydock's OO system will provide:

### Every Value Is an Object
```prg
? "hello":toString()           // "hello" — always works, no setup
? (42):className()             // "NUMERIC"
? NIL:isNil()                  // .T.
? {1,2,3}:map({|x| x * 2})    // {2,4,6}
? Date():addDays(30)           // date 30 days from now
```

### Universal Base Class
```prg
CLASS MyApp
   // Automatically inherits from DrydockObject
   // Gets toString(), className(), equals(), etc. for free
   DATA name
   METHOD toString() INLINE "MyApp: " + ::name
ENDCLASS
```

### Property Validation (Tier 1)
```prg
CLASS Person
   PROPERTY name AS CHARACTER INIT "" VALIDATE { |v| ! Empty(v) }
   PROPERTY age AS NUMERIC INIT 0 VALIDATE { |v| v >= 0 .AND. v <= 150 }

   // Computed property (read-only)
   PROPERTY fullName READONLY GET ::firstName + " " + ::lastName

   // Computed property (read-write)
   PROPERTY diameter GET ::radius * 2 SET ::radius := value / 2
ENDCLASS

o:name := ""       // Raises validation error
o:age := -5        // Raises validation error
? o:fullName       // Computed, read-only
o:diameter := 10   // Sets radius to 5

// Reflection
? o:isProperty("name")      // .T. — stored DATA
? o:isProperty("fullName")  // .T. — computed PROPERTY
? o:isProperty("toString")  // .F. — regular METHOD
? o:isReadOnly("fullName")  // .T. — no setter
```

### Type-Safe Declarations (Tier 2)
```prg
CLASS Account
   DATA balance AS NUMERIC INIT 0    // Enforced at compile time
   DATA owner AS CHARACTER           // Warning if assigned non-string
   METHOD deposit(amount AS NUMERIC) // Parameter type checked
ENDCLASS
```

### Function Parameters (Tier 2)
```prg
// Default parameter values
FUNCTION Greet(cName AS CHARACTER, cGreeting AS CHARACTER := "Hello")
   RETURN cGreeting + ", " + cName

Greet("Juan")                 // cGreeting defaults to "Hello"
Greet("Juan", "Hi")           // cGreeting = "Hi"

// Parameter type warnings
FUNCTION Calculate(a AS NUMERIC, b AS NUMERIC) AS NUMERIC
   RETURN a + b

Calculate("hello", 5)         // Compile-time WARNING: arg 1 expects NUMERIC

// Parameter count warnings
Calculate(1)                  // Warning: expects 2 arguments, got 1

// Union types — function accepts multiple types
FUNCTION Format(x AS NUMERIC | CHARACTER | DATE) AS CHARACTER
   MATCH x:valType()
      CASE "N" ; RETURN hb_ntos(x)
      CASE "C" ; RETURN x
      CASE "D" ; RETURN DToC(x)
   ENDMATCH

// Named parameters — desugars to hash construction
CreateWindow(x: 100, y: 200, width: 400, height: 300, visible: .T.)
// Equivalent to: CreateWindow({ "X" => 100, "Y" => 200, ... })
```

**Not planned**: Function overloading (multiple functions with same name but
different signatures). Harbour's dynamic dispatch model assumes one function
per name. Union types + MATCH provide equivalent capability without breaking
the symbol table.

### Open Classes (Tier 1, ExtensionMethods)
```prg
EXTEND CLASS CHARACTER
   METHOD titleCase()
   METHOD slug()
ENDCLASS

? "hello world":titleCase()    // "Hello World"
```

### Interfaces (Tier 2)
```prg
INTERFACE Serializable
   METHOD toJSON() AS CHARACTER
   METHOD fromJSON(cJSON AS CHARACTER)
ENDINTERFACE

CLASS Config IMPLEMENTS Serializable
   METHOD toJSON() ...
   METHOD fromJSON(cJSON) ...
ENDCLASS
```

### Enum Classes (Tier 2)
```prg
ENUM CLASS Color
   RED
   GREEN
   BLUE
ENDENUM

ENUM CLASS HttpStatus
   OK          := 200
   NOT_FOUND   := 404
   SERVER_ERROR := 500

   METHOD isSuccess() INLINE ::ordinal() >= 200 .AND. ::ordinal() < 300
ENDENUM

? Color.RED:toString()          // "RED"
? Color.RED:ordinal()           // 0
? HttpStatus.OK:isSuccess()     // .T.
? HttpStatus.NOT_FOUND:value()  // 404

// Type-safe: compiler warns if wrong enum type passed
SetStatus( HttpStatus.OK )      // OK
SetStatus( Color.RED )          // Compile-time warning
```

Enums are a closed set of named, typed singleton values. Each value is an
instance of the enum class. Enums can have methods, custom values, and
implement interfaces. Requires compiler support (ENUM CLASS syntax) and
GradualTyping for type enforcement.

### Inline Caching (Tier 3)
```prg
// Behind the scenes: first call is slow (hash lookup),
// subsequent calls at same call site hit monomorphic cache
FOR i := 1 TO 1000000
   result := myObj:calculate(i)    // ~10x faster with inline cache
NEXT
```

---

## 5. Design Principles

These rules guide ALL OO-related work across all blueprints:

### P1. Backward Compatibility Is Non-Negotiable
Existing Harbour code must compile and run identically. New features are
additive. The only acceptable "breaking" change: methods that previously
errored (EG_NOMETHOD) may now succeed.

### P2. C Foundation, PRG Extension
Core protocols (toString, className) are implemented in C for always-available
guarantee. Rich methods (Upper, Split, Map) are implemented in PRG for
extensibility. C provides the floor; PRG raises the ceiling.

### P3. No Linking Constraints for Core Features
`toString()` must work without ENABLE TYPE CLASS ALL, without REQUEST, without
any user setup. If it requires linking, it's not a language feature — it's a
library feature.

### P4. Performance Is a Requirement
No measurable regression on existing hot paths (integer arithmetic, string
concatenation, array access). New features must not add overhead to code
that doesn't use them (zero-cost abstraction where possible).

### P5. Message-Based Dispatch Is the Core Paradigm
Everything is a message send. Operator overloading is message sends. Property
access is message sends. This is the right abstraction — don't fight it,
optimize it (InlineCaching).

### P6. Consistency Between Functions and Methods
`Upper("hello")` and `"hello":Upper()` must return the same result. Methods
wrap functions, not replace them. Both calling conventions remain valid.

### P7. Every Value Is an Object (Drydock Vision)
After DrydockObject lands, there is no "scalar vs object" distinction from
the user's perspective. Internally, HB_ITEM remains unchanged (no ABI break).
Externally, every value responds to messages.

---

## 6. Workstream Mapping

| Gap / Feature | Blueprint | Tier | Status |
|---------------|-----------|------|--------|
| Root class (DrydockObject) | [DrydockObject](../blueprints/DrydockObject(SUBSYSTEM)/BRIEF.md) | 1 | FOCUSED |
| toString / className / isScalar | [DrydockObject](../blueprints/DrydockObject(SUBSYSTEM)/BRIEF.md) | 1 | FOCUSED |
| Always-available scalar classes | [DrydockObject](../blueprints/DrydockObject(SUBSYSTEM)/BRIEF.md) | 1 | FOCUSED |
| compareTo / isComparable | [DrydockObject](../../blueprints/DrydockObject(SUBSYSTEM)/BRIEF.md) | 1 | FOCUSED |
| equals / hashCode / clone | DrydockObject Phase 2 | 1 | Planned |
| isProperty / isReadOnly reflection | DrydockObject Phase 2 | 1 | Planned |
| dispose / WITH...END WITH | DrydockObject Phase 2 | 1 | Planned |
| User-facing scalar methods | [ScalarClasses](../blueprints/ScalarClasses(SUBSYSTEM)/BRIEF.md) | 1 | Phase 1a done |
| Operator routing via scalar classes | [ScalarClasses](../blueprints/ScalarClasses(SUBSYSTEM)/BRIEF.md) | 1 | Phase 2 planned |
| PROPERTY VALIDATE blocks | Standalone or hbclass.ch | 1 | Planned |
| Computed properties (GET/SET) | Standalone or hbclass.ch | 1 | Planned |
| EXTEND CLASS syntax | ExtensionMethods | 1 | Planned |
| Runtime type introspection | Reflection | 1 | Planned |
| Abstract classes / interfaces | [GradualTyping](../blueprints/GradualTyping(FEATURE)/BRIEF.md) | 2 | Planned |
| Type declaration enforcement | [GradualTyping](../blueprints/GradualTyping(FEATURE)/BRIEF.md) | 2 | Planned |
| Compile-time scope checking | [GradualTyping](../blueprints/GradualTyping(FEATURE)/BRIEF.md) | 2 | Planned |
| Strict parentheses warnings | [GradualTyping](../blueprints/GradualTyping(FEATURE)/BRIEF.md) | 2 | Planned |
| Default parameter values | PersistentAST + GradualTyping | 2 | Planned |
| Parameter type warnings | [GradualTyping](../blueprints/GradualTyping(FEATURE)/BRIEF.md) | 2 | Planned |
| Parameter count warnings | [GradualTyping](../blueprints/GradualTyping(FEATURE)/BRIEF.md) | 2 | Planned |
| Union types (`AS N \| C \| D`) | [GradualTyping](../blueprints/GradualTyping(FEATURE)/BRIEF.md) | 2 | Planned |
| Named parameters (`x: 100`) | PersistentAST (compiler sugar) | 2 | Planned |
| MATCH / pattern matching | PersistentAST (compiler feature) | 2 | Planned |
| Parameter name preservation | [PersistentAST](../blueprints/PersistentAST(SUBSYSTEM)/BRIEF.md) | 2 | Planned |
| Enum classes (ENUM CLASS syntax) | GradualTyping or standalone | 2 | Planned |
| Function overloading | **Not planned** | — | — |
| CLASS METHOD implementation | Future | 2 | Planned |
| Metaclass protocol | Future | 3 | Planned |
| Inline caching | [InlineCaching](../blueprints/InlineCaching(FEATURE)/BRIEF.md) | 3 | Planned |
| Operator dispatch optimization | RefactorHvm + ScalarClasses Phase 3 | 1 | Planned |
| Module encapsulation | [ModuleSystem](../blueprints/ModuleSystem(FEATURE)/BRIEF.md) | 2 | Planned |
| Namespace-qualified classes | [ModuleSystem](../blueprints/ModuleSystem(FEATURE)/BRIEF.md) | 2 | Planned |
| FRIEND across modules | ModuleSystem + GradualTyping | 2 | Planned |
| Extension method scope in modules | ModuleSystem + ExtensionMethods | 2 | Planned |

---

## 7. References

- [Drydock Vision](vision.md) — overall project goals and compatibility covenant
- [Technical Analysis](analysis.md) — codebase deep dive
- [DrydockObject Blueprint](../../blueprints/DrydockObject(SUBSYSTEM)/BRIEF.md) — root class implementation
- [ScalarClasses Blueprint](../../blueprints/ScalarClasses(SUBSYSTEM)/BRIEF.md) — scalar method dispatch
- [Harbour OO Source](../../src/vm/classes.c) — the C implementation
- [HBClass Source](../../src/rtl/tclass.prg) — the metaclass
- [HBObject Source](../../src/rtl/tobject.prg) — the current base class
- [Class Header Macros](../../include/hbclass.ch) — the PRG syntax layer
- [OO Constants](../../include/hboo.ch) — message types and scope flags
