#!/bin/zsh
# Assembles and builds the compare entry ladder (see cmp-ladder/main.swift):
# stage-by-stage attribution of RootCollator.compare on the fast-Latin path,
# the counterpart of build_sk_ladder.sh for sortKey. Stages L0 public entry,
# L0d no-options overload, L1 compareFastPath (no throws), S string pinning
# only, L2 fastLatinUTF8 on bytes pinned before the timer, F the loop floor.
# Stage results are verified against the public entry over the corpus.
# The engine sources are copied VERBATIM into a scratch package (repo
# untouched); visibility of a few private members is widened IN THE COPY
# ONLY. FULL WMO release; binary path on stdout.
#
#   Collation/Tools/build_cmp_ladder.sh
#   $(...)  Collation/Tools/bench/bench-ascii.txt 300
set -e
SCRIPT_DIR=${0:A:h}
REPO=${SCRIPT_DIR:h:h}
OUT="$REPO/.build/cmp-ladder"
ENGINE_SRC="$REPO/Sources/FoundationInternationalization/Collation"

mkdir -p "$OUT/Sources/CmpLadder/Resources"
cp "$ENGINE_SRC"/*.swift "$OUT/Sources/CmpLadder/"
cp "$ENGINE_SRC/Resources/ucadata.icu" "$ENGINE_SRC/Resources/ucadata-icu4x.icu" \
   "$ENGINE_SRC/Resources/nfd.bin" "$OUT/Sources/CmpLadder/Resources/"
rsync -a --delete "$ENGINE_SRC/Resources/tailorings/" "$OUT/Sources/CmpLadder/Resources/tailorings/"
cp "$SCRIPT_DIR/cmp-ladder/main.swift" "$OUT/Sources/CmpLadder/main.swift"

# Visibility widening — COPY ONLY. Each sed is a no-op if the pattern moved;
# if the probe then fails to compile, re-check the member's name/visibility.
sed -i '' \
  -e 's/private func compareFastPath(/func compareFastPath(/' \
  -e 's/private static func fastLatinUTF8(/static func fastLatinUTF8(/' \
  -e 's/private var defaultFLPrimaries:/var defaultFLPrimaries:/' \
  -e 's/private var defaultFLPackedOptions:/var defaultFLPackedOptions:/' \
  -e 's/private var defaultFLWord:/var defaultFLWord:/' \
  -e 's/private var defaultFLSetupPtr:/var defaultFLSetupPtr:/' \
  -e 's/private let storage: Storage/let storage: Storage/' \
  -e 's/private static func quickCJKDispatch(/static func quickCJKDispatch(/' \
  -e 's/private static func mismatchRestartIsUnsafe(/static func mismatchRestartIsUnsafe(/' \
  "$OUT/Sources/CmpLadder/RootCollator.swift"

cat > "$OUT/Package.swift" <<'MANIFEST'
// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "cmpladder",
    platforms: [.macOS("15")],
    targets: [
        .executableTarget(
            name: "CmpLadder",
            path: "Sources/CmpLadder",
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
echo "$(swift build -c release --show-bin-path)/CmpLadder"
