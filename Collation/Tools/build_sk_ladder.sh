#!/bin/zsh
# Assembles and builds the §43 sortKey entry ladder (see sk-ladder/
# main.swift): §29-style stage-by-stage attribution for sortKey(for:into:)
# — S0 public entry, S1 no-TLS, S2 no-throws, S3 pipeline-only, S4
# writer-only (holdS4 arg = hold-loop for sampling), S5 reset-only. Stage
# clones are verified byte-identical to the public entry over the corpus.
# The engine sources are copied VERBATIM into a scratch package (repo
# untouched); visibility of a few private members is loosened IN THE COPY
# ONLY. FULL WMO release; binary path on stdout. Same pattern as
# build_cjk_probe.sh.
#
#   Collation/Tools/build_sk_ladder.sh
#   $(...)  Collation/Tools/bench/bench-ascii.txt 300
#   $(...)  Collation/Tools/bench/bench-ascii.txt 1 holdS4   # then: sample PID 10
set -e
SCRIPT_DIR=${0:A:h}
REPO=${SCRIPT_DIR:h:h}
OUT="$REPO/.build/sk-ladder"
ENGINE_SRC="$REPO/Sources/FoundationInternationalization/Collation"

mkdir -p "$OUT/Sources/SKLadder/Resources"
cp "$ENGINE_SRC"/*.swift "$OUT/Sources/SKLadder/"
cp "$ENGINE_SRC/Resources/ucadata.icu" "$ENGINE_SRC/Resources/ucadata-icu4x.icu" \
   "$ENGINE_SRC/Resources/nfd.bin" "$OUT/Sources/SKLadder/Resources/"
rsync -a --delete "$ENGINE_SRC/Resources/tailorings/" "$OUT/Sources/SKLadder/Resources/tailorings/"
cp "$SCRIPT_DIR/sk-ladder/main.swift" "$OUT/Sources/SKLadder/main.swift"
# The two reference writers (buffered, direct) do not ship; they live with the tool.
cp "$SCRIPT_DIR/sk-ladder/ReferenceWriters.swift" "$OUT/Sources/SKLadder/ReferenceWriters.swift"

# Visibility loosening — COPY ONLY. Each sed is a no-op if the pattern moved;
# if the probe then fails to compile, re-check the member's name/visibility.
sed -i '' \
  -e 's/private func takeScratch/func takeScratch/' \
  -e 's/private func giveScratch/func giveScratch/' \
  -e 's/private func variableTopValue/func variableTopValue/' \
  -e 's/private var simpleCEs/var simpleCEs/' \
  -e 's/private var thaiCEs/var thaiCEs/' \
  "$OUT/Sources/SKLadder/RootCollator.swift"
# ReferenceWriters.swift shares the compression constants and levelFlags of
# CollationKeys, which are private in the product. Widen ONLY those: a
# blanket "private static" -> "static" would also widen helpers whose
# parameter types are private (RegionLevel), which does not compile.
sed -i '' \
  -e 's/^    private static let /    static let /' \
  -e 's/private static func levelFlags/static func levelFlags/' \
  "$OUT/Sources/SKLadder/SortKey.swift"

cat > "$OUT/Package.swift" <<'MANIFEST'
// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "skladder",
    platforms: [.macOS("15")],
    targets: [
        .executableTarget(
            name: "SKLadder",
            path: "Sources/SKLadder",
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
# Ask SwiftPM for the binary folder. A fixed ".build/release" is wrong for the
# newer build system, which writes to ".build/out/Products/Release".
echo "$(swift build -c release --show-bin-path)/SKLadder"
