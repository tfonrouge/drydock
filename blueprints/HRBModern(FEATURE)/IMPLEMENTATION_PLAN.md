# IMPLEMENTATION_PLAN -- HRBModern (FEATURE)

## Phase H.1: Fix .hrb Format (v3) -- DONE (2026-03-26, `0ea025e`)

v3 writer (genhrb.c) and reader (runner.c) implemented. Full scope preservation
verified. 6/8 tests PASS, 2 deferred to H.5.

---

## Phase H.2: .hrb Bundling -- DEFERRED

Per-file embedding (H.3) is sufficient for current needs. Bundle format
designed in BRIEF.md but not implemented. Can be added when multi-module
loading becomes a bottleneck.

---

## Phase H.3: .hrb Embedding -- DONE (2026-03-29, `f87a281`)

- **Milestone**: `hrbembed` tool generates C source with `.hrb` byte arrays.

### Steps (all complete)

- [x] **H.3.1** Create `utils/hrbembed/hrbembed.c` — reads `.hrb` files, writes
  C source with `static const HB_BYTE[]` arrays + `dd_hrbLoadEmbedded()`.
- [x] **H.3.2** Test: compile `.prg → .hrb → .c embedding`, verify output.

---

## Phase H.4: CLI Enhancements -- DONE (2026-03-29, `4e631e3`)

- **Milestone**: `drydock -dp` pcode disassembler. 181 opcodes decoded.

### Steps (all complete)

- [x] **H.4.1** Create `src/compiler/gendis.c` — 181-entry opcode name table +
  operand decoder (symbol names, jump targets, frame info, strings, numbers).
- [x] **H.4.2** Add `fPCodeDis` flag to compiler params (`hbcompdf.h`).
- [x] **H.4.3** Parse `-dp` flag in `cmdcheck.c`.
- [x] **H.4.4** Call `hb_compGenDis()` after code generation in `hbmain.c`.
- [x] **H.4.5** Add `gendis.c` to `Makefile` and `build.zig`.
- [x] **H.4.6** Verify: disassembly output correct, ddtest 4861/4861.

### Planned (not yet implemented)

- [ ] **H.4.7** `-gejson` — JSON-formatted error/warning output for LSP/IDE.
- [ ] **H.4.8** `--hrb-bundle` CLI flag (depends on H.2).
- [ ] **H.4.9** `--hrb-embed` CLI flag (alternative to standalone `hrbembed` tool).

---

## Phase H.5: Auto INIT/EXIT in .hrb -- DONE (2026-03-29, `f87a281`)

- **Milestone**: INIT procedures auto-execute on `.hrb` load. Matches C path.

### Steps (all complete)

- [x] **H.5.1** Call `hb_hrbInit()` after `hb_hrbInitStatic()` in `runner.c`
  — auto-executes INIT procedures on load.
- [x] **H.5.2** Test: INIT PROCEDURE runs, extension methods from INIT work.
- [x] **H.5.3** Verify: ddtest 4861/4861.

---

[<- Index](../INDEX.md) · [Map](../MAP.md) · [BRIEF](BRIEF.md) · [DESIGN](DESIGN.md) · **PLAN** · [TESTS](TEST_PLAN.md) · [AUDIT](AUDIT.md)
