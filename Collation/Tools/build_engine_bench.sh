#!/bin/zsh
# Assembles and builds the FULL-WMO engine-only bench (see engine-bench/
# main.swift). The engine sources are copied verbatim from the module into a
# scratch package under .build/engine-bench; the resulting binary path is
# printed on stdout. Safe on machine 1: no Locale, so no WMO SIGILL.
set -e
SCRIPT_DIR=${0:A:h}
REPO=${SCRIPT_DIR:h:h}
OUT="$REPO/.build/engine-bench"
ENGINE_SRC="$REPO/Sources/FoundationInternationalization/Collation"

mkdir -p "$OUT/Sources/CollEngine/Resources" "$OUT/Sources/EngineBench"
cp "$ENGINE_SRC"/*.swift "$OUT/Sources/CollEngine/"
cp "$ENGINE_SRC/Resources/ucadata.icu" "$ENGINE_SRC/Resources/ucadata-icu4x.icu" \
   "$ENGINE_SRC/Resources/nfd.bin" "$OUT/Sources/CollEngine/Resources/"
rsync -a --delete "$ENGINE_SRC/Resources/tailorings/" "$OUT/Sources/CollEngine/Resources/tailorings/"
cp "$SCRIPT_DIR/engine-bench/main.swift" "$OUT/Sources/EngineBench/main.swift"

cat > "$OUT/Package.swift" <<'MANIFEST'
// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "enginebench",
    platforms: [.macOS("15")],
    targets: [
        .target(
            name: "CollEngine",
            path: "Sources/CollEngine",
            resources: [
                .copy("Resources/ucadata.icu"),
                .copy("Resources/ucadata-icu4x.icu"),
                .copy("Resources/nfd.bin"),
                .copy("Resources/tailorings"),
            ]
        ),
        .executableTarget(name: "EngineBench", dependencies: ["CollEngine"], path: "Sources/EngineBench"),
    ]
)
MANIFEST

cd "$OUT" && swift build -c release >&2
echo "$OUT/.build/release/EngineBench"
