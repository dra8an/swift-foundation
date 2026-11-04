#!/bin/zsh
# The Swift compiler for the collation tools — sourced by the build scripts in
# this folder (technique log §51 (at)).
#
#   SWIFT   set by the caller: wins.
#   default on Apple Silicon (machine 2): the compiler of the SELECTED Xcode
#           (xcrun), so compiler and SDK always match. Since the macOS 27
#           update (2026-11-04) the selected Xcode's SDK needs Swift 6.5, and
#           the swiftly snapshot (6.4-dev) cannot read it ("this SDK is not
#           supported by the compiler").
#   default elsewhere (machine 1): `swift` from PATH, as before.
#
# Also sets SWIFTC (the swiftc next to SWIFT) and LLDB (Xcode's lldb, which
# has the Python framework that insn-count/ needs; LLDB set by the caller wins).
if [[ -z "$SWIFT" ]]; then
  if [[ "$(uname -m)" == arm64 ]]; then SWIFT="$(xcrun --find swift)"; else SWIFT=swift; fi
fi
if [[ "$SWIFT" == */* ]]; then SWIFTC="${SWIFT:h}/swiftc"; else SWIFTC=swiftc; fi
if [[ -z "$LLDB" ]]; then LLDB="$(xcrun --find lldb)"; fi
# A swiftc called by its path finds no SDK on its own ("unable to load standard
# library for target"); `swift build` passes one. Use the selected Xcode's SDK —
# the one `swift build` uses. `xcrun --show-sdk-path` without `--sdk macosx`
# returned the Command Line Tools SDK on machine 2 (27.2, against 27.5).
if [[ "$(uname -m)" == arm64 && -z "$SDKROOT" ]]; then export SDKROOT="$(xcrun --sdk macosx --show-sdk-path)"; fi
export SWIFT SWIFTC LLDB
