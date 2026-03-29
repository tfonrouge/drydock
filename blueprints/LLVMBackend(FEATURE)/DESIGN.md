# DESIGN -- LLVMBackend (FEATURE)

## 1. Current State

C code generation (gencc.c) emits hb_xvm* function calls. These are pre-dispatched interpreter calls — not native code. The C compiler optimizes call sequences but the actual work is still VM functions.

## 2. Proposed LLVM Backend

### 2.1 Target LLVM Version

LLVM 18+ (current stable). Use the C API (not C++) for easier integration with Harbour's C codebase. Link against libLLVM.

### 2.2 IR Emission

New code generator `src/compiler/genllvm.c`:
- Walks PersistentAST (requires Phase E)
- Emits LLVM IR for each function
- Type mapping: HB_ITEM → LLVM struct type with known layout
- Each HB_ITEM field (type tag, value union) maps to LLVM struct members
- Arithmetic on known types compiles to native instructions (no VM call)
- Dynamic dispatch compiles to inline cache check + direct call (speculative)

### 2.3 Calling Convention

- LLVM-compiled functions use the C calling convention (cdecl)
- Arguments passed as HB_ITEM* pointers (same as current HB_FUNC)
- Return value via hb_stackReturnItem() (unchanged)
- LLVM functions can call hb_vm* runtime functions directly
- Runtime functions exported as LLVM external declarations

### 2.4 Exception Handling

- Harbour SEQUENCE/RECOVER maps to setjmp/longjmp (not LLVM invoke/landingpad)
- Reason: Harbour exceptions are not C++ exceptions. They use the existing hb_vmRequestBreak() / hb_xvmSeqBegin() mechanism.
- LLVM code calls hb_xvmSeqBegin() which does setjmp. On BREAK, longjmp unwinds.
- This is the same mechanism as the current C codegen path.

### 2.5 GC Stack Maps

- LLVM's statepoint mechanism marks GC roots in compiled frames
- Each GC safepoint (allocation, function call) gets a statepoint
- The GC reads stack maps to find live HB_ITEM references
- DrydockAPI handles (dd_handle) used instead of raw pointers — handles survive object relocation

### 2.6 Macro Exclusion

- Functions containing `&` (macro evaluation) stay in the interpreter
- LLVM cannot compile runtime-generated code (same as V8's approach to eval())
- Macro-free functions compile to native. Macro-containing functions interpreted.

## 3. Phases

- M.1 (6 weeks): IR emission for basic functions (arithmetic, locals, function calls)
- M.2 (4 weeks): Runtime integration (calling convention, GC stack maps)
- M.3 (4 weeks): Optimization pipeline (LLVM passes: SROA, GVN, LICM)
- M.4 (2 weeks): JIT support via ORC (compile on first call)

## 4. Files Modified

- src/compiler/genllvm.c — NEW: LLVM IR code generator
- src/vm/hvmllvm.c — NEW: LLVM JIT runtime (ORC integration)
- include/hbllvm.h — NEW: LLVM backend public API
- build.zig — Link against libLLVM

## 5. Compatibility

Additive — LLVM is an optional backend. Existing C and .hrb backends unchanged. LLVM backend activated via flag (-gllvm or similar).

## 6. Input Source

LLVMBackend walks PersistentAST (Phase E) directly. It does NOT consume
RegisterPcode IR. The INDEX.md dependency on RegisterPcode is "recommended"
(RegisterPcode's register allocation insights inform LLVM IR generation)
but NOT required.

The code path is: .prg → Parser → AST → genllvm.c → LLVM IR → native code.
RegisterPcode (genreg.c) is a parallel path for interpreted execution.

---

[<- Index](../INDEX.md) · [Map](../MAP.md) · [BRIEF](BRIEF.md) · **DESIGN**
