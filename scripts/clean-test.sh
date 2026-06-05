#!/usr/bin/env bash
# clean-test.sh — full-rebuild test runner
#
# Use this instead of plain `swift test` whenever a refactor touches stored
# properties on widely-imported internal classes (`_CalendarHebrew`,
# `_CalendarGregorian`, `_CalendarICU`, etc.). SPM's incremental compilation
# can leave stale `.swiftmodule` artifacts that reference the old class
# layout, causing SIGSEGV at runtime even though the build succeeds.
#
# Forcing a clean rebuild costs ~5–7 minutes but is far cheaper than
# bisecting code changes that aren't actually wrong.
#
# Usage:
#   ./scripts/clean-test.sh                        # defaults to Calendar|RecurrenceRule|Hebrew
#   ./scripts/clean-test.sh Hebrew
#   ./scripts/clean-test.sh "Calendar|RecurrenceRule"
#
# See backup/BUILD_CACHE_PROTOCOL.md for the full rationale.

set -euo pipefail

# Locate the repo root (assumes this script lives in <repo>/scripts/).
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

FILTER="${1:-Calendar|RecurrenceRule|Hebrew}"

echo "================================================================"
echo "clean-test.sh"
echo "  Repo:   $REPO_ROOT"
echo "  Filter: $FILTER"
echo "================================================================"

export SWIFTCI_USE_LOCAL_DEPS=1

START_TS=$(date +%s)

echo ""
echo "[1/3] Removing .build/*/debug to force full module-info regeneration..."
# Targeted removal — keeps .build/checkouts/, .build/release/, etc.
rm -rf .build/*/debug
echo "      Done."

echo ""
echo "[2/3] swift build (full rebuild — expect ~5–7 min cold)..."
BUILD_START=$(date +%s)
swift build 2>&1 | tail -3
BUILD_ELAPSED=$(( $(date +%s) - BUILD_START ))
echo "      Build complete (${BUILD_ELAPSED}s)."

echo ""
echo "[3/3] swift test --filter \"$FILTER\"..."
TEST_START=$(date +%s)
set +e
swift test --filter "$FILTER" 2>&1 | tee /tmp/clean-test-output.log | grep -E "Test run with|signal code 11|✘ Test|error:"
TEST_EXIT=$?
set -e
TEST_ELAPSED=$(( $(date +%s) - TEST_START ))

TOTAL_ELAPSED=$(( $(date +%s) - START_TS ))

echo ""
echo "================================================================"
if [ $TEST_EXIT -eq 0 ]; then
    echo "✓ PASS  (build ${BUILD_ELAPSED}s + test ${TEST_ELAPSED}s = ${TOTAL_ELAPSED}s total)"
else
    echo "✘ FAIL  (exit $TEST_EXIT)  (build ${BUILD_ELAPSED}s + test ${TEST_ELAPSED}s = ${TOTAL_ELAPSED}s total)"
    echo ""
    echo "Tests failed AFTER a clean build. This is a REAL regression, not"
    echo "a build-cache issue. Full output saved to /tmp/clean-test-output.log."
fi
echo "================================================================"

exit $TEST_EXIT
