#!/bin/zsh
# Lists the collation engine functions that get a STACK PROTECTOR from the current compiler (technique log §51 (av)).
# A stack protector stores a guard value at a function's entry and checks it before the return (~10 instructions
# per call). Swift 6.5 gave one to RootCollator.compare, because the optimizer traced the fast path's indexing back
# to the stack copy of a small string; RootCollator.untraced(_:) hides that origin. Run this after a compiler or
# Xcode update: the expected output is "none".
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
FUNCS=$(grep "^sil \[stack_protection\]" "$OUT" | sed 's/.*@\(\$s[A-Za-z0-9_]*\).*/\1/' | xcrun swift-demangle --simplified | sed 's/(.*//' | sort -u)
echo "compiler: $("$SWIFT" --version 2>&1 | head -1)"
if [[ -z "$FUNCS" ]]; then echo "engine functions with a stack protector: none"; else echo "engine functions with a stack protector:"; echo "$FUNCS" | sed 's/^/  /'; fi
