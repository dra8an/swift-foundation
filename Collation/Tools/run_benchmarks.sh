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

source "$SCRIPT_DIR/swift_toolchain.sh"   # SWIFT, SWIFTC: the compiler that matches the selected SDK (technique log §51 (at))

if [[ "$(uname -m)" == arm64 ]]; then
  # Machine 2: two BenchFoundation builds for Table 2 — -no-WMO (the column of
  # the history) and WMO (release builds of swift-foundation compile WMO,
  # CMakeLists.txt). Both with SwiftPM's native build system, each in its own
  # scratch path: the default build system cannot build -no-WMO from an empty
  # scratch path ("unable to open dependencies file" in swift-syntax), with
  # Swift 6.4-dev and 6.5 alike; the same build system for both columns keeps
  # WMO the only difference (technique log §51 (as), (at)).
  echo "== build BenchFoundation (release, -no-WMO; $($SWIFT --version 2>&1 | head -1)) =="
  "$SWIFT" build --build-system native -c release -Xswiftc -no-whole-module-optimization --product BenchFoundation --scratch-path .build-matrix-nowmo >/dev/null
  BF="$("$SWIFT" build --build-system native -c release -Xswiftc -no-whole-module-optimization --product BenchFoundation --scratch-path .build-matrix-nowmo --show-bin-path)/BenchFoundation"
  echo "== build BenchFoundation (release, WMO) =="
  "$SWIFT" build --build-system native -c release --product BenchFoundation --scratch-path .build-matrix-wmo >/dev/null
  export WMO_BIN="$("$SWIFT" build --build-system native -c release --product BenchFoundation --scratch-path .build-matrix-wmo --show-bin-path)/BenchFoundation"
else
  # Machine 1 (Intel/Swift 6.3.1): -no-WMO is REQUIRED — a release WMO
  # executable SIGILLs at startup via the _localeICUClass dynamic-replacement
  # miscompile (Docs/25 / Docs/27). No WMO column there.
  echo "== build BenchFoundation (release, -no-WMO) =="
  "$SWIFT" build -c release -Xswiftc -no-whole-module-optimization --product BenchFoundation >/dev/null
  BF="$("$SWIFT" build -c release -Xswiftc -no-whole-module-optimization --product BenchFoundation --show-bin-path)/BenchFoundation"
  unset WMO_BIN
fi

echo "== build bench_system (system-ICU reference, compiled once) =="
"$SWIFTC" -O Collation/Tools/bench_system_foundation.swift -o Collation/Tools/bench_system
export SYS_BIN="$REPO/Collation/Tools/bench_system"

echo "== build EngineBench (engine-only, FULL WMO — honest Table 1) =="
export ENGINE_BIN="$(Collation/Tools/build_engine_bench.sh)"

echo "== run matrix =="
python3 Collation/Tools/bench_matrix.py "$BF" "$K"
