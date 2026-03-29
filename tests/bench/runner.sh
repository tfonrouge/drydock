#!/bin/bash
#
# Drydock Benchmark Runner
#
# Usage:
#   tests/bench/runner.sh              Run benchmarks, compare to baseline
#   tests/bench/runner.sh --save       Run and save results as new baseline
#   tests/bench/runner.sh --baseline   Show current baseline
#   tests/bench/runner.sh --help       Show this help
#
# Each .prg benchmark outputs lines in format:
#   name  elapsed_ms  "ms"  description
#
# The runner parses these, compares to baseline.txt, and reports diffs.

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DDMAKE="$REPO_ROOT/bin/linux/gcc/ddmake"
BASELINE="$SCRIPT_DIR/baseline.txt"
BENCHMARKS="loop_int string_ops array_heavy oo_dispatch gc_pressure"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

usage() {
    sed -n '3,12p' "$0" | sed 's/^# \?//'
    exit 0
}

# Parse args
SAVE=0
SHOW_BASELINE=0
for arg in "$@"; do
    case "$arg" in
        --save)     SAVE=1 ;;
        --baseline) SHOW_BASELINE=1 ;;
        --help|-h)  usage ;;
        *)          echo "Unknown option: $arg"; usage ;;
    esac
done

if [ "$SHOW_BASELINE" -eq 1 ]; then
    if [ -f "$BASELINE" ]; then
        cat "$BASELINE"
    else
        echo "No baseline file found at $BASELINE"
    fi
    exit 0
fi

