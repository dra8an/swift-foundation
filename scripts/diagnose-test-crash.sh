#!/usr/bin/env bash
# diagnose-test-crash.sh — auto-bisect "is it the cache or the code?"
#
# If `swift test` crashes with SIGSEGV (signal 11) inside swiftpm-testing-helper,
# this script tells you whether it's the well-known SPM incremental-build cache
# staleness footgun (a stored-property refactor invalidated module info but
# downstream artifacts weren't rebuilt) — or a real code regression.
#
# Strategy:
#   1. Run `swift test` incrementally first. If it passes, you're fine.
#   2. If it crashes with signal 11, force a clean rebuild and try again.
#   3. If clean rebuild passes → it was a cache issue. Reapply your change
#      cleanly via `./scripts/clean-test.sh` going forward.
#   4. If clean rebuild also crashes → real regression. Bisect the code.
#
# Usage:
#   ./scripts/diagnose-test-crash.sh                        # defaults to Calendar|RecurrenceRule|Hebrew
#   ./scripts/diagnose-test-crash.sh Hebrew
#   ./scripts/diagnose-test-crash.sh "Calendar|RecurrenceRule"
#
# See backup/BUILD_CACHE_PROTOCOL.md for the full rationale.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

FILTER="${1:-Calendar|RecurrenceRule|Hebrew}"

echo "================================================================"
echo "diagnose-test-crash.sh"
echo "  Repo:   $REPO_ROOT"
echo "  Filter: $FILTER"
echo "================================================================"

export SWIFTCI_USE_LOCAL_DEPS=1

INCR_LOG=/tmp/diagnose-incremental.log
CLEAN_LOG=/tmp/diagnose-clean.log

echo ""
echo "[1/2] Running tests with incremental build..."
swift test --filter "$FILTER" 2>&1 | tee "$INCR_LOG" | grep -E "Test run with|signal code 11|✘ Test|error:" || true
INCR_EXIT=${PIPESTATUS[0]}

if [ "$INCR_EXIT" -eq 0 ]; then
    echo ""
    echo "================================================================"
    echo "✓ PASS  (incremental build, no crash)"
    echo "================================================================"
    exit 0
fi

# Tests failed. Is it signal 11?
if ! grep -q "signal code 11" "$INCR_LOG"; then
    echo ""
    echo "================================================================"
    echo "✘ FAIL  (incremental exit $INCR_EXIT, but NOT signal 11)"
    echo "================================================================"
    echo "This isn't the build-cache footgun. Probably a real test failure"
    echo "or assertion. Inspect $INCR_LOG for details."
    exit $INCR_EXIT
fi

echo ""
echo "================================================================"
echo "⚠ SIGSEGV (signal 11) detected in incremental run."
echo "  This is the classic SPM stored-property cache footgun."
echo "  Bisecting: full clean rebuild + retest."
echo "================================================================"

echo ""
echo "[2/2] Force clean rebuild + retest..."
rm -rf .build/*/debug
swift build > /dev/null 2>&1
swift test --filter "$FILTER" 2>&1 | tee "$CLEAN_LOG" | grep -E "Test run with|signal code 11|✘ Test|error:" || true
CLEAN_EXIT=${PIPESTATUS[0]}

echo ""
echo "================================================================"
if [ "$CLEAN_EXIT" -eq 0 ]; then
    echo "✓ CACHE STALENESS CONFIRMED"
    echo "  Incremental: signal 11 (exit $INCR_EXIT)"
    echo "  Clean:       PASS  (exit $CLEAN_EXIT)"
    echo ""
    echo "Your code is fine. The crash was SPM's incremental compilation"
    echo "leaving stale module artifacts after a stored-property change."
    echo ""
    echo "Going forward, use ./scripts/clean-test.sh for refactors that"
    echo "touch stored properties on cross-module-imported internal classes."
else
    echo "✘ REAL REGRESSION"
    echo "  Incremental: signal 11 (exit $INCR_EXIT)"
    echo "  Clean:       signal 11 (exit $CLEAN_EXIT)"
    echo ""
    echo "Crash persists after clean rebuild. This is a genuine code bug."
    echo "Bisect via backup/vN-*/ snapshots. Logs:"
    echo "  - Incremental: $INCR_LOG"
    echo "  - Clean:       $CLEAN_LOG"
fi
echo "================================================================"

exit $CLEAN_EXIT
