# DESIGN -- RegisterPcode (SUBSYSTEM)

## 1. Current State

Stack-based pcode: 181 opcodes. Each instruction operates on a stack.
HB_P_PUSHLOCAL pushes a local to stack, HB_P_PLUS pops two and pushes result.
Typical expression `a + b * c` compiles to: PUSHLOCAL a, PUSHLOCAL b, PUSHLOCAL c, MULT, PLUS — 5 instructions.

## 2. Proposed Register-Based Instruction Set

### 2.1 Instruction Encoding

3-address format: `[opcode 8-bit] [dst 8-bit] [src1 8-bit] [src2 8-bit]`
- 256 virtual registers (r0-r255)
- Fixed 4-byte instruction width (vs variable-length stack pcode)
- Same expression `a + b * c`: `MULT r2, r1, r0; PLUS r3, r2, r0` — 2 instructions

### 2.2 Calling Convention

- Arguments: r0-r15 (first 16 registers)
- Return value: r0
- Locals: r16+ (allocated by register allocator)
- Callee-saved: none (all registers are virtual, spilling handled by allocator)

### 2.3 Register Allocation Strategy

Linear scan (not graph coloring):
- Simpler to implement (~500 LOC vs ~2000 LOC)
- Good enough for interpreted VM (no physical register pressure)
- Fast compilation (O(n) vs O(n^2))
- If LLVM is the native backend, LLVM does its own register allocation

### 2.4 Variable-Length Instructions

Some instructions need more than 8-bit operands:
- LOADK r0, #constant_index (16-bit index into constant pool)
- JUMP offset (24-bit signed offset)
- CALL r0, symbol_index, arg_count

Encoding: 4-byte base + optional 4-byte extension word.

## 3. Backward Compatibility

- Old .hrb files (stack pcode) still load and run — stack interpreter stays
- New .hrb files have register pcode — pcode version bump
- `HB_PCODE_VER` incremented to distinguish formats
- DD_METHOD_* macros change to register-based parameter access

## 4. Files Modified

- src/compiler/genreg.c — NEW: register pcode code generator from AST
- src/compiler/regalloc.c — NEW: linear scan register allocator
- src/vm/hvmreg.c — NEW: register-based VM dispatch loop
- include/hbpcode.h — New register opcode enum (separate from stack opcodes)

## 5. Compatibility

Stack interpreter retained. Old .hrb files work. New pcode version for register format.

## 6. Interaction with LLVMBackend

LLVMBackend walks the PersistentAST directly — it does NOT consume RegisterPcode IR.
RegisterPcode is an interpreter optimization (faster bytecode execution).
LLVMBackend is a compiler optimization (native code generation from AST).

They are independent paths:
- Interpreted execution: AST → RegisterPcode → register VM
- Compiled execution: AST → LLVM IR → native code

The RegisterPcode calling convention (r0-r15) applies ONLY to the register
interpreter. LLVM-compiled functions use cdecl. Cross-calls between interpreted
and compiled functions go through the standard HB_FUNC() interface (stack-based),
which both paths support.

---

[<- Index](../INDEX.md) · [Map](../MAP.md) · [BRIEF](BRIEF.md) · **DESIGN**
