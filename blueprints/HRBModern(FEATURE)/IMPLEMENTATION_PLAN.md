# IMPLEMENTATION_PLAN -- HRBModern (FEATURE)

## Phase H.1: Fix .hrb Format (v3) -- DONE (2026-03-26, `0ea025e`)

v3 writer (genhrb.c) and reader (runner.c) implemented. Full scope preservation
verified. 6/8 tests PASS, 2 deferred to H.5.

---

## Phase H.2: .hrb Bundling (3 days)

- **Milestone**: Multiple .hrb files combine into a single archive with TOC.
  `drydock --hrb-bundle obj/hrb/*.hrb -o lib/hbrtl.hrb` works.

### Steps

- [ ] **H.2.1** Define bundle format in genhrb.c: signature `\xC0HBL`,
  entry count, TOC (name + offset + size), concatenated .hrb v3 files.
- [ ] **H.2.2** Implement bundle writer in `src/compiler/genhrb.c`.
- [ ] **H.2.3** Implement bundle loader in `src/vm/runner.c` — single
  `hb_hrbLoad()` call registers all modules.
- [ ] **H.2.4** Add `--hrb-bundle` CLI flag to `src/compiler/cmdcheck.c`.
- [ ] **H.2.5** Test: bundle 5 .hrb files, load bundle, verify all symbols.
- [ ] **H.2.6** Verify: `ddtest` — 4861/4861 pass.

---

## Phase H.3: .hrb Embedding (3 days)

- **Milestone**: `drydock --hrb-embed lib/hbrtl.hrb -o hbrtl_hrb.c` generates
  a C file with the bundle as a static byte array + accessor function.

### Steps

- [ ] **H.3.1** Implement embed generator — reads .hrb bundle, writes C source
  with `static const HB_BYTE s_data[] = {...}` and accessor function.
- [ ] **H.3.2** Add `--hrb-embed` CLI flag.
- [ ] **H.3.3** Add VM startup hook to load embedded .hrb data via accessor.
- [ ] **H.3.4** Test: embed a bundle, link into executable, verify functions work.

---

## Phase H.4: CLI Enhancements (2 days, independent)

- **Milestone**: `drydock -dp file.prg` prints human-readable pcode disassembly.

### Steps

- [ ] **H.4.1** Implement pcode disassembler in `src/compiler/hbmain.c` — walk
  pcode bytes, print opcode names and operands.
- [ ] **H.4.2** Add `-dp` CLI flag to `src/compiler/cmdcheck.c`.
- [ ] **H.4.3** Test: disassemble hello.prg, verify output shows LINE/PUSHSYM/etc.

---

## Phase H.5: Auto INIT/EXIT in .hrb (1 day)

- **Milestone**: Loading a v3 .hrb file auto-executes INIT symbols and queues
  EXIT symbols, matching the C path behavior.

### Steps

- [ ] **H.5.1** In `runner.c` `hb_hrbLoad()`, after symbol registration,
  call `hb_hrbInitStatic()` and `hb_hrbInit()` automatically for v3 files.
- [ ] **H.5.2** Test: compile a .prg with INIT PROCEDURE to .hrb, load via
  ddrun, verify INIT runs automatically.
- [ ] **H.5.3** Re-run deferred tests TEST-H1-002 and TEST-H1-008.

---

[<- Index](../INDEX.md) · [Map](../MAP.md) · [BRIEF](BRIEF.md) · [DESIGN](DESIGN.md) · **PLAN** · [TESTS](TEST_PLAN.md) · [AUDIT](AUDIT.md)
