#!/bin/zsh
# Assembles and builds the §32/§34 thai probe ladder (see thai-ladder/
# main.swift): §29-style stage-by-stage attribution probes for the thai
# compare/sortKey pipeline, plus the P7 skip-walk statistics. The engine
# sources are copied VERBATIM into a scratch package (repo untouched);
# visibility of a few private entry points is loosened IN THE COPY ONLY so
# the probes (same target) can call them. FULL WMO release; binary path on
# stdout. Same pattern as build_engine_bench.sh.
#
#   Collation/Tools/build_thai_ladder.sh
#   $(...)  Collation/Tools/bench/bench-thai.txt 10
set -e
SCRIPT_DIR=${0:A:h}
REPO=${SCRIPT_DIR:h:h}
OUT="$REPO/.build/thai-ladder"
ENGINE_SRC="$REPO/Sources/FoundationInternationalization/Collation"

mkdir -p "$OUT/Sources/ThaiLadder/Resources"
cp "$ENGINE_SRC"/*.swift "$OUT/Sources/ThaiLadder/"
cp "$ENGINE_SRC/Resources/ucadata.icu" "$ENGINE_SRC/Resources/ucadata-icu4x.icu" \
   "$ENGINE_SRC/Resources/nfd.bin" "$OUT/Sources/ThaiLadder/Resources/"
rsync -a --delete "$ENGINE_SRC/Resources/tailorings/" "$OUT/Sources/ThaiLadder/Resources/tailorings/"
cp "$SCRIPT_DIR/thai-ladder/main.swift" "$OUT/Sources/ThaiLadder/main.swift"

# Visibility loosening — COPY ONLY. Each sed is a no-op if the pattern moved;
# if a probe then fails to compile, re-check the member's name/visibility.
sed -i '' \
  -e 's/private func compareBody/func compareBody/' \
  -e 's/private func takeScratch/func takeScratch/' \
  -e 's/private func giveScratch/func giveScratch/' \
  -e 's/private func unsafeStart/func unsafeStart/' \
  -e 's/private func variableTopValue/func variableTopValue/' \
  "$OUT/Sources/ThaiLadder/RootCollator.swift"

cat > "$OUT/Package.swift" <<'MANIFEST'
// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "thailadder",
    platforms: [.macOS("15")],
    targets: [
        .executableTarget(
            name: "ThaiLadder",
            path: "Sources/ThaiLadder",
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
echo "$OUT/.build/release/ThaiLadder"
