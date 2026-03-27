#!/bin/sh
# Compile .prg to .c using the drydock compiler, writing to stdout.
# Usage: prg2c.sh <compiler_exe> <include_dir> <input.prg>
# Output: generated C source on stdout
set -e
COMPILER="$1"
INCDIR="$2"
INPUT="$3"
TMPDIR=$(mktemp -d)
BASE=$(basename "$INPUT" .prg)
"$COMPILER" -gc0 -n1 -w3 -es2 -q0 "-i${INCDIR}" "-o${TMPDIR}/${BASE}" "$INPUT" >&2
cat "${TMPDIR}/${BASE}.c"
rm -rf "$TMPDIR"
