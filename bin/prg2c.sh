#!/bin/sh
# Wrapper: compile .prg to .c using harbour, writing output to a specific directory.
# Usage: prg2c.sh <harbour_exe> <include_dir> <output_dir> <input.prg>
# Produces: <output_dir>/<basename>.c
HARBOUR="$1"
INCDIR="$2"
OUTDIR="$3"
INPUT="$4"
BASE=$(basename "$INPUT" .prg)
"$HARBOUR" -gc0 -n1 -w3 -es2 -q0 "-i${INCDIR}" "-o${OUTDIR}/${BASE}" "$INPUT"