# Load baseline into associative array
declare -A BASELINE_MAP
if [ -f "$BASELINE" ]; then
    while IFS=$'\t' read -r name ms desc; do
        [ -z "$name" ] && continue
        [[ "$name" == \#* ]] && continue
        BASELINE_MAP["$name"]="$ms"
    done < "$BASELINE"
fi

# Compile all benchmarks
echo -e "${BOLD}Compiling benchmarks...${NC}"
for bench in $BENCHMARKS; do
    "$DDMAKE" "$SCRIPT_DIR/${bench}.prg" -gtcgi -q 2>/dev/null
done
echo ""

# Print header
VERSION=$("$REPO_ROOT/bin/linux/gcc/drydock" --version 2>&1 | head -1)
COMMIT=$(cd "$REPO_ROOT" && git rev-parse --short HEAD 2>/dev/null || echo "unknown")

echo -e "${BOLD}══════════════════════════════════════════════════════════════${NC}"
echo -e "${BOLD} Drydock Benchmark Suite${NC}"
echo -e " $VERSION"
echo -e " Commit: $COMMIT  $(date '+%Y-%m-%d %H:%M')"
echo -e "${BOLD}══════════════════════════════════════════════════════════════${NC}"
echo ""

if [ ${#BASELINE_MAP[@]} -gt 0 ]; then
    printf "${BOLD}%-24s %8s %8s %8s  %s${NC}\n" "Test" "Time" "Base" "Diff" "Description"
else
    printf "${BOLD}%-24s %8s  %s${NC}\n" "Test" "Time" "Description"
fi
printf "%-70s\n" "----------------------------------------------------------------------"

# Run benchmarks and collect results
declare -A RESULTS
TOTAL=0
TOTAL_BASE=0
REGRESSIONS=0
IMPROVEMENTS=0

for bench in $BENCHMARKS; do
    # Run and parse output — extract lines matching: name  number  ms  description
    while IFS= read -r line || [ -n "$line" ]; do
        # Strip ANSI escape codes and terminal control
        clean=$(echo "$line" | sed 's/\x1b\[[0-9;]*[a-zA-Z]//g' | tr -s ' ' | sed 's/^ //')
        # Skip empty lines
        [ -z "$clean" ] && continue

        # Parse: name  elapsed  ms  description...
        name=$(echo "$clean" | awk '{print $1}')
        ms=$(echo "$clean" | awk '{print $2}')
        desc=$(echo "$clean" | awk '{$1=$2=$3=""; print $0}' | sed 's/^ *//')

        # Validate: name must be lowercase/underscore, ms must be a number
        [[ "$name" =~ ^[a-z_]+$ ]] || continue
        [[ "$ms" =~ ^[0-9]+$ ]] || continue

        RESULTS["$name"]="$ms"
        TOTAL=$((TOTAL + ms))

        if [ ${#BASELINE_MAP[@]} -gt 0 ]; then
            base="${BASELINE_MAP[$name]:-}"
            if [ -n "$base" ]; then
                TOTAL_BASE=$((TOTAL_BASE + base))
                diff=$((ms - base))
                if [ "$base" -gt 0 ]; then
                    pct=$(awk "BEGIN { printf \"%.1f\", ($diff / $base) * 100 }")
                else
                    pct="n/a"
                fi

                if [ "$diff" -gt 0 ]; then
                    # Slower — regression
                    threshold=$(awk "BEGIN { printf \"%d\", $base * 0.05 }")
                    if [ "$diff" -gt "$threshold" ]; then
                        color="$RED"
                        REGRESSIONS=$((REGRESSIONS + 1))
                        sign="+"
                    else
                        color="$YELLOW"
                        sign="+"
                    fi
                elif [ "$diff" -lt 0 ]; then
                    # Faster — improvement
                    threshold=$(awk "BEGIN { printf \"%d\", $base * 0.05 }")
                    absdiff=$((-diff))
                    if [ "$absdiff" -gt "$threshold" ]; then
                        color="$GREEN"
                        IMPROVEMENTS=$((IMPROVEMENTS + 1))
                    else
                        color="$NC"
                    fi
                    sign=""
                else
                    color="$NC"
                    sign=""
                fi

                printf "%-24s %6d ms %6d ms ${color}%+6d ms (%s%s%%)${NC}  %s\n" \
                    "$name" "$ms" "$base" "$diff" "$sign" "$pct" "$desc"
            else
                printf "%-24s %6d ms %8s %8s  %s ${CYAN}(new)${NC}\n" \
                    "$name" "$ms" "--" "--" "$desc"
            fi
        else
            printf "%-24s %6d ms  %s\n" "$name" "$ms" "$desc"
        fi

    done < <(./"$bench" 2>&1)
done

# Summary
echo ""
printf "%-70s\n" "----------------------------------------------------------------------"

if [ ${#BASELINE_MAP[@]} -gt 0 ] && [ "$TOTAL_BASE" -gt 0 ]; then
    total_diff=$((TOTAL - TOTAL_BASE))
    total_pct=$(awk "BEGIN { printf \"%.1f\", ($total_diff / $TOTAL_BASE) * 100 }")

    if [ "$total_diff" -gt 0 ]; then
        color="$RED"
    elif [ "$total_diff" -lt 0 ]; then
        color="$GREEN"
    else
        color="$NC"
    fi

    printf "${BOLD}%-24s %6d ms %6d ms ${color}%+6d ms (%s%%)${NC}\n" \
        "TOTAL" "$TOTAL" "$TOTAL_BASE" "$total_diff" "$total_pct"

    echo ""
    if [ "$REGRESSIONS" -gt 0 ]; then
        echo -e "${RED}${BOLD}$REGRESSIONS regression(s) detected (>5% slower)${NC}"
    fi
    if [ "$IMPROVEMENTS" -gt 0 ]; then
        echo -e "${GREEN}${BOLD}$IMPROVEMENTS improvement(s) detected (>5% faster)${NC}"
    fi
    if [ "$REGRESSIONS" -eq 0 ] && [ "$IMPROVEMENTS" -eq 0 ]; then
        echo -e "${GREEN}No significant changes vs baseline${NC}"
    fi
else
    printf "${BOLD}%-24s %6d ms${NC}\n" "TOTAL" "$TOTAL"
    echo ""
    echo -e "${YELLOW}No baseline found. Run with --save to create one.${NC}"
fi

# Save if requested
if [ "$SAVE" -eq 1 ]; then
    echo ""
    {
        echo "# Drydock benchmark baseline"
        echo "# $VERSION"
        echo "# Commit: $COMMIT  $(date '+%Y-%m-%d %H:%M')"
        echo "#"
        echo "# name	ms	description"
        for name in $(echo "${!RESULTS[@]}" | tr ' ' '\n' | sort); do
            echo -e "${name}\t${RESULTS[$name]}\t"
        done
    } > "$BASELINE"
    echo -e "${GREEN}Baseline saved to $BASELINE${NC}"
fi

# Cleanup compiled binaries
for bench in $BENCHMARKS; do
    rm -f "./$bench"
done

echo ""
