#!/bin/zsh
# Assembles and builds the §41 accented-search probe (see accented-probe/
# main.swift): match-confirmation attribution for search on DECOMPOSING
# text — the nfdMap path that the standard bench corpora barely trigger.
# Three variants per line: A needle-at-end, B needle-at-start, C absent
# (control). The engine sources are copied VERBATIM into a scratch package
# (repo untouched). FULL WMO release; binary path on stdout. Same pattern
# as build_cjk_probe.sh.
#
#   Collation/Tools/build_accented_probe.sh
#   $(...)  Collation/Tools/bench/bench-accented-64.txt 100 [hold A|B|C]
set -e
SCRIPT_DIR=${0:A:h}
REPO=${SCRIPT_DIR:h:h}
OUT="$REPO/.build/accented-probe"
ENGINE_SRC="$REPO/Sources/FoundationInternationalization/Collation"

mkdir -p "$OUT/Sources/AccentedProbe/Resources"
cp "$ENGINE_SRC"/*.swift "$OUT/Sources/AccentedProbe/"
cp "$ENGINE_SRC/Resources/ucadata.icu" "$ENGINE_SRC/Resources/ucadata-icu4x.icu" \
   "$ENGINE_SRC/Resources/nfd.bin" "$OUT/Sources/AccentedProbe/Resources/"
rsync -a --delete "$ENGINE_SRC/Resources/tailorings/" "$OUT/Sources/AccentedProbe/Resources/tailorings/"
cp "$SCRIPT_DIR/accented-probe/main.swift" "$OUT/Sources/AccentedProbe/main.swift"

cat > "$OUT/Package.swift" <<'MANIFEST'
// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "accentedprobe",
    platforms: [.macOS("15")],
    targets: [
        .executableTarget(
            name: "AccentedProbe",
            path: "Sources/AccentedProbe",
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
echo "$OUT/.build/release/AccentedProbe"
