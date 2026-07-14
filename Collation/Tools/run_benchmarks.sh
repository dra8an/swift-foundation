#!/bin/zsh
# One-command benchmark runbook — builds all three harnesses and prints the
# matrix. See Docs/27-benchmark-runbook.md for the why and per-machine notes.
#
#   Collation/Tools/run_benchmarks.sh [K]      # K = repeats per metric (default 7)
#
# Machine 1 (Intel iMac) defaults below. Machine 2 (Apple Silicon): override
#   ICU_SRC=~/Projects/Unicode/icu-DraganBesevic-2 \
#   ICU_BUILD=$ICU_SRC/icu4c/source  Collation/Tools/run_benchmarks.sh
set -e

SCRIPT_DIR=${0:A:h}          # .../Collation/Tools
REPO=${SCRIPT_DIR:h:h}        # repo root (swift-foundation)
cd "$REPO"

ICU_SRC=${ICU_SRC:-$HOME/Projects/claude/icu}
ICU_BUILD=${ICU_BUILD:-$HOME/Projects/claude/collation/icu-build}
export ICU_LIB=$ICU_BUILD/lib
K=${1:-7}

echo "== build bench_icu (pure ICU reference) =="
clang Collation/Tools/bench_icu.c -O2 -o Collation/Tools/bench_icu \
  -I "$ICU_SRC/icu4c/source/common" -I "$ICU_SRC/icu4c/source/i18n" \
  -L "$ICU_BUILD/lib" -licuuc -licui18n -licudata
export ICU_BIN="$REPO/Collation/Tools/bench_icu"

# -no-WMO is REQUIRED on machine 1 (Intel/Swift 6.3.1): a release WMO executable
# SIGILLs at startup via the _localeICUClass dynamic-replacement miscompile.
# Harmless (just un-WMO'd) on machine 2. See Docs/25 / Docs/27.
echo "== build BenchFoundation (release, -no-WMO) =="
swift build -c release -Xswiftc -no-whole-module-optimization --product BenchFoundation >/dev/null
BF="$(swift build -c release -Xswiftc -no-whole-module-optimization --product BenchFoundation --show-bin-path)/BenchFoundation"

echo "== build bench_system (system-ICU reference, compiled once) =="
swiftc -O Collation/Tools/bench_system_foundation.swift -o Collation/Tools/bench_system
export SYS_BIN="$REPO/Collation/Tools/bench_system"

echo "== build EngineBench (engine-only, FULL WMO — honest Table 1) =="
export ENGINE_BIN="$(Collation/Tools/build_engine_bench.sh)"

echo "== run matrix =="
python3 Collation/Tools/bench_matrix.py "$BF" "$K"
