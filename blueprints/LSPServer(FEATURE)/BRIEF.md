# BRIEF -- LSPServer (FEATURE)

## Identity

| Field | Value |
|-------|-------|
| **Name** | LSPServer |
| **Mode** | FEATURE |
| **Tier** | 2 — Build a Real Compiler |
| **Phase** | I |
| **Component** | New — `contrib/hblsp/` or `utils/hblsp/` |
| **Status** | PLANNING |

---

## 1. Motivation

Harbour has no IDE integration beyond basic syntax highlighting. There is no
LSP (Language Server Protocol) server, which means:

- No go-to-definition
- No hover type information
- No real-time diagnostics
- No autocomplete for functions, methods, or variables
- No find-all-references or rename support

This makes Harbour effectively unusable in modern development workflows. Developers
in 2026 expect IDE-quality tooling. Without it, no new developers adopt the language.

---

## 2. Proposed Architecture

```
Editor (VS Code / JetBrains / Neovim)
    ↕ JSON-RPC (stdio or socket)
hblsp server
    ↕ Harbour compiler library API
Persistent AST + type info + symbol tables
```

### Capabilities (phased)

| Phase | LSP Features |
|-------|-------------|
| I.1 | `textDocument/diagnostic` — real-time compile errors and warnings |
| I.1 | `textDocument/definition` — go-to-definition for functions and variables |
| I.2 | `textDocument/hover` — type info, function signatures, documentation |
| I.2 | `textDocument/completion` — autocomplete for functions, methods, keywords |
| I.3 | `textDocument/references` — find all references |
| I.3 | `textDocument/rename` — rename symbol across files |

### Implementation

- Built on the persistent AST from Phase E and type info from Phase F
- Incremental reparsing: re-parse only changed functions, not entire files
- Background thread for analysis while editing
- Written in C for the core (compiler integration), with a thin JSON-RPC
  transport layer

---

## 3. Dependencies

| Dependency | Status | Notes |
|------------|--------|-------|
| PersistentAST (Phase E) | PLANNING | **Required** — AST needed for all IDE features |
| GradualTyping (Phase F) | PLANNING | **Required for hover/completion** — type info feeds hover and autocomplete |

## 4. Estimated Scope

**8 weeks** — 3 phases, each adding more LSP capabilities.

---

[<- Index](../INDEX.md) · [Map](../MAP.md) · **BRIEF**
