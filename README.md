# Drydock

A modernization fork of the [Harbour compiler](https://github.com/harbour/core).

Harbour is a multi-platform, multi-threading, object-oriented compiler and
runtime for the xBase/Clipper language family. It compiles `.prg` source files
to pcode bytecode, generates C code, and links against the Harbour VM and
runtime libraries to produce native executables.

Drydock builds on Harbour's solid foundation with a structured modernization
plan: unify scalar types through OO dispatch, build a type-checked compilation
pipeline with a persistent AST, unlock hardware-level performance, and replace
the build system with a single `build.zig`.

**Upstream**: [harbour/core](https://github.com/harbour/core)

## Quick Start (Linux)

```bash
# Build (via zig — recommended)
zig build

# Build (via make — legacy)
make

# Run tests
bin/linux/gcc/ddtest

# Compile and run a program
bin/linux/gcc/ddmake tests/hello.prg
```

On Windows use `win-make`, on OS/2 use `os2-make`, on MS-DOS use `dos-make`.

For the full platform matrix and build options, see
[doc/upstream-README.md](doc/upstream-README.md).

### Binary Names

Drydock renames the user-facing binaries from the upstream Harbour names:

| Drydock | Harbour | Purpose |
|---------|---------|---------|
| `drydock` | `harbour` | Compiler |
| `ddmake` | `hbmk2` | Build tool |
| `ddtest` | `hbtest` | Test suite |
| `ddrun` | `hbrun` | Script runner |
| `ddpp` | `hbpp` | Preprocessor |
| `ddformat` | `hbformat` | Code formatter |
| `ddi18n` | `hbi18n` | i18n tool |

Internal APIs (`hb_*`), libraries (`libhb*.a`), and file formats (`.hrb`,
`.hbp`, `.hbc`) retain the `hb` prefix for backward compatibility. The old
Harbour binary names (`harbour`, `hbmk2`, etc.) remain available as legacy
symlinks.

## Project Documents

| Document | Purpose |
|----------|---------|
| [doc/drydock.md](doc/drydock.md) | Vision, workstreams, compatibility covenant |
| [doc/drydock-analysis.md](doc/drydock-analysis.md) | Technical deep dive and code analysis |
| [blueprints/INDEX.md](blueprints/INDEX.md) | Workstream status board |
| [blueprints/MAP.md](blueprints/MAP.md) | Dependency graph and sprint focus |
| [CLAUDE.md](CLAUDE.md) | Guidance for Claude Code when working in this repo |

## Roadmap Overview

```
Tier 0  Build         ZigBuild (replace GNU Make + hbmk2 with build.zig)
Tier 1  Foundation    RefactorHvm -> ScalarClasses -> ExtensionMethods -> Traits
                      ComputedGoto, GenerationalGC (independent)
Tier 2  Compiler      PersistentAST -> GradualTyping, Optimizer, ModuleSystem, LSP
Tier 3  Performance   RemoveGIL, RegisterPcode, InlineCaching, LLVMBackend
```

See [blueprints/MAP.md](blueprints/MAP.md) for the full dependency graph and
current sprint focus.

## Compatibility Target

99.5% source compatibility with existing Clipper/Harbour code. All breaks
documented, non-silent, and discoverable at compile time. See
[doc/drydock.md](doc/drydock.md) for the compatibility covenant.

## Code Formatting

```bash
# C/H files
uncrustify -c bin/harbour.ucf <file.c>

# Harbour .prg/.hb/.ch files
bin/linux/gcc/ddformat <file.prg>
```

## License

Harbour is licensed under the GNU General Public License with a special
exception for executables. See [LICENSE.txt](LICENSE.txt) for details.

## Acknowledgments

Harbour is the result of over two decades of work by a dedicated open-source
community. Drydock is a downstream fork that builds on their foundation.

**Core contributors** (alphabetical, by volume of commits and scope of impact):

- Antonio Linares — original creator, compiler and VM architect
- Przemyslaw Czerpak (druzus) — VM, class system, RDD, macro compiler, core runtime
- Viktor Szakats — build system, portability, CI, documentation, long-term maintainer

**Major contributors:**

- Alexander Kresin — contrib modules, GT drivers
- Brian Hays — runtime library
- Chen Kedem — runtime, portability
- David G. Holm — runtime library, Clipper compatibility
- Eddie Runia — VM, class system
- Francesco Saverio Giudice — contrib modules
- Jose Lalin — runtime library
- Luiz Rafael Culik — GT drivers, contrib modules
- Maurilio Longo — networking, contrib modules
- Mindaugas Kavaliauskas — runtime library
- Pritpal Bedi — IDE tools, QT bindings, contrib modules
- Ron Pinkas — compiler, class system, xHarbour divergence/reunion
- Ryszard Glab — compiler, debugger

And [many more](https://github.com/harbour/core/graphs/contributors) across
100+ individual contributors.

The original upstream build documentation is preserved at
[doc/upstream-README.md](doc/upstream-README.md).

---
Original Harbour README Copyright 2009-present Viktor Szakats
([CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/))
Drydock additions Copyright 2026-present Teo Fonrouge and contributors
