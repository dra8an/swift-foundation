#!/bin/zsh
# Assembles and builds the §47 discontiguous-contraction probe (see
# disc-probe/main.swift): finds the corpus lines that actually reach the
# UTS #10 S2.1.3 "remove C" branch, then checks the POSITIONS the search
# APIs report for each of them. This is the probe that found §46(b) (the
# scalar count that ignored the out-of-order consumption) and §47's second
# bug (a match ENDING at a discontiguous contraction under-reporting its
# end). PositionInvariantTests covers seven curated sequences; this covers
# whatever a corpus actually contains, at corpus scale.
#
# The engine sources are copied VERBATIM into a scratch package (repo
# untouched) and `removeAhead` gains a hit counter IN THE COPY ONLY, so the
# probe can tell which lines reach the branch — the CE and key output never
# reveals it. FULL WMO release; binary path on stdout. Exits non-zero if any
# position check fails, so it doubles as a corpus-scale gate. Same pattern
# as build_cjk_probe.sh.
#
#   Collation/Tools/build_disc_probe.sh
#   $(...)  Tests/FoundationInternationalizationTests/Collation/Conformance/CollationTest_NON_IGNORABLE_SHORT.txt --hex
#   $(...)  Collation/Tools/bench/bench-uca.txt
set -e
SCRIPT_DIR=${0:A:h}
REPO=${SCRIPT_DIR:h:h}
OUT="$REPO/.build/disc-probe"
ENGINE_SRC="$REPO/Sources/FoundationInternationalization/Collation"

mkdir -p "$OUT/Sources/DiscProbe/Resources"
cp "$ENGINE_SRC"/*.swift "$OUT/Sources/DiscProbe/"
cp "$ENGINE_SRC/Resources/ucadata.icu" "$ENGINE_SRC/Resources/ucadata-icu4x.icu" \
   "$ENGINE_SRC/Resources/nfd.bin" "$OUT/Sources/DiscProbe/Resources/"
rsync -a --delete "$ENGINE_SRC/Resources/tailorings/" "$OUT/Sources/DiscProbe/Resources/tailorings/"
cp "$SCRIPT_DIR/disc-probe/main.swift" "$OUT/Sources/DiscProbe/main.swift"

cat > "$OUT/Sources/DiscProbe/DiscProbeCounter.swift" <<'COUNTER'
/// Hit counter for the S2.1.3 "remove C" branch, incremented by the
/// instrumentation the build script splices into `removeAhead` (copy only).
enum DiscProbeCounter {
    nonisolated(unsafe) static var hits = 0
}
COUNTER

# Instrumentation — COPY ONLY, and inside removeAhead's BODY rather than at
# its call site, so it counts every path that reaches the branch. The sed is
# a no-op if the signature moved; the guard below then fails the build early
# instead of silently reporting zero hits.
sed -i '' \
  -e 's|    private mutating func removeAhead(at i: Int) {|    private mutating func removeAhead(at i: Int) {\
        DiscProbeCounter.hits += 1|' \
  "$OUT/Sources/DiscProbe/CollationElements.swift"
if ! grep -q 'DiscProbeCounter.hits += 1' "$OUT/Sources/DiscProbe/CollationElements.swift"; then
  echo "build_disc_probe.sh: removeAhead(at:) signature moved — re-check the instrumentation sed" >&2
  exit 1
fi

cat > "$OUT/Package.swift" <<'MANIFEST'
// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "discprobe",
    platforms: [.macOS("15")],
    targets: [
        .executableTarget(
            name: "DiscProbe",
            path: "Sources/DiscProbe",
            resources: [
                .copy("Resources/ucadata.icu"),
                .copy("Resources/ucadata-icu4x.icu"),
                .copy("Resources/nfd.bin"),
                .copy("Resources/tailorings"),
            ]
        ),
    ]
)
MANIFEST

cd "$OUT" && swift build -c release >&2
echo "$OUT/.build/release/DiscProbe"
