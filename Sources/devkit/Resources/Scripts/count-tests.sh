#!/bin/bash
#
# Checks that every test method of some test files ran, and passed, in a result bundle.
#
#   devkit count-tests [--label <text>] <xcresult> <glob>...
#
# The expected number is the test methods in the files that the globs name (git pathspecs, relative
# to the repository, among the files git tracks). The pattern allows attributes, also with
# arguments such as @available(iOS 18, *), the modifiers public, open, internal, final, override and
# nonisolated before func, and a test that returns nothing. The summary of the bundle comes from
# xcresulttool and must hold exactly that many tests, all passed, none failed, none skipped: a run
# that lost a test class, or has a test that skips itself, passes the build and the coverage floor
# too. Nothing is expected to skip by design here: a job whose tests may skip on some device keeps
# its own reader, which names the tests that may.
#
# --label names the count in every message, such as the platform of the run.
#
# Exit codes: 0 every test ran and passed, 1 the counts disagree (or there is no test method), 2 the
# check could not be made: wrong usage, a search or xcresulttool that failed, a summary that cannot
# be read. A search that fails is never an expected count of 0.

set -euo pipefail

# Functions imported from the caller's environment could replace a tool this script trusts (git, python3):
# only the functions it defines itself count.
while IFS= read -r FUNCTION; do unset -f "$FUNCTION"; done < <(compgen -A function)

if [ -z "${DEVKIT_REPO_ROOT:-}" ] || [ -z "${DEVKIT_RESOURCES:-}" ] || [ -z "${DEVKIT_WORK:-}" ]; then
    echo "count-tests: run it as 'devkit count-tests'" >&2
    exit 2
fi
ROOT="$DEVKIT_REPO_ROOT"

LABEL="count-tests"
if [ "${1:-}" = "--label" ]; then
    if [ "$#" -lt 2 ]; then
        echo "usage: devkit count-tests [--label <text>] <xcresult> <glob>..." >&2
        exit 2
    fi
    LABEL="$2"
    shift 2
fi
if [ "$#" -lt 2 ]; then
    echo "usage: devkit count-tests [--label <text>] <xcresult> <glob>..." >&2
    exit 2
fi
BUNDLE="$1"
shift

ERRORS="$(mktemp "${TMPDIR:-/tmp}/count-tests.XXXXXX")"
trap 'rm -f "$ERRORS"' EXIT

PATTERN='^[[:space:]]*((@[[:alnum:]_]+(\([^)]*\))?|public|open|internal|final|override|nonisolated)[[:space:]]+)*func[[:space:]]+test[[:alnum:]_]*[[:space:]]*\(\)[[:space:]]*(async[[:space:]]*)?(throws[[:space:]]*)?(\{.*|//.*)?$'
SEARCH_STATUS=0
COUNTS="$(git -C "$ROOT" grep -hcE "$PATTERN" -- "$@" 2> "$ERRORS")" || SEARCH_STATUS=$?
# Status 1 is a search that found no test method, which is a count of 0. Anything above is a search that failed.
if [ "$SEARCH_STATUS" -gt 1 ]; then
    echo "$LABEL: the test methods could not be counted: $(tr '\n' ' ' < "$ERRORS")" >&2
    exit 2
fi
EXPECTED="$(printf '%s\n' "$COUNTS" | awk '{ total += $1 } END { print total + 0 }')"

if ! SUMMARY="$(xcrun xcresulttool get test-results summary --path "$BUNDLE" 2> "$ERRORS")"; then
    echo "$LABEL: xcresulttool could not read $BUNDLE: $(tr '\n' ' ' < "$ERRORS")" >&2
    exit 2
fi

# The single quotes hand the Python program to python3 unexpanded. skipcq: SH-2016
# shellcheck disable=SC2016
python3 -c '
import json
import sys

expected, label = int(sys.argv[1]), sys.argv[2]
try:
    summary = json.loads(sys.stdin.read())
except ValueError as error:
    print(f"{label}: the summary of the bundle is not JSON: {error}", file=sys.stderr)
    sys.exit(2)
if not isinstance(summary, dict):
    print(f"{label}: the summary of the bundle is not an object", file=sys.stderr)
    sys.exit(2)
keys = ("totalTestCount", "passedTests", "failedTests", "skippedTests")
actual = {key: summary.get(key) for key in keys}
if not (expected > 0 and actual["totalTestCount"] == expected and actual["passedTests"] == expected
        and actual["failedTests"] == 0 and actual["skippedTests"] == 0):
    print(f"{label}: Expected {expected} tests to run and pass, got {actual}", file=sys.stderr)
    sys.exit(1)
print(f"{label}: all {expected} tests ran and passed.")
' "$EXPECTED" "$LABEL" <<< "$SUMMARY"
