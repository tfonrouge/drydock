---
name: Drydock modernization initiative
description: Codename and scope for the Harbour compiler modernization project
type: project
---

The Harbour modernization initiative is codenamed **Drydock**. This is a fork of
the original Harbour compiler (upstream: https://github.com/harbour/core, fork:
https://github.com/tfonrouge/core).

**North star:** Modernize the Harbour compiler — make it more usable, debuggable, and pluggable while maintaining 99.5% backward compatibility (see Compatibility Covenant in doc/drydock.md).

**Key workstreams:**
1. Scalar classes — unify primitives with the OO system
2. Structured reflection API
3. Extension methods + Traits
4. Conditional breakpoints + DAP debug server
5. Gradual strong typing (opt-in)
6. Encoding-aware strings
7. VM dispatch table refactor (split hvm.c)

**Plan document:** `doc/plan_modernization.md` (to be renamed `doc/drydock.md`)

**Branch naming convention:** `drydock/<feature>` (e.g., `drydock/scalar-classes`)

**Why:** The core problem is the conceptual bifurcation between primitive types managed by hvm.c and objects managed by classes.c. Drydock unifies them.

**How to apply:** Use "Drydock" when referring to this initiative. Follow the sprint order in the plan document. All changes must be backward-compatible.
