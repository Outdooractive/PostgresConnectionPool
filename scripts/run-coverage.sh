#!/usr/bin/env bash
#
# Run the test suite with code coverage and print the PostgresConnectionPool
# coverage summary.
#
# Integration tests run when POSTGRES_HOSTNAME is set (or POSTGRES_TESTS=1 for
# a local database). Without either, the database-backed suites are skipped and
# the reported coverage is lower.
#
# Usage: scripts/run-coverage.sh [minimum-line-coverage]

set -euo pipefail

MINIMUM="${1:-90}"
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"

# Remove stale profiles so the report only reflects this test run.
BIN=$(swift build --show-bin-path)
rm -rf "$BIN/codecov"

LOG=$(mktemp)
trap 'rm -f "$LOG"' EXIT

set +e
swift build --build-tests --enable-code-coverage > "$LOG" 2>&1
BUILD_STATUS=$?
set -e

if [ "$BUILD_STATUS" -ne 0 ]; then
    cat "$LOG"
    exit "$BUILD_STATUS"
fi

set +e
swift test --skip-build --enable-code-coverage --no-parallel >> "$LOG" 2>&1
STATUS=$?
set -e

cat "$LOG"

if grep -q '✘ Test run with .* failed' "$LOG"; then
    exit 1
fi

if ! grep -q '✔ Test run with .* passed' "$LOG"; then
    echo "Coverage test run did not complete successfully" >&2
    exit "$STATUS"
fi

python3 scripts/coverage.py --minimum "$MINIMUM"
