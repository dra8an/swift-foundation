#!/bin/zsh
# Lists the collation engine functions that get a STACK PROTECTOR from the current compiler (technique log §51 (av)).
# A stack protector stores a guard value at a function's entry and checks it before the return (~10 instructions
# per call). Swift 6.5 gave one to RootCollator.compare, because the optimizer traced the fast path's indexing back
# to the stack copy of a small string; RootCollator.untraced(_:) hides that origin. Run this after a compiler or
# Xcode update. Expected in both lists (since §51 (ay)): only RootCollator.Storage.init (collator creation) and
# CollationKeys.writeSinglePass (it WRITES into its own stack buffer: there the guard is a real one; kept on purpose);
# since §51 (bd) also the three file parsers CollationData.init(contentsOf:), CollationData.bundledTailoring(named:)
# and NormalizationData.init(contentsOf:) (creation only: Data.withUnsafeBytes passes a stack copy for a small Data).
# Any other engine function in a list is new work for every call. Two checks: the SIL marks (every linkage — the first
# version matched only public functions and missed compareSlowPath and writeSinglePass, technique log §51 (ay)), and
# the machine code of the built EngineBench (functions that load ___stack_chk_guard; the SIL alone missed one).
# Usage (from anywhere): /Users/dragan/Projects/dra8an/swift-foundation-collation/Collation/Tools/check_stack_protection.sh
set -e
SCRIPT_DIR=${0:A:h}
REPO=${SCRIPT_DIR:h:h}
source "$SCRIPT_DIR/swift_toolchain.sh"
E="$REPO/.build/engine-bench"
"$SCRIPT_DIR/build_engine_bench.sh" > /dev/null          # copies the engine sources and builds (Bundle.module accessor)
A=$(find "$E/.build" -name resource_bundle_accessor.swift -path "*CollEngine*" | head -1)
OUT="$E/stack-protection.sil"
cd "$E"
"$SWIFTC" -O -wmo -emit-sil -parse-as-library -module-name CollEngine Sources/CollEngine/*.swift "$A" -o "$OUT"
FUNCS=$(grep -E "^sil [a-z_ ]*\[stack_protection\]" "$OUT" | sed 's/.*@\(\$s[A-Za-z0-9_]*\).*/\1/' | xcrun swift-demangle --simplified | sed 's/(.*//' | sort -u)
echo "compiler: $("$SWIFT" --version 2>&1 | head -1)"
if [[ -z "$FUNCS" ]]; then echo "engine functions with a stack protector (SIL): none"; else echo "engine functions with a stack protector (SIL):"; echo "$FUNCS" | sed 's/^/  /'; fi
BIN=$("$SWIFT" build -c release --package-path "$E" --show-bin-path)/EngineBench
python3 -I "$SCRIPT_DIR/stack_guard_funcs.py" "$BIN" | grep -v -E "^  (_main|static String._copying)" | sed "s/^\([0-9]*\) functions with a stack protector:/engine binary (the bench program's _main and String._copying not listed), \1 functions with a stack protector:/"
